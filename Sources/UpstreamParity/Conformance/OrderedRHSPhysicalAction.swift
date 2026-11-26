import Foundation
import SwiftTLA

/// Reads physical LET operands with a separate lexical scope for each action path.
/// Tags distinguish an original variable from a preceding captured RHS value.
enum OrderedRHSPhysicalAction {
    struct Plan {
        let kinds: [TLAValue]
        let literals: [TLAValue]
        let reads: [TLAValue]
        let left: [TLAValue]
        let right: [TLAValue]
    }

    struct Capture {
        let binding: String
        let rhs: String
        let plan: Plan
        let terms: [String]
        let starts: [Int]
        let guards: [String]
        let additionNodes: [Int]
    }

    struct Action {
        // Index 0 is the first evaluated RHS on this path. A failure site
        // observes only the preceding captures in this array.
        let captures: [Capture]
        // Actual final field references. An overwritten RHS may have no write here.
        let writes: [String: TLAValue]
    }

    struct Conditional {
        struct Definition {
            let binder: BinderID
            let rhs: CompiledExpression
        }

        struct Arm {
            let definitions: [Definition]?
            let action: Action
            let writeOrder: [String]
            let body: String
            let frame: String

            func scalarPlan() -> TLAValue? {
                let captures = action.captures.compactMap { capture -> TLAValue? in
                    let plan = capture.plan
                    guard plan.kinds.count == 1 else { return nil }
                    return plan.kinds[0] == .string("literal") ? .tuple([.string("literal"), plan.literals[0]]) : plan.reads[0]
                }
                guard captures.count == action.captures.count else { return nil }
                let writes = writeOrder.compactMap { target in
                    action.writes[target].map { TLAValue.tuple([.string(target), $0]) }
                }
                guard writes.count == action.writes.count else { return nil }
                return .record(["captures": .tuple(captures), "guards": .tuple([]), "writes": .tuple(writes)])
            }
        }

        let sharedDefinitions: [Definition]?
        let sharedCaptures: [Capture]
        let selectionBody: String
        let condition: TLAValue
        let predicate: String
        let ifTrue: Arm
        let ifFalse: Arm

        func captures(in arm: Arm) -> [Capture] {
            sharedCaptures + arm.action.captures
        }

        // This supplies lexical bindings. The shared guards determine whether the selector is reached.
        func sharedScope(_ body: String) -> String {
            OrderedRHSPhysicalAction.scoped(sharedCaptures[...], body: body)
        }

        func overflowProbes(in rendered: RenderedModule, actionOrdinal: Int, namedHistory: String,
                            regions: [AlternativeFailureRegion], program: CompiledProgram)
            -> (sites: [OverflowProbe], aggregate: String, events: [HistoryCell])? {
            let paths = [captures(in: ifTrue), captures(in: ifFalse)]
            let module = rendered.renderedModuleSource
            let sharedCount = sharedCaptures.count
            guard regions.count == paths.count,
                  zip(paths, regions).enumerated().allSatisfy({ arm, pair in
                      pair.1.armOrdinal == arm && pair.1.sharedBindingCount == sharedCount
                          && pair.0.count == pair.1.bindings.count
                          && zip(pair.0, pair.1.bindings).allSatisfy { capture, binding in
                              capture.binding == program.binderNames[binding.binder]
                          }
                  }),
                  regions[0].bindings.prefix(sharedCount).elementsEqual(regions[1].bindings.prefix(sharedCount), by: {
                      $0.binder == $1.binder && $0.target == $1.target
                  }),
                  let history = actionText(in: module, named: namedHistory)
            else { return nil }

            let owners = [OverflowPath(owner: .sharedPrefix, captures: sharedCaptures, firstOwnedIndex: 0)]
                + paths.enumerated().map { arm, captures in
                    OverflowPath(owner: .arm(arm), captures: captures, firstOwnedIndex: sharedCount)
                }
            guard let evidence = OrderedRHSPhysicalAction.overflowProbes(in: rendered, actionOrdinal: actionOrdinal,
                      probing: owners, requiringNamedBefore: false), let aggregate = evidence.aggregate
            else { return nil }

            let entry = "<<\(program.layout.variables.map(\.formalName).joined(separator: ", "))>>"
            func conditioned(_ condition: String, _ body: String) -> String { "(IF \(condition) THEN \(body) ELSE FALSE)" }
            func reachedAfter(_ prefix: ArraySlice<Capture>, _ failure: String) -> String {
                prefix.reversed().reduce(failure) { body, capture in
                    let bound = "(LET \(capture.binding) == \(capture.rhs) IN \(body))"
                    let guards = capture.additionNodes.map { capture.guards[$0 - 1] }
                    guard let first = guards.first else { return bound }
                    let defined = guards.count == 1 ? first : guards.reversed().reduce("TRUE") { body, guard_ in
                        conditioned(guard_, body)
                    }
                    return conditioned(defined, bound)
                }
            }

            var events: [HistoryCellTemplate] = []
            for probe in evidence.sites {
                let index = probe.row - 1
                let captures: [Capture]
                let region: AlternativeFailureRegion
                let branch: String
                switch probe.owner {
                case .sharedPrefix:
                    captures = sharedCaptures
                    region = regions[0]
                    branch = "<<>>"
                    guard region.sharedIndex(of: region.bindings[index].binder) == index else { return nil }
                case .arm(let arm):
                    captures = paths[arm]
                    region = regions[arm]
                    branch = String(arm)
                    guard region.index(of: region.bindings[index].binder) == index else { return nil }
                }

                let origin = region.bindings[index]
                let prefix = captures.prefix(index)
                let current = captures[index]
                let preceding = current.additionNodes.prefix { $0 != probe.node }.map { current.guards[$0 - 1] }
                let failure = preceding.reversed().reduce("~(\(current.guards[probe.node - 1]))") { body, guard_ in
                    conditioned(guard_, body)
                }
                let reached: String
                switch probe.owner {
                case .sharedPrefix:
                    reached = reachedAfter(prefix, failure)
                case .arm(let arm):
                    let local = reachedAfter(prefix.dropFirst(sharedCount), failure)
                    let selected = arm == 0 ? conditioned(predicate, local) : "(IF \(predicate) THEN FALSE ELSE \(local))"
                    reached = reachedAfter(prefix.prefix(sharedCount), selected)
                }
                guard sameTokens(probe.failed.body, reached) else { return nil }

                let frame = zip(region.bindings.prefix(index), prefix).map { binding, capture in
                    "[binding |-> \(binding.binder.ordinal), target |-> \(binding.target.ordinal), value |-> \(capture.binding)]"
                }.joined(separator: ", ")
                let before = scoped(prefix, body: "<<\(frame)>>")
                let payload = #"<<"integerOverflow", \#(probe.operation.body), \#(probe.operands.body)>>"#
                let header = "<<[source |-> \(entry), action |-> \(actionOrdinal), branch |-> \(branch), "
                    + "site |-> \(origin.binder.ordinal), target |-> \(origin.target.ordinal), payload |-> "
                events.append(.init(guardPrefix: "(IF \(probe.failed.body) THEN ", header: header,
                                    payload: payload, before: before))
            }
            guard events.count == evidence.sites.count,
                  let cells = historyCells(history, matching: events) else { return nil }
            return (evidence.sites, aggregate, cells)
        }
    }

    struct Declaration {
        let name: String
        let body: String

        fileprivate init?(_ line: String) {
            guard let separator = line.range(of: " == ") else { return nil }
            name = String(line[..<separator.lowerBound])
            body = String(line[separator.upperBound...])
        }
    }

    struct HistoryCell {
        let body: String
        let event: String
        let payload: String
        let before: String
    }

    struct OverflowProbe {
        let owner: NativeAlternativeFailure.Location
        let row: Int
        let node: Int
        let failed: Declaration
        let operands: Declaration
        let operation: Declaration
        let before: Declaration?
    }

    private struct OverflowPath {
        let owner: NativeAlternativeFailure.Location
        let captures: [Capture]
        let firstOwnedIndex: Int
    }

    static func overflowProbes(in rendered: RenderedModule, actionOrdinal: Int, paths: [[Capture]],
                               requiringNamedBefore: Bool) -> (sites: [OverflowProbe], aggregate: String?)? {
        let owners = paths.enumerated().map { arm, captures in
            OverflowPath(owner: .arm(arm), captures: captures, firstOwnedIndex: 0)
        }
        return overflowProbes(in: rendered, actionOrdinal: actionOrdinal, probing: owners,
                              requiringNamedBefore: requiringNamedBefore)
    }

    private static func overflowProbes(in rendered: RenderedModule, actionOrdinal: Int, probing paths: [OverflowPath],
                                       requiringNamedBefore: Bool) -> (sites: [OverflowProbe], aggregate: String?)? {
        let locations = paths.flatMap { path in
            path.captures.indices.dropFirst(path.firstOwnedIndex).flatMap { index in
                path.captures[index].additionNodes.map { (path: path, row: index + 1, node: $0) }
            }
        }
        let ordinal = String(actionOrdinal)
        let roles = ["Failure", "Operands", "Operation", "Before"].map { "__SwiftTLAOverflow" + $0 }
        let emittedRoles = requiringNamedBefore ? roles : Array(roles.dropLast())
        let aggregate = "__SwiftTLAAnyEvaluationFailure" + ordinal
        let actionStems = roles.map { $0 + ordinal } + [aggregate]
        let generated = Set(rendered.evaluationFailureDeclarations)
        let module = rendered.renderedModuleSource
        let declarations = module.split(separator: "\n").compactMap { line -> Declaration? in
            let text = String(line)
            guard generated.contains(text), let declaration = Declaration(text),
                  actionStems.contains(where: { stem in
                      declaration.name == stem || declaration.name.hasPrefix(stem + "_")
                  }) else { return nil }
            return declaration
        }
        let expected = locations.indices.flatMap { offset in
            let suffix = ordinal + (offset == 0 ? "" : "_\(offset)")
            return emittedRoles.map { $0 + suffix }
        } + (locations.isEmpty ? [] : [aggregate])
        guard declarations.elementsEqual(expected, by: { named($0, stem: $1) }),
              declarations.allSatisfy({ actionText(in: module, named: $0.name) == $0.body })
        else { return nil }

        var sites: [OverflowProbe] = []
        for (offset, location) in locations.enumerated() {
            let start = offset * emittedRoles.count
            let failed = declarations[start], operands = declarations[start + 1], operation = declarations[start + 2]
            let completed = requiringNamedBefore ? declarations[start + 3] : nil
            let prefix = location.path.captures.prefix(location.row - 1)
            let capture = location.path.captures[location.row - 1]
            let node = location.node - 1
            guard operation.body == #""addition""#,
                  case .int(let left) = capture.plan.left[node], case .int(let right) = capture.plan.right[node],
                  sameTokens(operands.body, scoped(prefix, body: "<<\(capture.terms[left - 1]), \(capture.terms[right - 1])>>"))
            else { return nil }
            if let completed {
                let values = "<<\(prefix.map(\.binding).joined(separator: ", "))>>"
                let projection = scoped(prefix, body: values)
                guard sameTokens(completed.body, "(IF \(failed.name) THEN \(projection) ELSE <<>>)") else { return nil }
            }
            sites.append(.init(owner: location.path.owner, row: location.row, node: location.node, failed: failed,
                               operands: operands, operation: operation, before: completed))
        }
        return (sites, declarations.last?.name)
    }

    private static func named(_ declaration: Declaration, stem: String) -> Bool {
        declaration.name.hasPrefix(stem) && declaration.name.dropFirst(stem.count).allSatisfy { $0 == "_" }
    }

    private static func sameTokens(_ actual: String, _ expected: String) -> Bool {
        guard let expected = StraightLineRenderedActionCheck.tokens(expected) else { return false }
        return StraightLineRenderedActionCheck.tokens(actual) == expected
    }

    private struct HistoryCellTemplate {
        let guardPrefix: String
        let header: String
        let payload: String
        let before: String

        static let beforeLabel = ", before |-> "
        static let eventEnd = "]>>"
        static let cellEnd = " ELSE <<>>)"

        var body: String { guardPrefix + header + payload + Self.beforeLabel + before + Self.eventEnd + Self.cellEnd }
    }

    private static func historyCells(_ history: String, matching expected: [HistoryCellTemplate]) -> [HistoryCell]? {
        guard sameTokens(history, expected.map(\.body).joined(separator: " \\o ")),
              let spans = StraightLineRenderedActionCheck.tokenSpans(history) else { return nil }
        let text = history as NSString
        var offset = 0
        var cells: [HistoryCell] = []
        func width(_ part: String) -> Int? {
            guard let count = StraightLineRenderedActionCheck.tokenSpans(part)?.count, count > 0 else { return nil }
            return count
        }
        func bytes(from start: Int, to end: Int) -> String {
            let location = spans[start].location
            return text.substring(with: NSRange(location: location, length: spans[end - 1].upperBound - location))
        }
        guard let labelWidth = width(HistoryCellTemplate.beforeLabel),
              let eventEndWidth = width(HistoryCellTemplate.eventEnd),
              let cellEndWidth = width(HistoryCellTemplate.cellEnd) else { return nil }
        for event in expected {
            if !cells.isEmpty { offset += 1 } // Token-checked concatenation separator.
            guard let guardWidth = width(event.guardPrefix), let headerWidth = width(event.header),
                  let payloadWidth = width(event.payload), let beforeWidth = width(event.before) else { return nil }
            let eventStart = offset + guardWidth
            let payloadStart = eventStart + headerWidth
            let payloadEnd = payloadStart + payloadWidth
            let beforeStart = payloadEnd + labelWidth
            let beforeEnd = beforeStart + beforeWidth
            let eventEnd = beforeEnd + eventEndWidth
            let end = eventEnd + cellEndWidth
            guard end <= spans.count else { return nil }
            cells.append(.init(body: bytes(from: offset, to: end),
                               event: bytes(from: eventStart, to: eventEnd),
                               payload: bytes(from: payloadStart, to: payloadEnd),
                               before: bytes(from: beforeStart, to: beforeEnd)))
            offset = end
        }
        guard offset == spans.count else { return nil }
        return cells
    }

    private static func scoped(_ captures: ArraySlice<Capture>, body: String) -> String {
        captures.reversed().reduce(body) { text, capture in
            "(LET \(capture.binding) == \(capture.rhs) IN \(text))"
        }
    }

    private enum Node {
        case literal(TLAValue)
        case read(TLAValue)
        case addition(Int, Int)
    }

    private enum Part {
        case token(String)
        case node(Int)
    }

    static func decode(in module: String, action: String, body: CompiledActionExpr,
                       fields: [CompiledVariableLayout], counter: CompiledVariableLayout, destination: String,
                       binderNames: [BinderID: String], assignmentTargets: [BinderID: VariableID])
        -> (action: Action, targets: [String])? {
        guard let text = actionText(in: module, named: action),
              let tokens = StraightLineRenderedActionCheck.tokens(text) else { return nil }
        let rawNames = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.declaration.name) })
        var scope = CaptureScope(reads: originalReads(fields))
        let definitions = tokens.indices.filter { tokens[$0] == "LET" }
        var remaining = body
        if case .and(let assignments, .assign(let id, _)) = body, id == counter.id {
            remaining = assignments
        }
        var captures: [Capture] = []
        var targets: [String] = []
        var continuation = 0
        guard !definitions.isEmpty, definitions.count == assignmentTargets.count else { return nil }
        for offset in definitions {
            guard case .define(let binder, let value, let next) = remaining,
                  offset + 3 < tokens.count,
                  let name = binderNames[binder], tokens[offset + 1].utf8.elementsEqual(name.utf8),
                  let target = assignmentTargets[binder], let field = rawNames[target],
                  tokens[offset + 2] == "==",
                  let end = tokens[(offset + 3)...].firstIndex(of: "IN"),
                  let expression = expression(tokens[(offset + 3)..<end], bindings: scope.reads),
                  matches(expression.plan, value, rawNames: rawNames, captures: scope.positions),
                  let guardParts = additionGuards(tokens, before: offset, count: expression.additionNodes.count),
                  scope.reads[name] == nil, scope.positions[binder] == nil else { return nil }
            let position = captures.count + 1
            scope.reads[name] = .tuple([.string("capture"), .int(position)])
            scope.positions[binder] = position
            captures.append(capture(named: name, rhs: tokens[(offset + 3)..<end],
                                    expression: expression, additionGuards: guardParts))
            targets.append(field)
            remaining = next
            continuation = end + 1
        }
        if case .define = remaining { return nil }
        guard let writes = writes(in: tokens[continuation...], fields: fields,
            bindings: scope.reads, counter: counter.formalName, destination: destination) else { return nil }
        return (.init(captures: captures, writes: writes), targets)
    }

    static func decodeConditional(in module: String, action: CompiledAction, program: CompiledProgram,
                                  retainingDefinitions: Bool = false) -> Conditional? {
        guard action.bindings.isEmpty,
              let label = program.layout.actions.first(where: { $0.id == action.id }),
              let text = actionText(in: module, named: label.renderedName),
              let tokens = StraightLineRenderedActionCheck.tokens(text)
        else { return nil }
        let fields = program.layout.variables
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.formalName) })
        let rawNames = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.declaration.name) })
        var remaining = action.body
        var physical = tokens[...]
        var scope = CaptureScope(reads: originalReads(fields))
        guard let shared = leadingConditionalCaptures(&physical, body: &remaining, scope: &scope,
                  rawNames: rawNames, program: program, retainingDefinitions: retainingDefinitions),
              case .ifElse(let predicate, let yes, let no) = remaining,
              let split = conditional(physical), let yesTokens = parentheses(split.yes),
              let noTokens = parentheses(split.no),
              let condition = comparison(split.condition, predicate: predicate, scope: scope, rawNames: rawNames),
              let first = arm(yesTokens, body: yes, scope: scope, names: names, rawNames: rawNames,
                              program: program, retainingDefinitions: retainingDefinitions),
              let second = arm(noTokens, body: no, scope: scope, names: names, rawNames: rawNames,
                               program: program, retainingDefinitions: retainingDefinitions)
        else { return nil }
        // Do not treat a present guard as a correct one. Match the checked scalar
        // guard/definedness and failure-gating constructions against the same text.
        do {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: text, layout: program.layout,
                binders: program.binderNames, moduleName: program.moduleName, required: true)
        } catch { return nil }
        return .init(sharedDefinitions: shared.definitions, sharedCaptures: shared.captures,
                     selectionBody: physical.joined(separator: " "), condition: condition,
                     predicate: split.condition.joined(separator: " "), ifTrue: first, ifFalse: second)
    }

    private static func actionText(in module: String, named action: String) -> String? {
        let prefix = "\(action) == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(prefix) }
        guard declarations.count == 1, let declaration = declarations.first else { return nil }
        return String(declaration.dropFirst(prefix.count))
    }

    private static func originalReads(_ fields: [CompiledVariableLayout]) -> [String: TLAValue] {
        Dictionary(uniqueKeysWithValues: fields.map {
            ($0.formalName, .tuple([.string("state"), .string($0.declaration.name)]))
        })
    }

    private static func capture(named name: String, rhs: ArraySlice<String>, expression: Expression,
                                additionGuards: [String]) -> Capture {
        var guards = Array(repeating: "TRUE", count: expression.terms.count)
        for (node, guardText) in zip(expression.additionNodes, additionGuards) { guards[node - 1] = guardText }
        return .init(binding: name, rhs: rhs.joined(separator: " "), plan: expression.plan,
                     terms: expression.terms, starts: expression.starts, guards: guards,
                     additionNodes: expression.additionNodes)
    }

    private struct CaptureScope {
        var reads: [String: TLAValue]
        var positions: [BinderID: Int] = [:]
    }

    private static func comparison(_ text: ArraySlice<String>, predicate: CompiledExpression,
                                   scope: CaptureScope, rawNames: [VariableID: String]) -> TLAValue? {
        let comparison: (operation: String, symbol: String)
        switch predicate.operation {
        case .lessThan: comparison = ("lessThan", "<")
        case .equal: comparison = ("equal", "=")
        default: return nil
        }
        guard predicate.resultType == .bool, predicate.children.count == 2,
              let inside = parentheses(text), let separator = inside.firstIndex(of: comparison.symbol),
              let left = expression(inside[..<separator], bindings: scope.reads, allowingBooleans: true),
              let right = expression(inside[(separator + 1)...], bindings: scope.reads, allowingBooleans: true),
              left.plan.kinds.count == 1, right.plan.kinds.count == 1,
              matches(left.plan, predicate.children[0], rawNames: rawNames, captures: scope.positions),
              matches(right.plan, predicate.children[1], rawNames: rawNames, captures: scope.positions)
        else { return nil }
        func term(_ plan: Plan) -> TLAValue {
            plan.kinds[0] == .string("literal") ? .tuple([.string("literal"), plan.literals[0]]) : plan.reads[0]
        }
        return .tuple([.tuple([.string(comparison.operation)]), term(left.plan), term(right.plan)])
    }

    private static func leadingConditionalCaptures(
        _ physical: inout ArraySlice<String>, body remaining: inout CompiledActionExpr, scope: inout CaptureScope,
        rawNames: [VariableID: String], program: CompiledProgram, retainingDefinitions: Bool
    ) -> (captures: [Capture], definitions: [Conditional.Definition]?)? {
        var captures: [Capture] = []
        var definitions: [Conditional.Definition]? = retainingDefinitions ? [] : nil
        while case .define(let binder, let value, let next) = remaining {
            let declaration: ArraySlice<String>
            let guardTokens: ArraySlice<String>?
            if let guarded = conditional(physical) {
                guard guarded.no.elementsEqual(["FALSE"]) else { return nil }
                declaration = guarded.yes
                guardTokens = guarded.condition
            } else {
                declaration = physical
                guardTokens = nil
            }
            guard let inside = parentheses(declaration), inside.count >= 5,
                  inside[inside.startIndex] == "LET", inside[inside.startIndex + 2] == "==",
                  let expectedName = program.binderNames[binder], inside[inside.startIndex + 1] == expectedName,
                  let end = inside.dropFirst(3).firstIndex(of: "IN"),
                  let decoded = expression(inside[(inside.startIndex + 3)..<end], bindings: scope.reads, allowingBooleans: true),
                  matches(decoded.plan, value, rawNames: rawNames, captures: scope.positions),
                  let guards = guardTexts(guardTokens, count: decoded.additionNodes.count),
                  scope.reads[expectedName] == nil, scope.positions[binder] == nil else { return nil }
            let position = scope.positions.count + 1
            scope.reads[expectedName] = .tuple([.string("capture"), .int(position)])
            scope.positions[binder] = position
            definitions?.append(.init(binder: binder, rhs: value))
            captures.append(capture(named: expectedName, rhs: inside[(inside.startIndex + 3)..<end],
                                    expression: decoded, additionGuards: guards))
            physical = inside[(end + 1)...]
            remaining = next
        }

        return (captures, definitions)
    }

    private static func arm(_ tokens: ArraySlice<String>, body: CompiledActionExpr, scope shared: CaptureScope,
                            names: [VariableID: String], rawNames: [VariableID: String],
                            program: CompiledProgram, retainingDefinitions: Bool) -> Conditional.Arm? {
        var scope = shared
        var remaining = body
        var physical = tokens
        guard let local = leadingConditionalCaptures(&physical, body: &remaining, scope: &scope,
                  rawNames: rawNames, program: program, retainingDefinitions: retainingDefinitions) else { return nil }
        let frame = physical.joined(separator: " ")
        var pending: [FramePart] = [.action(remaining)]
        var writes: [String: TLAValue] = [:]
        var order: [String] = []
        func consume(_ token: String) -> Bool {
            guard physical.first == token else { return false }
            physical = physical.dropFirst()
            return true
        }
        while let part = pending.popLast() {
            switch part {
            case .token(let token):
                guard consume(token) else { return nil }
            case .action(.and(let left, let right)):
                pending += [.token(")"), .action(right), .token(#"/\"#), .action(left), .token("(")]
            case .action(.guard_(let condition)):
                guard condition.operation == .value(.boolean(true)), consume("TRUE") else { return nil }
            case .action(.unchanged(let target)):
                guard let formal = names[target], let raw = rawNames[target], consume("UNCHANGED"), consume(formal),
                      writes.updateValue(.tuple([.string("state"), .string(raw)]), forKey: raw) == nil else { return nil }
                order.append(raw)
            case .action(.assign(let target, let value)):
                guard let formal = names[target], let raw = rawNames[target], case .boundValue(let binder) = value.operation,
                      let position = scope.positions[binder], let name = program.binderNames[binder], consume(formal + "'"),
                      consume("="), consume(name), writes.updateValue(.tuple([.string("capture"), .int(position)]),
                                                                     forKey: raw) == nil else { return nil }
                order.append(raw)
            default: return nil
            }
        }
        guard physical.isEmpty, writes.count == names.count else { return nil }
        return .init(definitions: local.definitions, action: .init(captures: local.captures, writes: writes), writeOrder: order,
                     body: tokens.joined(separator: " "), frame: frame)
    }

    private enum FramePart {
        case token(String)
        case action(CompiledActionExpr)
    }

    private static func matches(_ plan: Plan, _ root: CompiledExpression, rawNames: [VariableID: String],
                                captures: [BinderID: Int]) -> Bool {
        var pending = [(plan.kinds.count - 1, root)]
        while let (index, expression) = pending.popLast() {
            switch expression.operation {
            case .value(.integer(let value)):
                guard plan.kinds[index] == .string("literal"), plan.literals[index] == .int(value) else { return false }
            case .value(.boolean(let value)):
                guard plan.kinds[index] == .string("literal"), plan.literals[index] == .bool(value) else { return false }
            case .stateVariable(let id):
                guard let field = rawNames[id], plan.kinds[index] == .string("read"),
                      plan.reads[index] == .tuple([.string("state"), .string(field)]) else { return false }
            case .boundValue(let binder):
                guard let position = captures[binder], plan.kinds[index] == .string("read"),
                      plan.reads[index] == .tuple([.string("capture"), .int(position)]) else { return false }
            case .add:
                guard expression.children.count == 2, plan.kinds[index] == .string("add"),
                      case .int(let left) = plan.left[index], case .int(let right) = plan.right[index]
                else { return false }
                pending.append((right - 1, expression.children[1]))
                pending.append((left - 1, expression.children[0]))
            default: return false
            }
        }
        return true
    }

    private static func parentheses(_ tokens: ArraySlice<String>) -> ArraySlice<String>? {
        guard tokens.first == "(", tokens.last == ")" else { return nil }
        var depth = 0
        for index in tokens.indices {
            if tokens[index] == "(" { depth += 1 }
            if tokens[index] == ")" { depth -= 1 }
            if depth == 0 && index != tokens.endIndex - 1 { return nil }
        }
        return depth == 0 ? tokens.dropFirst().dropLast() : nil
    }

    private static func writes(in tokens: ArraySlice<String>, fields: [CompiledVariableLayout],
                               bindings: [String: TLAValue], counter: String, destination: String) -> [String: TLAValue]? {
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.formalName, $0.declaration.name) })
        var writes: [String: TLAValue] = [:]
        var writesControl = false
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "UNCHANGED" {
                guard index + 1 < tokens.endIndex, let field = names[tokens[index + 1]],
                      writes.updateValue(.tuple([.string("state"), .string(field)]), forKey: field) == nil else { return nil }
                index += 2
            } else if token.hasSuffix("'") {
                guard index + 2 < tokens.endIndex, tokens[index + 1] == "=" else { return nil }
                let name = String(token.dropLast())
                let value = tokens[index + 2]
                if name == counter {
                    guard !writesControl, value == destination else { return nil }
                    writesControl = true
                } else {
                    guard let field = names[name], let reference = bindings[value],
                          writes.updateValue(reference, forKey: field) == nil else { return nil }
                }
                index += 3
            } else {
                switch token {
                case "(", ")", "/\\", "TRUE", "ELSE", "FALSE": break
                default: return nil
                }
                index += 1
            }
        }
        return writesControl && writes.count == fields.count ? writes : nil
    }

    private struct Expression {
        let plan: Plan
        let terms: [String]
        let starts: [Int]
        let additionNodes: [Int]
    }

    private static func expression(_ input: ArraySlice<String>,
                                   bindings: [String: TLAValue], allowingBooleans: Bool = false) -> Expression? {
        var nodes: [Node] = []
        var spans: [ClosedRange<Int>] = []
        var parts: [Part] = []
        var opens: [(part: Int, token: Int)] = []
        func append(_ node: Node, span: ClosedRange<Int>) {
            parts.append(.node(nodes.count))
            nodes.append(node)
            spans.append(span)
        }
        func literal(_ index: Int) -> Int? {
            if case .literal(.int(let value)) = nodes[index] { return value }
            return nil
        }

        for offset in input.indices {
            let token = input[offset]
            switch token {
            case "(":
                opens.append((parts.count, offset))
            case ")":
                guard let open = opens.popLast() else { return nil }
                let group = Array(parts[open.part...])
                parts.removeSubrange(open.part...)
                switch group.count {
                case 3:
                    guard case .node(let first) = group[0], case .token("+") = group[1],
                          case .node(let second) = group[2] else { return nil }
                    append(.addition(first, second), span: open.token...offset)
                case 5: // The normal renderer prints wide integer literals in base 10^9 chunks.
                    guard case .node(let high) = group[0], case .token("*") = group[1],
                          case .node(let radix) = group[2], literal(radix) == 1_000_000_000,
                          case .token(let operatorToken) = group[3], ["+", "-"].contains(operatorToken),
                          case .node(let low) = group[4], let lowValue = literal(low),
                          (0..<1_000_000_000).contains(lowValue), let highValue = literal(high) else { return nil }
                    let product = highValue.multipliedReportingOverflow(by: 1_000_000_000)
                    let wide = product.partialValue.addingReportingOverflow(operatorToken == "+" ? lowValue : -lowValue)
                    guard !product.overflow, !wide.overflow,
                          let canonical = StraightLineRenderedActionCheck.tokens(TLAValue.int(wide.partialValue).description),
                          input[open.token...offset].elementsEqual(canonical) else { return nil }
                    append(.literal(.int(wide.partialValue)), span: open.token...offset)
                default:
                    return nil
                }
            case "+", "*", "-":
                guard !opens.isEmpty else { return nil }
                parts.append(.token(token))
            default:
                if let value = Int(token), String(value) == token {
                    append(.literal(.int(value)), span: offset...offset)
                } else if allowingBooleans, token == "TRUE" || token == "FALSE" {
                    append(.literal(.bool(token == "TRUE")), span: offset...offset)
                } else if let reference = bindings[token] {
                    append(.read(reference), span: offset...offset)
                } else {
                    return nil
                }
            }
        }
        guard opens.isEmpty, parts.count == 1, case .node(let root) = parts[0] else { return nil }

        var order: [Int] = []
        var pending = [root]
        while let index = pending.popLast() {
            order.append(index)
            if case .addition(let left, let right) = nodes[index] {
                pending.append(left)
                pending.append(right)
            }
        }

        var positions: [Int: Int] = [:]
        var kinds: [TLAValue] = [], literals: [TLAValue] = [], reads: [TLAValue] = []
        var left: [TLAValue] = [], right: [TLAValue] = []
        var terms: [String] = [], starts: [Int] = [], additionNodes: [Int] = []
        for index in order.reversed() {
            let position = kinds.count + 1
            terms.append(input[spans[index]].joined(separator: " "))
            switch nodes[index] {
            case .literal(let value):
                starts.append(position)
                kinds.append(.string("literal"))
                literals.append(value)
                reads.append(.tuple([]))
                left.append(.int(0))
                right.append(.int(0))
            case .read(let reference):
                starts.append(position)
                kinds.append(.string("read"))
                literals.append(.int(0))
                reads.append(reference)
                left.append(.int(0))
                right.append(.int(0))
            case .addition(let first, let second):
                kinds.append(.string("add"))
                guard let lhs = positions[first], let rhs = positions[second] else { return nil }
                starts.append(starts[lhs - 1])
                additionNodes.append(position)
                literals.append(.int(0))
                reads.append(.tuple([]))
                left.append(.int(lhs))
                right.append(.int(rhs))
            }
            positions[index] = position
        }
        let plan = Plan(kinds: kinds, literals: literals, reads: reads, left: left, right: right)
        return .init(plan: plan, terms: terms, starts: starts, additionNodes: additionNodes)
    }

    private static func additionGuards(_ tokens: [String], before definition: Int, count: Int) -> [String]? {
        guard definition >= 2, tokens[definition - 1] == "(" else { return nil }
        let then = definition - 2
        if count == 0 { return tokens[then] == "THEN" ? nil : [] }
        guard tokens[then] == "THEN" else { return nil }

        var depth = 0
        var start: Int?
        for index in tokens[..<then].indices.reversed() {
            switch tokens[index] {
            case ")": depth += 1
            case "(": depth -= 1
            case "IF" where depth == 0: start = index + 1
            default: break
            }
            if start != nil || depth < 0 { break }
        }
        guard let start, start < then else { return nil }
        return guardTexts(tokens[start..<then], count: count)
    }

    private static func guardTexts(_ tokens: ArraySlice<String>?, count: Int) -> [String]? {
        guard count > 0 else { return tokens == nil ? [] : nil }
        guard let condition = tokens else { return nil }
        if count == 1 { return [condition.joined(separator: " ")] }

        var remainder = condition
        var guards: [String] = []
        while let split = conditional(remainder), split.no.elementsEqual(["FALSE"]) {
            guards.append(split.condition.joined(separator: " "))
            remainder = split.yes
        }
        guard guards.count == count, remainder.elementsEqual(["TRUE"]) else { return nil }
        return guards
    }

    private static func conditional(_ tokens: ArraySlice<String>)
        -> (condition: ArraySlice<String>, yes: ArraySlice<String>, no: ArraySlice<String>)? {
        guard tokens.count > 6, tokens.first == "(", tokens.last == ")",
              tokens[tokens.startIndex + 1] == "IF" else { return nil }
        var then: Int?
        var depth = 0
        for index in tokens.indices {
            switch tokens[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "THEN" where depth == 1:
                guard then == nil else { return nil }
                then = index
            case "ELSE" where depth == 1:
                guard let then else { return nil }
                return (tokens[(tokens.startIndex + 2)..<then], tokens[(then + 1)..<index],
                        tokens[(index + 1)..<(tokens.endIndex - 1)])
            default: break
            }
        }
        return nil
    }

}
