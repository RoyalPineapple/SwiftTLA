import Foundation

enum StraightLineRenderedActionCheck {
    private enum Task {
        case action(CompiledActionExpr)
        case value(CompiledExpression)
        case token(String)
    }

    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"\s+|==|/\\|[()]|=|[A-Za-z_][A-Za-z0-9_]*'?|-?[0-9]+"#)

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
        while let task = pending.popLast() {
            switch task {
            case .token(let token): expected.append(token)
            case .value(let expression):
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
                default: return
                }
            case .action(let node):
                switch node {
                case .assign(let id, let value):
                    guard let name = variables[id] else { throw mismatch() }
                    schedule([.token("\(name)'"), .token("="), .value(value)])
                case .unchanged(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    schedule([.token("UNCHANGED"), .token(name)])
                case .guard_(let value):
                    guard value.children.isEmpty,
                          value.operation == .value(.boolean(true)) else { return }
                    expected.append("TRUE")
                case .define(let id, let value, let body):
                    guard let name = binders[id], isFormalIdentifier(name),
                          !variables.values.contains(name),
                          usedBinderNames.insert(name).inserted else { return }
                    schedule([.token("("), .token("LET"), .token(name), .token("=="),
                        .value(value), .token("IN"), .action(body), .token(")")])
                case .and(let left, let right):
                    schedule([.token("("), .action(left), .token("/\\"), .action(right), .token(")")])
                default: return
                }
            }
        }
        guard let actual = tokens(rendered), actual == expected else { throw mismatch() }
    }

    static func verifyDeclaration(_ action: CompiledAction, named name: String,
                                  body: String, module: String, layout: CompiledLayout,
                                  binders: [BinderID: String]) throws {
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
