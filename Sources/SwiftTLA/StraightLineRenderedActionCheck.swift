import Foundation

enum StraightLineRenderedActionCheck {
    private enum Task {
        case action(CompiledActionExpr)
        case value(CompiledExpression)
        case token(String)
    }

    private struct AdditionSite {
        let guardText: String
        let operands: String
    }

    private struct AdditionTree {
        let value: String
        let sites: [AdditionSite]

        var defined: String {
            let guards = sites.map(\.guardText)
            return guards.count == 1 ? guards[0] : "(\(guards.joined(separator: " /\\ ")))"
        }
    }

    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"\s+|"(?:[^"\\]|\\.)*"|==|>=|<=|/\\|\\/|-?[0-9]+|[A-Za-z_][A-Za-z0-9_]*'?|[()+*<>-]|="#)

    // shortcut: only direct scalar addition trees are checked here; extend to other expression forms with their output rules.
    private static func addition(_ expression: CompiledExpression,
                                 variables: [VariableID: String],
                                 binders: [BinderID: String]) -> AdditionTree? {
        let swiftIntMinimum = TLAValue.int(.min).description
        let swiftIntMaximum = TLAValue.int(.max).description
        var pending = [(expression, false)]
        var values: [String] = []
        var sites: [AdditionSite] = []
        while let (node, expanded) = pending.popLast() {
            if expanded {
                guard values.count >= 2 else { return nil }
                let rhs = values.removeLast()
                let lhs = values.removeLast()
                values.append("(\(lhs) + \(rhs))")
                let small = "(\(lhs) >= -1000000000 /\\ \(lhs) <= 1000000000 /\\ \(rhs) >= -1000000000 /\\ \(rhs) <= 1000000000)"
                let exact = "(IF \(rhs) > 0 THEN \(lhs) <= \(swiftIntMaximum) - (\(rhs)) ELSE IF \(rhs) < 0 THEN \(lhs) >= \(swiftIntMinimum) - (\(rhs)) ELSE TRUE)"
                sites.append(.init(guardText: "(IF \(small) THEN TRUE ELSE \(exact))",
                    operands: "<<\(lhs), \(rhs)>>"))
                continue
            }
            switch node.operation {
            case .add:
                guard node.resultType == .int, node.children.count == 2 else { return nil }
                pending.append((node, true))
                pending.append((node.children[1], false))
                pending.append((node.children[0], false))
            case .stateVariable(let id):
                guard node.children.isEmpty, let name = variables[id] else { return nil }
                values.append(name)
            case .boundValue(let id):
                guard node.children.isEmpty, let name = binders[id] else { return nil }
                values.append(name)
            case .value(.integer(let value)):
                guard node.children.isEmpty else { return nil }
                values.append(TLAValue.int(value).description)
            default: return nil
            }
        }
        guard values.count == 1, !sites.isEmpty else { return nil }
        return .init(value: values[0], sites: sites)
    }

    static func verify(_ action: CompiledActionExpr, rendered: String,
                       layout: CompiledLayout, binders: [BinderID: String]) throws {
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "tla.action.scalarAssignments",
                expected: "the complete TLA+ action form for the compiled scalar assignment rule",
                actual: "the emitted action body differs from its compiled identities and values",
                nextSafeAction: "Report this TLA+ action emission failure."
            )
        }
        var expected: [String] = []
        var usedBinderNames: Set<String> = []
        var pending: [Task] = [.action(action)]
        func schedule(_ tasks: [Task]) { pending.append(contentsOf: tasks.reversed()) }
        func controlledEquality(_ expression: CompiledExpression) -> Bool {
            guard case .equal = expression.operation, expression.children.count == 2,
                  case .stateVariable(let variable) = expression.children[0].operation,
                  variable == layout.programCounterID(),
                  case .controlLocation = expression.children[1].operation else { return false }
            return true
        }
        func directBoolean(_ expression: CompiledExpression) -> Bool {
            if controlledEquality(expression) { return true }
            guard expression.children.isEmpty else { return false }
            switch expression.operation {
            case .stateVariable, .boundValue, .value(.boolean): return true
            default: return false
            }
        }
        while let task = pending.popLast() {
            switch task {
            case .token(let token): expected.append(token)
            case .value(let expression):
                if controlledEquality(expression) {
                    schedule([.token("("), .value(expression.children[0]), .token("="),
                        .value(expression.children[1]), .token(")")])
                    continue
                }
                if case .add = expression.operation {
                    guard let value = addition(expression, variables: variables, binders: binders),
                          let rendered = tokens(value.value) else { return }
                    expected.append(contentsOf: rendered)
                    continue
                }
                guard expression.children.isEmpty else { return }
                switch expression.operation {
                case .stateVariable(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    expected.append(name)
                case .boundValue(let id):
                    guard let name = binders[id] else { throw mismatch() }
                    expected.append(name)
                case .value(.integer(let value)): expected.append(String(value))
                case .value(.boolean(let value)): expected.append(value ? "TRUE" : "FALSE")
                case .controlLocation(let id):
                    guard let name = layout.controlLocation(id)?.formalName,
                          isFormalIdentifier(name) else { return }
                    expected.append("\"\(name)\"")
                default: return
                }
            case .action(let node):
                switch node {
                case .assign(let id, let value):
                    guard let name = variables[id] else { throw mismatch() }
                    let assignment: [Task] = [.token("\(name)'"), .token("="), .value(value)]
                    if case .add = value.operation,
                       let tree = addition(value, variables: variables, binders: binders) {
                        guard let guardTokens = tokens(tree.defined) else { throw mismatch() }
                        schedule([.token("("), .token("IF")] + guardTokens.map(Task.token)
                            + [.token("THEN")] + assignment
                            + [.token("ELSE"), .token("FALSE"), .token(")")])
                    } else { schedule(assignment) }
                case .unchanged(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    schedule([.token("UNCHANGED"), .token(name)])
                case .guard_(let value):
                    guard directBoolean(value) else { return }
                    if case .value(.boolean) = value.operation {
                        schedule([.value(value)])
                    } else {
                        schedule([.token("("), .value(value), .token(")"),
                            .token("="), .token("TRUE")])
                    }
                case .define(let id, let value, let body):
                    guard let name = binders[id], isFormalIdentifier(name),
                          !variables.values.contains(name),
                          usedBinderNames.insert(name).inserted else { return }
                    let definition: [Task] = [.token("("), .token("LET"), .token(name),
                        .token("=="), .value(value), .token("IN"), .action(body), .token(")")]
                    if case .add = value.operation,
                       let tree = addition(value, variables: variables, binders: binders) {
                        guard let guardTokens = tokens(tree.defined) else { throw mismatch() }
                        schedule([.token("("), .token("IF")] + guardTokens.map(Task.token)
                            + [.token("THEN")] + definition
                            + [.token("ELSE"), .token("FALSE"), .token(")")])
                    } else { schedule(definition) }
                case .and(let left, let right):
                    schedule([.token("("), .action(left), .token("/\\"), .action(right), .token(")")])
                case .or(let left, let right):
                    schedule([.token("("), .action(left), .token("\\/"), .action(right), .token(")")])
                case .ifElse(let condition, let yes, let no):
                    guard directBoolean(condition) else { return }
                    schedule([.token("("), .token("IF"), .value(condition), .token("THEN"),
                        .token("("), .action(yes), .token(")"), .token("ELSE"),
                        .token("("), .action(no), .token(")"), .token(")")])
                default: return
                }
            }
        }
        guard let actual = tokens(rendered), actual == expected else { throw mismatch() }
    }

    static func verifyDeclaration(_ action: CompiledAction, named name: String,
                                  body: String, module: String, layout: CompiledLayout,
                                  binders: [BinderID: String],
                                  failureDeclarations: [String]) throws {
        try verify(action.body, rendered: body, layout: layout, binders: binders)
        let parameters = try action.bindings.map { binding -> String in
            guard let name = binders[binding.binder], isFormalIdentifier(name) else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
                    stage: .validation, path: "tla.action.parameters",
                    expected: "a rendered parameter for each compiled binder",
                    actual: "a compiled binder has no valid rendered name",
                    nextSafeAction: "Report this TLA+ action emission failure.")
            }
            return name
        }
        let header = parameters.isEmpty ? name : "\(name)(\(parameters.joined(separator: ", ")))"
        try verifyRenderedActionDeclarations(module,
            declarations: [(header, "\(header) == \(body)")])
        try verifyAdditionFailures(action, module: module, layout: layout,
            binders: binders, parameters: parameters,
            failureDeclarations: failureDeclarations)
    }

    private static func verifyAdditionFailures(_ action: CompiledAction, module: String,
                                               layout: CompiledLayout, binders: [BinderID: String],
                                               parameters: [String],
                                               failureDeclarations: [String]) throws {
        // shortcut: branching or multiply-fallible continuations need their own failure rule.
        let programCounter = layout.programCounterID()
        func controlWrite(_ node: CompiledActionExpr) -> Bool {
            guard case .assign(let id, let value) = node, id == programCounter,
                  case .controlLocation = value.operation, value.children.isEmpty else { return false }
            return true
        }
        var body = action.body
        var selection: String?
        if case .and(.guard_(let condition), let guardedBody) = body,
           case .equal = condition.operation, condition.children.count == 2,
           case .stateVariable(let id) = condition.children[0].operation,
           id == programCounter,
           case .controlLocation(let location) = condition.children[1].operation,
           let variableName = layout.variables.first(where: { $0.id == id })?.declaration.name,
           let locationName = layout.controlLocation(location)?.formalName {
            selection = "(\(variableName) = \"\(locationName)\")"
            body = guardedBody
        }
        if case .and(let assignment, let tail) = body, controlWrite(tail) { body = assignment }
        guard case .define(let binder, let expression, let continuation) = body,
              case .add = expression.operation,
              binders[binder] != nil,
              let tree = addition(expression,
                  variables: Dictionary(uniqueKeysWithValues: layout.variables.map {
                      ($0.id, $0.declaration.name)
                  }), binders: binders) else { return }
        var assigned = false
        var pending = [continuation]
        while let node = pending.popLast() {
            switch node {
            case .assign(_, let value):
                if controlWrite(node) { break }
                guard !assigned, case .boundValue(let usedBinder) = value.operation,
                      usedBinder == binder, value.children.isEmpty else { return }
                assigned = true
            case .unchanged: break
            case .guard_(let condition):
                guard case .value(.boolean(true)) = condition.operation,
                      condition.children.isEmpty else { return }
            case .and(let left, let right):
                pending.append(right)
                pending.append(left)
            default: return
            }
        }
        guard assigned else { return }
        func mismatch(_ name: String) -> CompilationDiagnostic {
            CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.evaluationFailures.\(name)",
                expected: "the captured addition's ordered failure and operand declarations",
                actual: "a generated declaration differs or is missing",
                nextSafeAction: "Regenerate the TLA+ failure declarations from the compiled action.")
        }
        let index = action.id.ordinal
        let parameterSuffix = parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))"
        let lines = module.components(separatedBy: "\n")
        func verifyDeclaration(_ base: String, value: String) throws {
            // The emitter may append underscores when an authored symbol owns the base name.
            let candidates = failureDeclarations.filter { declaration in
                guard let header = declaration.components(separatedBy: " == ").first,
                      header.hasSuffix(parameterSuffix) else { return false }
                let name = String(header.dropLast(parameterSuffix.count))
                return name.hasPrefix(base) && name.dropFirst(base.count).allSatisfy { $0 == "_" }
            }
            guard candidates.count == 1,
                  let header = candidates[0].components(separatedBy: " == ").first else {
                throw mismatch(base)
            }
            let expected = "\(header) == \(value)"
            guard candidates[0] == expected,
                  lines.filter({ $0.hasPrefix("\(header) == ") }) == [expected] else {
                throw mismatch(base)
            }
        }
        var preceding: [String] = []
        for (position, site) in tree.sites.enumerated() {
            let suffix = position == 0 ? "\(index)" : "\(index)_\(position)"
            let unselected = preceding.isEmpty ? "~(\(site.guardText))"
                : "(\(preceding.joined(separator: " /\\ ")) /\\ ~(\(site.guardText)))"
            let predicate = selection.map { "((\($0)) = TRUE /\\ \(unselected))" } ?? unselected
            let expected = [
                ("__SwiftTLAOverflowFailure\(suffix)", predicate),
                ("__SwiftTLAOverflowOperands\(suffix)", site.operands),
                ("__SwiftTLAOverflowOperation\(suffix)", "\"addition\""),
            ]
            for (name, value) in expected {
                try verifyDeclaration(name, value: value)
            }
            preceding.append(site.guardText)
        }
        let aggregateName = "__SwiftTLAAnyEvaluationFailure\(index)"
        let failure = "~(\(tree.defined))"
        try verifyDeclaration(aggregateName,
            value: selection.map { "(IF \($0) THEN \(failure) ELSE FALSE)" } ?? failure)
    }

    static func verifyFiniteInvocations(_ behavior: CompiledBehavior,
                                        layout: CompiledLayout, binders: [BinderID: String],
                                        module: String) throws {
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
                stage: .validation, path: "tla.Next.finiteInvocations",
                expected: "every compiled finite action call exactly once in the emitted Next relation",
                actual: "a call alias or the complete Next disjunction differs",
                nextSafeAction: "Report this TLA+ action-call emission failure.")
        }
        guard behavior.actions.count == layout.actions.count else { throw mismatch() }
        let included = layout.actions.indices.filter { !layout.actions[$0].declaration.name.isEmpty }
        guard !layout.variables.isEmpty || !included.isEmpty else { return }
        let enabled = Set(behavior.enabledActionIndices)
        func values(_ binding: CompiledActionBinding) -> [CompiledValue]? {
            guard case .set(let element) = binding.domain.resultType,
                  element == .int || element == .bool else { return nil }
            let members: [CompiledValue]
            if let literal = binding.literalMembers {
                members = literal
            } else if case .value(.set(let set)) = binding.domain.operation {
                members = set.sorted()
            } else { return nil }
            guard members.allSatisfy({ value in
                switch (value, element) {
                case (.integer, .int), (.boolean, .bool): true
                default: false
                }
            }) else { return nil }
            return members
        }
        func scalar(_ value: CompiledValue) -> String {
            switch value {
            case .integer(let integer): String(integer)
            case .boolean(let boolean): boolean ? "TRUE" : "FALSE"
            default: preconditionFailure("finite invocation preflight rejected non-scalar values")
            }
        }
        // shortcut: state-dependent and non-scalar domains need their own invocation rule; extend this check when those rules exist.
        guard included.allSatisfy({ index in
            enabled.contains(index) && behavior.actions[index].bindings.allSatisfy { values($0) != nil }
        }) else { return }

        var invocations: [String] = []
        var aliases: [(header: String, definition: String)] = []
        for index in included {
            let name = layout.actions[index].renderedName
            let bindings = behavior.actions[index].bindings
            if bindings.contains(where: { $0.literalMembers == nil }) {
                let names = try bindings.map { binding in
                    guard let name = binders[binding.binder] else { throw mismatch() }
                    return name
                }
                let domains = zip(names, bindings).map { binder, binding in
                    let members = Set(values(binding)!).sorted().map(scalar).joined(separator: ", ")
                    return "\(binder) \\in {\(members)}"
                }
                let call = "\(name)(\(names.joined(separator: ", ")))"
                invocations.append(domains.reversed().reduce(call) { "(\\E \($1): \($0))" })
                continue
            }
            var tuples: [(arguments: [String], indices: [Int])] = [([], [])]
            for binding in bindings {
                let values = values(binding)!.map(scalar)
                tuples = tuples.flatMap { tuple in
                    values.enumerated().map { offset, value in
                        (tuple.arguments + [value], tuple.indices + [offset])
                    }
                }
            }
            for tuple in tuples {
                if tuple.indices.isEmpty {
                    invocations.append(name)
                } else {
                    let alias = name + "__" + tuple.indices.map(String.init).joined(separator: "_")
                    invocations.append(alias)
                    aliases.append((alias, "\(alias) == \(name)(\(tuple.arguments.joined(separator: ", ")))"))
                }
            }
        }
        try verifyRenderedActionDeclarations(module, declarations: aliases)
        if invocations == ["Next"] { return }
        let expected: String
        switch invocations.count {
        case 0: expected = "Next == FALSE"
        case 1: expected = "Next == \(invocations[0])"
        default: expected = "Next ==\n" + invocations.map { "  \\/ \($0)" }.joined(separator: "\n")
        }
        let lines = module.components(separatedBy: "\n")
        let starts = lines.indices.filter { lines[$0] == "Next ==" || lines[$0].hasPrefix("Next == ") }
        guard starts.count == 1, let start = starts.first, start + 1 < lines.count,
              let end = lines[(start + 1)...].firstIndex(of: ""),
              lines[start..<end].joined(separator: "\n") == expected else { throw mismatch() }
    }

    private static func tokens(_ source: String) -> [String]? {
        guard let tokenPattern else { return nil }
        let text = source as NSString
        var offset = 0
        var result: [String] = []
        while offset < text.length {
            guard let match = tokenPattern.firstMatch(in: source,
                    range: NSRange(location: offset, length: text.length - offset)),
                  match.range.location == offset else { return nil }
            let token = text.substring(with: match.range)
            if token.first?.isWhitespace == false { result.append(token) }
            offset = match.range.upperBound
        }
        return result
    }
}
