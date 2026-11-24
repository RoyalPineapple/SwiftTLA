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
        struct Arm {
            let action: Action
            let writeOrder: [String]

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

        let condition: TLAValue
        let ifTrue: Arm
        let ifFalse: Arm
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
                       fields: [CompiledVariableLayout], counter: CompiledVariableLayout, destination: String) -> Action? {
        guard let text = actionText(in: module, named: action),
              let tokens = StraightLineRenderedActionCheck.tokens(text) else { return nil }
        var bindings = originalReads(fields)
        let definitions = tokens.indices.filter { tokens[$0] == "LET" }
        var remaining = body
        if case .and(let assignments, .assign(let id, _)) = body, id == counter.id {
            remaining = assignments
        }
        var captures: [Capture] = []
        var continuation = 0
        for offset in definitions {
            guard case .define(_, _, let next) = remaining,
                  offset + 3 < tokens.count,
                  tokens[offset + 2] == "==",
                  let end = tokens[(offset + 3)...].firstIndex(of: "IN"),
                  let expression = expression(tokens[(offset + 3)..<end], bindings: bindings),
                  let guardParts = additionGuards(tokens, before: offset, count: expression.additionNodes.count),
                  bindings.updateValue(.tuple([.string("capture"), .int(captures.count + 1)]),
                                       forKey: tokens[offset + 1]) == nil else { return nil }
            captures.append(capture(named: tokens[offset + 1], rhs: tokens[(offset + 3)..<end],
                                    expression: expression, additionGuards: guardParts))
            remaining = next
            continuation = end + 1
        }
        guard !captures.isEmpty else { return nil }
        if case .define = remaining { return nil }
        guard let writes = writes(in: tokens[continuation...], fields: fields,
            bindings: bindings, counter: counter.formalName, destination: destination) else { return nil }
        return .init(captures: captures, writes: writes)
    }

    static func decodeConditional(in module: String, action: CompiledAction,
                                  program: CompiledProgram) -> Conditional? {
        guard action.bindings.isEmpty, case .ifElse(let predicate, let yes, let no) = action.body,
              let label = program.layout.actions.first(where: { $0.id == action.id }),
              let text = actionText(in: module, named: label.renderedName),
              let tokens = StraightLineRenderedActionCheck.tokens(text), let split = conditional(tokens[...]),
              let yesTokens = parentheses(split.yes), let noTokens = parentheses(split.no)
        else { return nil }
        let fields = program.layout.variables
        let reads = originalReads(fields)
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.formalName) })
        let rawNames = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.declaration.name) })
        guard let condition = comparison(split.condition, predicate: predicate, reads: reads, rawNames: rawNames),
              let first = arm(yesTokens, body: yes, reads: reads, names: names, rawNames: rawNames, program: program),
              let second = arm(noTokens, body: no, reads: reads, names: names, rawNames: rawNames, program: program)
        else { return nil }
        // Do not treat a present guard as a correct one. Match the checked scalar
        // guard/definedness and failure-gating constructions against the same text.
        do {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: text, layout: program.layout,
                binders: program.binderNames, moduleName: program.moduleName, required: true)
        } catch { return nil }
        return .init(condition: condition, ifTrue: first, ifFalse: second)
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

    private static func comparison(_ text: ArraySlice<String>, predicate: CompiledExpression,
                                   reads: [String: TLAValue], rawNames: [VariableID: String]) -> TLAValue? {
        let comparison: (operation: String, symbol: String)
        switch predicate.operation {
        case .lessThan: comparison = ("lessThan", "<")
        case .equal: comparison = ("equal", "=")
        default: return nil
        }
        guard predicate.resultType == .bool, predicate.children.count == 2,
              let inside = parentheses(text), let separator = inside.firstIndex(of: comparison.symbol),
              let left = expression(inside[..<separator], bindings: reads, allowingBooleans: true),
              let right = expression(inside[(separator + 1)...], bindings: reads, allowingBooleans: true),
              left.plan.kinds.count == 1, right.plan.kinds.count == 1,
              matches(left.plan, predicate.children[0], rawNames: rawNames, captures: [:]),
              matches(right.plan, predicate.children[1], rawNames: rawNames, captures: [:])
        else { return nil }
        func term(_ plan: Plan) -> TLAValue {
            plan.kinds[0] == .string("literal") ? .tuple([.string("literal"), plan.literals[0]]) : plan.reads[0]
        }
        return .tuple([.tuple([.string(comparison.operation)]), term(left.plan), term(right.plan)])
    }

    private static func arm(_ tokens: ArraySlice<String>, body: CompiledActionExpr, reads: [String: TLAValue],
                            names: [VariableID: String], rawNames: [VariableID: String],
                            program: CompiledProgram) -> Conditional.Arm? {
        var bindings = reads
        var positions: [BinderID: Int] = [:]
        var captures: [Capture] = []
        var remaining = body
        var physical = tokens
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
                  let decoded = expression(inside[(inside.startIndex + 3)..<end], bindings: bindings, allowingBooleans: true),
                  matches(decoded.plan, value, rawNames: rawNames, captures: positions),
                  let guards = guardTexts(guardTokens, count: decoded.additionNodes.count),
                  bindings.updateValue(.tuple([.string("capture"), .int(captures.count + 1)]), forKey: expectedName) == nil,
                  positions.updateValue(captures.count + 1, forKey: binder) == nil else { return nil }
            captures.append(capture(named: expectedName, rhs: inside[(inside.startIndex + 3)..<end],
                                    expression: decoded, additionGuards: guards))
            physical = inside[(end + 1)...]
            remaining = next
        }

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
                      let position = positions[binder], let name = program.binderNames[binder], consume(formal + "'"),
                      consume("="), consume(name), writes.updateValue(.tuple([.string("capture"), .int(position)]),
                                                                     forKey: raw) == nil else { return nil }
                order.append(raw)
            default: return nil
            }
        }
        guard physical.isEmpty, writes.count == names.count else { return nil }
        return .init(action: .init(captures: captures, writes: writes), writeOrder: order)
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
