import Foundation

enum StraightLineRenderedActionCheck {
    private enum StructureTask {
        case action(CompiledActionExpr)
        case text(String)
    }

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
            return guards.count == 1 ? guards[0] : guards.reversed().reduce("TRUE") { result, guard_ in
                "(IF \(guard_) THEN \(result) ELSE FALSE)"
            }
        }
    }

    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"\s+|"(?:[^"\\]|\\.)*"|==|>=|<=|/\\|\\/|-?[0-9]+|[A-Za-z_][A-Za-z0-9_]*'?|[(),{}+*<>-]|="#)

    private static func checkedIntegerLiteral(_ value: Int) -> String {
        let radix = 1_000_000_000
        guard value.magnitude > UInt(radix) else { return String(value) }
        let digits = Array(String(value.magnitude))
        let firstCount = (digits.count - 1) % 9 + 1
        let negative = value < 0
        var result = (negative ? "-" : "") + String(digits[..<firstCount])
        for start in stride(from: firstCount, to: digits.count, by: 9) {
            let remainder = Int(String(digits[start..<(start + 9)]))!
            result = "(\(result) * \(radix) \(negative ? "-" : "+") \(remainder))"
        }
        return result
    }

    static func verifyStructure(_ action: CompiledActionExpr, rendered: String,
                                renderer: CompiledTLARenderer) throws {
        let names = Dictionary(uniqueKeysWithValues: renderer.layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "tla.action.structure",
                expected: "the compiled action constructors and state-variable identities",
                actual: "the emitted TLA+ action body differs from that structure",
                nextSafeAction: "Report this TLA+ action emission failure.")
        }
        var pending: [StructureTask] = [.action(action)]
        var parts: [String] = []
        func schedule(_ tasks: [StructureTask]) { pending.append(contentsOf: tasks.reversed()) }
        while let task = pending.popLast() {
            switch task {
            case .text(let value): parts.append(value)
            case .action(let node):
                switch node {
                case .assign(let id, let value):
                    guard let name = names[id] else { throw mismatch() }
                    let assignment = "\(name)' = \(try renderer.state(value))"
                    let defined = try renderer.evaluationDefined(value)
                    parts.append(defined.map { "(IF \($0) THEN \(assignment) ELSE FALSE)" } ?? assignment)
                case .unchanged(let id):
                    guard let name = names[id] else { throw mismatch() }
                    parts.append("UNCHANGED \(name)")
                case .guard_(let condition):
                    let predicate = try renderer.state(condition)
                    let body: String
                    if case .value(.boolean) = condition.operation {
                        body = predicate
                    } else {
                        body = "(\(predicate)) = TRUE"
                    }
                    let defined = try renderer.evaluationDefined(condition)
                    parts.append(defined.map { "(IF \($0) THEN \(body) ELSE FALSE)" } ?? body)
                case .existsAction(let binder, let domain, let body):
                    guard let name = renderer.bindings.binders[binder] else { throw mismatch() }
                    let defined = try renderer.evaluationDefined(domain)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(\\E \(name) \\in \(try renderer.state(domain)): ")
                    schedule([.action(body), .text(defined == nil ? ")" : ") ELSE FALSE)")])
                case .define(let binder, let value, let body):
                    guard let name = renderer.bindings.binders[binder] else { throw mismatch() }
                    let defined = try renderer.evaluationDefined(value)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(LET \(name) == \(try renderer.state(value)) IN ")
                    schedule([.action(body), .text(defined == nil ? ")" : ") ELSE FALSE)")])
                case .ifElse(let condition, let yes, let no):
                    let defined = try renderer.evaluationDefined(condition)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(IF \(try renderer.state(condition)) THEN (")
                    schedule([.action(yes), .text(") ELSE ("), .action(no),
                        .text(defined == nil ? "))" : ")) ELSE FALSE)")])
                case .and(let left, let right):
                    parts.append("(")
                    schedule([.action(left), .text(" /\\ "), .action(right), .text(")")])
                case .or(let left, let right):
                    parts.append("(")
                    schedule([.action(left), .text(" \\/ "), .action(right), .text(")")])
                }
            }
        }
        guard parts.joined() == rendered else { throw mismatch() }
    }

    // shortcut: only direct scalar addition trees are checked here; extend to other expression forms with their output rules.
    private static func addition(_ expression: CompiledExpression,
                                 variables: [VariableID: String],
                                 binders: [BinderID: String]) -> AdditionTree? {
        let swiftIntMinimum = checkedIntegerLiteral(.min)
        let swiftIntMaximum = checkedIntegerLiteral(.max)
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
                // Rendered expressions can precede type resolution; the accepted rule checks Int operands.
                guard (node.resultType == .int || node.resultType == .unknown),
                      node.children.count == 2 else { return nil }
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
                values.append(checkedIntegerLiteral(value))
            default: return nil
            }
        }
        guard values.count == 1, !sites.isEmpty else { return nil }
        return .init(value: values[0], sites: sites)
    }

    static func initialIntPredicate(_ expression: CompiledExpression, named name: String,
                                    layout: CompiledLayout) -> String? {
        guard expression.resultType == .int ||
                (expression.resultType == .unknown && layout.variables.contains {
                    $0.declaration.name == name && $0.generatedSwiftType == "Int"
                }) else { return nil }
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        switch expression.operation {
        case .stateVariable(let id) where expression.children.isEmpty:
            return variables[id].map { "\(name) = \($0)" }
        case .add:
            guard let tree = addition(expression, variables: variables, binders: [:]) else { return nil }
            return "(IF \(tree.defined) THEN \(name) = \(tree.value) ELSE FALSE)"
        default: return nil
        }
    }

    static func requiresInitialIntFailureRecord(_ behavior: CompiledBehavior,
                                                layout: CompiledLayout) -> Bool {
        guard layout.parameters.isEmpty, behavior.initialInvariant == nil,
              !behavior.initializations.isEmpty,
              behavior.initializations.count == layout.variables.count else { return false }
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map { ($0.id, $0) })
        var hasAddition = false
        for initialization in behavior.initializations {
            guard let variable = variables[initialization.variable],
                  case .value(let expression) = initialization.initialization else { return false }
            switch expression.operation {
            case .value(.integer):
                guard variable.generatedSwiftType == "Int", expression.resultType == .int,
                      expression.children.isEmpty else { return false }
            case .controlLocation(let id):
                guard variable.declaration.origin == .programCounter,
                      expression.resultType == .controlLocation,
                      expression.children.isEmpty, layout.controlLocation(id) != nil else { return false }
            case .stateVariable, .add:
                guard variable.generatedSwiftType == "Int", expression.resultType == .int,
                      initialIntPredicate(expression, named: variable.declaration.name,
                        layout: layout) != nil else { return false }
                if case .add = expression.operation { hasAddition = true }
            default: return false
            }
        }
        return hasAddition
    }

    static func verifyInitialAdditionFailures(
        _ expression: CompiledExpression,
        after prefix: ArraySlice<(variable: VariableID, initialization: CompiledVariableInitialization)>,
        names: [VariableID: String],
        emitted: [(failure: RenderedEvaluationFailure, relation: String,
                   operandsName: String?, selection: String,
                   operationDeclaration: String?, record: String?)],
        siteOrdinal: Int?,
        layout: CompiledLayout,
        binders: [BinderID: String] = [:]
    ) throws {
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.initialEvaluationFailures",
                expected: "the checked additions' ordered initial failure relations",
                actual: "an initial failure, operand, or prefix guard differs from its compiled expression",
                nextSafeAction: "Regenerate the TLA+ initial failure declarations.")
        }
        guard let tree = addition(expression, variables: names, binders: binders) else {
            if case .add = expression.operation { throw mismatch() }
            return
        }
        func initialValue(_ expression: CompiledExpression) -> (value: String, defined: String?)? {
            guard expression.children.isEmpty else {
                guard let tree = addition(expression, variables: names, binders: binders) else { return nil }
                return (tree.value, tree.defined)
            }
            switch expression.operation {
            case .stateVariable(let id):
                return names[id].map { ($0, nil) }
            case .value(.integer(let value)):
                return (checkedIntegerLiteral(value), nil)
            case .controlLocation(let id):
                return layout.controlLocation(id).map {
                    (TLAValue.string($0.formalName).description, nil)
                }
            default: return nil
            }
        }
        var earlier: [(name: String, value: String, defined: String?)] = []
        for prior in prefix {
            guard case .value(let expression) = prior.initialization,
                  let name = names[prior.variable],
                  let value = initialValue(expression) else { return }
            earlier.append((name, value.value, value.defined))
        }
        guard emitted.count == tree.sites.count else { throw mismatch() }
        var preceding: [String] = []
        for (site, output) in zip(tree.sites, emitted) {
            guard case .overflow(.addition) = output.failure.kind,
                  let operandsName = output.operandsName,
                  let operation = output.operationDeclaration?.components(separatedBy: " == "),
                  operation.count == 2,
                  operation[0].hasPrefix("__SwiftTLA"),
                  operation[0].contains("OverflowOperation"),
                  operation[1] == "\"addition\"",
                  output.failure.operands == site.operands else { throw mismatch() }
            let predicate = preceding.reversed().reduce("~(\(site.guardText))") { value, guard_ in
                "(IF \(guard_) THEN \(value) ELSE FALSE)"
            }
            var relation = "(IF \(predicate) THEN \(operandsName) = \(site.operands) ELSE FALSE)"
            var selection = predicate
            var record = siteOrdinal.map { ordinal in
                "(IF \(predicate) THEN [site |-> \(ordinal), kind |-> \"integerOverflow.addition\", operands |-> \(site.operands)] ELSE FALSE)"
            }
            for prior in earlier.reversed() {
                relation = "(LET \(prior.name) == \(prior.value) IN \(relation))"
                selection = "(LET \(prior.name) == \(prior.value) IN \(selection))"
                record = record.map { "(LET \(prior.name) == \(prior.value) IN \($0))" }
                if let defined = prior.defined {
                    relation = "(IF \(defined) THEN \(relation) ELSE FALSE)"
                    selection = "(IF \(defined) THEN \(selection) ELSE FALSE)"
                    record = record.map { "(IF \(defined) THEN \($0) ELSE FALSE)" }
                }
            }
            guard output.failure.predicate == predicate,
                  output.relation == relation, output.selection == selection,
                  output.record == record else {
                throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                    path: "tla.initialEvaluationFailures",
                    expected: "\(relation) and \(selection)",
                    actual: "\(output.relation) and \(output.selection)",
                    nextSafeAction: "Regenerate the TLA+ initial failure declarations.")
            }
            preceding.append(site.guardText)
        }
    }

    static func verifyInitialFailureAggregate(_ module: String, predicates: [String],
                                              name: String?) throws {
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.initialEvaluationAggregate",
                expected: "the complete constant-level initial failure predicate",
                actual: "the emitted initial failure predicate is absent or differs",
                nextSafeAction: "Regenerate the TLA+ initial failure predicate.")
        }
        guard let name else {
            guard predicates.isEmpty else { throw mismatch() }
            return
        }
        guard name.hasPrefix("__SwiftTLAAnyInitialEvaluationFailure"),
              name.dropFirst("__SwiftTLAAnyInitialEvaluationFailure".count)
                .allSatisfy({ $0 == "_" }),
              !predicates.isEmpty else { throw mismatch() }
        let expected = "\(name) == " + predicates.map { "(\($0))" }.joined(separator: " \\/ ")
        guard module.components(separatedBy: "\n").filter({ $0.hasPrefix("\(name) == ") })
                == [expected] else { throw mismatch() }
    }

    static func verifyInitialFailureRecord(_ module: String, name: String?,
                                           predicates: [String], records: [String],
                                           required: Bool) throws {
        guard let name else {
            guard !required else { throw initialFailureRecordMismatch() }
            return
        }
        let selected = Array(zip(predicates, records)).reversed().reduce("FALSE") { rest, entry in
            "(IF \(entry.0) THEN \(entry.1) ELSE \(rest))"
        }
        let expected = "\(name) == \(selected)"
        guard !records.isEmpty, predicates.count == records.count else {
            throw initialFailureRecordMismatch()
        }
        try verifyInitialFailureRecord(module, declaration: expected)
    }

    private static func initialFailureRecordMismatch() -> CompilationDiagnostic {
        CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
            path: "tla.initialEvaluationFailureRecord",
            expected: "the selected initial failure site, kind, and operands",
            actual: "the emitted selected initial failure record is absent or differs",
            nextSafeAction: "Regenerate the TLA+ initial failure record.")
    }

    static func verifyInitialFailureRecord(_ module: String, declaration: String) throws {
        let name = String(declaration.prefix(while: { $0 != " " }))
        guard module.split(separator: "\n").filter({ $0.hasPrefix("\(name) == ") })
                == [Substring(declaration)] else {
            throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.initialEvaluationFailureRecord",
                expected: "the selected initial failure site, kind, and operands",
                actual: "the emitted selected initial failure record differs",
                nextSafeAction: "Regenerate the TLA+ initial failure record.")
        }
    }

    static func verifyInitialFailureCheckBundle(_ bundle: TLAModuleBundle,
        base: TLAModuleBundle, aggregate: String, constants: [String],
        record: String? = nil) throws {
        let sourceLines = bundle.root.tla.split(separator: "\n").map(String.init)
        let stateName = sourceLines.indices.contains(2)
            ? String(sourceLines[2].dropFirst("VARIABLE ".count)) : ""
        let initName = sourceLines.indices.contains(4)
            ? String(sourceLines[4].prefix(while: { $0 != " " })) : ""
        let nextName = sourceLines.indices.contains(5)
            ? String(sourceLines[5].prefix(while: { $0 != " " })) : ""
        let statePrefix = bundle.root.name + "__ProbeState"
        let initPrefix = bundle.root.name + "__ProbeInit"
        let nextPrefix = bundle.root.name + "__ProbeNext"
        let expected = ["---- MODULE \(bundle.root.name) ----",
            "EXTENDS \(base.root.name)\(record == nil ? "" : ", TLC")",
            "VARIABLE \(stateName)",
            "ASSUME \(record.map { "PrintT(\($0)) /\\ " } ?? "")~\(aggregate)",
            "\(initName) == FALSE /\\ Init /\\ \(stateName) = 0",
            "\(nextName) == FALSE /\\ \(stateName)' = \(stateName)", "===="]
        let recordDeclarationPresent = record.map { name in
            base.root.tla.split(separator: "\n").filter { $0.hasPrefix("\(name) == ") }.count == 1
        } ?? true
        guard base.root.tla.split(separator: "\n").filter({ $0 == "Init ==" || $0.hasPrefix("Init == ") }).count == 1,
              base.root.tla.split(separator: "\n").filter({ $0.hasPrefix("\(aggregate) == ") }).count == 1,
              recordDeclarationPresent,
              stateName.hasPrefix(statePrefix),
              stateName.dropFirst(statePrefix.count).allSatisfy({ $0 == "_" }),
              initName.hasPrefix(initPrefix),
              initName.dropFirst(initPrefix.count).allSatisfy({ $0 == "_" }),
              nextName.hasPrefix(nextPrefix),
              nextName.dropFirst(nextPrefix.count).allSatisfy({ $0 == "_" }),
              !base.files.contains(where: {
                  $0.tla.contains(stateName) || $0.tla.contains(initName) || $0.tla.contains(nextName)
              }),
              sourceLines == expected,
              bundle.root.cfg?.split(separator: "\n").map(String.init)
                == ["INIT \(initName)", "NEXT \(nextName)", "CHECK_DEADLOCK FALSE"] + constants,
              bundle.imports.map(\.tla) == base.files.map(\.tla) else {
            throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.initialEvaluationSelection",
                expected: "a zero-state check of the generated initial failure predicate",
                actual: "the emitted initial failure check differs",
                nextSafeAction: "Regenerate the TLA+ initial failure check.")
        }
    }

    static func verify(_ action: CompiledActionExpr, rendered: String,
                       layout: CompiledLayout, binders: [BinderID: String],
                       required: Bool = false) throws {
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
        func unsupported() throws {
            if required { throw mismatch() }
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
                          let rendered = tokens(value.value) else { try unsupported(); return }
                    expected.append(contentsOf: rendered)
                    continue
                }
                guard expression.children.isEmpty else { try unsupported(); return }
                switch expression.operation {
                case .stateVariable(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    expected.append(name)
                case .boundValue(let id):
                    guard let name = binders[id] else { throw mismatch() }
                    expected.append(name)
                case .value(.integer(let value)): expected.append(String(value))
                case .value(.boolean(let value)): expected.append(value ? "TRUE" : "FALSE")
                case .value(let value):
                    guard let literal = tokens(try value.rendered(using: layout).description) else {
                        try unsupported(); return
                    }
                    expected.append(contentsOf: literal)
                case .controlLocation(let id):
                    guard let name = layout.controlLocation(id)?.formalName,
                          isFormalIdentifier(name) else { try unsupported(); return }
                    expected.append("\"\(name)\"")
                default: try unsupported(); return
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
                    guard directBoolean(value) else { try unsupported(); return }
                    if case .value(.boolean) = value.operation {
                        schedule([.value(value)])
                    } else {
                        schedule([.token("("), .value(value), .token(")"),
                            .token("="), .token("TRUE")])
                    }
                case .define(let id, let value, let body):
                    guard let name = binders[id], isFormalIdentifier(name),
                          !variables.values.contains(name),
                          usedBinderNames.insert(name).inserted else { try unsupported(); return }
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
                    guard directBoolean(condition) else { try unsupported(); return }
                    schedule([.token("("), .token("IF"), .value(condition), .token("THEN"),
                        .token("("), .action(yes), .token(")"), .token("ELSE"),
                        .token("("), .action(no), .token(")"), .token(")")])
                default: try unsupported(); return
                }
            }
        }
        guard let actual = tokens(rendered), actual == expected else { throw mismatch() }
    }

    static func verifyDeclaration(_ action: CompiledAction, named name: String,
                                  body: String, module: String, layout: CompiledLayout,
                                  binders: [BinderID: String],
                                  failureDeclarations: [String], required: Bool = false) throws {
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
            failureDeclarations: failureDeclarations, required: required)
    }

    private static func verifyAdditionFailures(_ action: CompiledAction, module: String,
                                               layout: CompiledLayout, binders: [BinderID: String],
                                               parameters: [String],
                                               failureDeclarations: [String], required: Bool) throws {
        // shortcut: branching continuations need their own failure rule.
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
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        func scalarValue(_ expression: CompiledExpression) -> String? {
            if case .add = expression.operation {
                return addition(expression, variables: variables, binders: binders)?.value
            }
            guard expression.children.isEmpty else { return nil }
            switch expression.operation {
            case .stateVariable(let id): return variables[id]
            case .boundValue(let id): return binders[id]
            case .value(.integer(let value)): return checkedIntegerLiteral(value)
            default: return nil
            }
        }
        var definitions: [(name: String, value: String, addition: AdditionTree?)] = []
        var remainder = body
        while case .define(let binder, let expression, let continuation) = remainder {
            guard let name = binders[binder], let value = scalarValue(expression) else { break }
            definitions.append((name, value, addition(expression, variables: variables, binders: binders)))
            remainder = continuation
        }
        if definitions.contains(where: { $0.addition != nil }) {
            var pending = [remainder]
            var finalWrites = 0
            var supported = true
            while let node = pending.popLast() {
                switch node {
                case .assign(_, _) where controlWrite(node): break
                case .assign(_, let value):
                    guard case .boundValue = value.operation, value.children.isEmpty else {
                        supported = false; break
                    }
                    finalWrites += 1
                case .unchanged: break
                case .guard_(let condition):
                    guard case .value(.boolean(true)) = condition.operation,
                          condition.children.isEmpty else { supported = false; break }
                case .and(let left, let right):
                    pending.append(right)
                    pending.append(left)
                default: supported = false
                }
            }
            if supported, finalWrites > 0 {
                var occurrence = 0
                for (position, definition) in definitions.enumerated() {
                    guard let tree = definition.addition else { continue }
                    var preceding: [String] = []
                    for site in tree.sites {
                        let suffix = occurrence == 0 ? "\(index)" : "\(index)_\(occurrence)"
                        var predicate = preceding.reversed().reduce("~(\(site.guardText))") { value, guard_ in
                            "(IF \(guard_) THEN \(value) ELSE FALSE)"
                        }
                        var operands = site.operands
                        for earlier in definitions[..<position].reversed() {
                            predicate = "(LET \(earlier.name) == \(earlier.value) IN \(predicate))"
                            operands = "(LET \(earlier.name) == \(earlier.value) IN \(operands))"
                            if let guardText = earlier.addition?.defined {
                                predicate = "(IF \(guardText) THEN \(predicate) ELSE FALSE)"
                            }
                        }
                        let selected = selection.map { "((\($0)) = TRUE /\\ \(predicate))" } ?? predicate
                        try verifyDeclaration("__SwiftTLAOverflowFailure\(suffix)", value: selected)
                        try verifyDeclaration("__SwiftTLAOverflowOperands\(suffix)", value: operands)
                        try verifyDeclaration("__SwiftTLAOverflowOperation\(suffix)", value: "\"addition\"")
                        preceding.append(site.guardText)
                        occurrence += 1
                    }
                }
                var aggregate: String?
                for definition in definitions.reversed() {
                    let current = definition.addition.map { "~(\($0.defined))" }
                    if let later = aggregate {
                        var continuation = "(LET \(definition.name) == \(definition.value) IN \(later))"
                        if let guardText = definition.addition?.defined {
                            continuation = "(IF \(guardText) THEN \(continuation) ELSE FALSE)"
                        }
                        aggregate = current.map { "(\($0) \\/ \(continuation))" } ?? continuation
                    } else {
                        aggregate = current
                    }
                }
                guard let aggregate else { throw mismatch("__SwiftTLAAnyEvaluationFailure\(index)") }
                try verifyDeclaration("__SwiftTLAAnyEvaluationFailure\(index)",
                    value: selection.map { "(IF \($0) THEN \(aggregate) ELSE FALSE)" } ?? aggregate)
                return
            }
        }
        if required {
            guard !definitions.contains(where: { $0.addition != nil }) else {
                throw mismatch("__SwiftTLAAnyEvaluationFailure\(index)")
            }
            let prefix = "__SwiftTLAAnyEvaluationFailure\(index)"
            let unexpected = failureDeclarations.contains { declaration in
                guard let header = declaration.components(separatedBy: " == ").first,
                      header.hasPrefix(prefix), header.hasSuffix(parameterSuffix) else { return false }
                return header.dropFirst(prefix.count).dropLast(parameterSuffix.count)
                    .allSatisfy { $0 == "_" }
            }
            guard !unexpected else { throw mismatch(prefix) }
        }
    }

    static func verifySourceDefaultDeadlock(_ configuration: TLCConfiguration,
                                            rendered: String, required: Bool) throws {
        guard required else { return }
        let directives = rendered.split(separator: "\n").filter { $0.hasPrefix("CHECK_DEADLOCK ") }
        guard configuration.checkDeadlock, directives == ["CHECK_DEADLOCK TRUE"] else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "tla.checking.defaultDeadlock",
                expected: "the authored #spec default CHECK_DEADLOCK TRUE",
                actual: "the emitted configuration changes the default deadlock check",
                nextSafeAction: "Report this TLA+ configuration emission failure.")
        }
    }

    static func verifyEvaluationSelection(_ behavior: CompiledBehavior, module: String,
                                          failureDeclarations: [String],
                                          evaluationInvariant: String?,
                                          configuration: TLCConfiguration,
                                          renderer: CompiledTLARenderer) throws {
        let lines = module.components(separatedBy: "\n")
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "tla.evaluationSelection",
                expected: "all emitted action failures selected by the TLC evaluation invariant",
                actual: "the module or configuration omits or changes that selection",
                nextSafeAction: "Regenerate the evaluation invariant and TLC configuration.")
        }
        func pureGuard(_ condition: CompiledExpression) -> Bool {
            func leaf(_ expression: CompiledExpression) -> Bool {
                guard expression.children.isEmpty else { return false }
                switch expression.operation {
                case .stateVariable, .boundValue, .controlLocation, .value: return true
                default: return false
                }
            }
            guard condition.resultType == .bool else { return false }
            if leaf(condition) { return true }
            guard case .equal = condition.operation, condition.children.count == 2 else { return false }
            return condition.children.allSatisfy(leaf)
        }
        func checkableCondition(_ condition: CompiledExpression) throws -> Bool {
            if pureGuard(condition) { return true }
            return try renderer.evaluationDefined(condition) != nil
        }
        func composedOutcome(_ node: CompiledActionExpr) throws ->
            (failure: String?, sites: [RenderedEvaluationFailure]) {
            if case .ifElse(let condition, let yes, let no) = node,
               try checkableCondition(condition) {
                // Expression results are child-rule premises; only the conditional wrapper is checked here.
                let conditionFailure = try renderer.anyFailurePredicate(.guard_(condition))
                let conditionSites = try renderer.expressionEvaluationFailures(condition)
                let defined = try renderer.evaluationDefined(condition)
                let selected = try composedOutcome(yes)
                let unselected = try composedOutcome(no)
                let predicate = try renderer.state(condition)
                let sites = conditionSites + selected.sites.map { site in
                    let failure = "(IF \(predicate) THEN \(site.predicate) ELSE FALSE)"
                    return RenderedEvaluationFailure(
                        predicate: defined.map { "(IF \($0) THEN \(failure) ELSE FALSE)" } ?? failure,
                        operands: site.operands, kind: site.kind)
                } + unselected.sites.map { site in
                    let failure = "(IF \(predicate) THEN FALSE ELSE \(site.predicate))"
                    return RenderedEvaluationFailure(
                        predicate: defined.map { "(IF \($0) THEN \(failure) ELSE FALSE)" } ?? failure,
                        operands: site.operands, kind: site.kind)
                }
                guard selected.failure != nil || unselected.failure != nil else {
                    return (conditionFailure, sites)
                }
                let branch = "(IF \(predicate) THEN \(selected.failure ?? "FALSE") ELSE \(unselected.failure ?? "FALSE"))"
                let guarded = defined.map { "(IF \($0) THEN \(branch) ELSE FALSE)" } ?? branch
                return (conditionFailure.map { "(\($0) \\/ \(guarded))" } ?? guarded, sites)
            }
            if case .or(let left, let right) = node {
                let first = try composedOutcome(left)
                let second = try composedOutcome(right)
                let later = second.sites.map { site in
                    RenderedEvaluationFailure(
                        predicate: first.failure.map { "(IF \($0) THEN FALSE ELSE \(site.predicate))" }
                            ?? site.predicate,
                        operands: site.operands, kind: site.kind)
                }
                let failure: String?
                switch (first.failure, second.failure) {
                case (nil, nil): failure = nil
                case (let first?, nil), (nil, let first?): failure = first
                case (let first?, let second?): failure = "(IF \(first) THEN TRUE ELSE \(second))"
                }
                return (failure, first.sites + later)
            }
            switch node {
            case .and(.guard_(let condition), let body):
                guard try checkableCondition(condition) else { break }
                let conditionFailure = try renderer.anyFailurePredicate(.guard_(condition))
                let conditionSites = try renderer.expressionEvaluationFailures(condition)
                let defined = try renderer.evaluationDefined(condition)
                let second = try composedOutcome(body)
                guard let bodyFailure = second.failure else { return (conditionFailure, conditionSites) }
                let predicate = try renderer.state(condition)
                let selected = "(IF \(predicate) THEN \(bodyFailure) ELSE FALSE)"
                let failure = defined.map { "(IF \($0) THEN \(selected) ELSE FALSE)" } ?? selected
                let sites = conditionSites + second.sites.map { site in
                    let selected = "((\(predicate)) = TRUE /\\ \(site.predicate))"
                    return RenderedEvaluationFailure(
                        predicate: defined.map { "(IF \($0) THEN \(selected) ELSE FALSE)" } ?? selected,
                        operands: site.operands, kind: site.kind)
                }
                return (conditionFailure.map { "(\($0) \\/ \(failure))" } ?? failure, sites)
            case .and(let left, let right):
                let first = try composedOutcome(left)
                let second = try composedOutcome(right)
                guard let rightFailure = second.failure else { return first }
                let enabled = "(ENABLED (\(try renderer.action(left))))"
                let reachedRight = "(\(enabled) /\\ \(rightFailure))"
                let failure = first.failure.map { "(\($0) \\/ \(reachedRight))" } ?? reachedRight
                let later = second.sites.map { site in
                    RenderedEvaluationFailure(predicate: "(\(enabled) /\\ \(site.predicate))",
                        operands: site.operands, kind: site.kind)
                }
                return (failure, first.sites + later)
            default: break
            }
            if case .assign(_, let value) = node {
                let names = Dictionary(uniqueKeysWithValues: renderer.layout.variables.map {
                    ($0.id, $0.declaration.name)
                })
                if let tree = addition(value, variables: names, binders: renderer.bindings.binders) {
                    var preceding: [String] = []
                    let sites = tree.sites.map { site -> RenderedEvaluationFailure in
                        let predicate = preceding.reversed().reduce("~(\(site.guardText))") { result, guard_ in
                            "(IF \(guard_) THEN \(result) ELSE FALSE)"
                        }
                        preceding.append(site.guardText)
                        return .init(predicate: predicate, operands: site.operands,
                            kind: .overflow(.addition))
                    }
                    return ("~(\(tree.defined))", sites)
                }
            }
            // shortcut: non-addition child rules remain premises until their output checks are independent.
            return (try renderer.anyFailurePredicate(node), try renderer.evaluationFailures(node))
        }
        func verifyComposedPayloads(_ action: CompiledAction, parameters: [String]) throws -> String? {
            let expected = try composedOutcome(action.body)
            let suffix = parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))"
            func check(_ base: String, _ value: String) throws {
                let candidates = failureDeclarations.filter { declaration in
                    guard let header = declaration.components(separatedBy: " == ").first,
                          header.hasSuffix(suffix) else { return false }
                    let name = String(header.dropLast(suffix.count))
                    return name.hasPrefix(base) && name.dropFirst(base.count).allSatisfy { $0 == "_" }
                }
                guard candidates.count == 1,
                      let header = candidates[0].components(separatedBy: " == ").first,
                      candidates[0] == "\(header) == \(value)",
                      lines.filter({ $0.hasPrefix("\(header) == ") }) == candidates else {
                    throw mismatch()
                }
            }
            var occurrences: [String: Int] = [:]
            for site in expected.sites {
                let failurePrefix: String
                let operandsPrefix: String?
                let operation: String?
                switch site.kind {
                case .noMatchingCase:
                    (failurePrefix, operandsPrefix, operation) = ("__SwiftTLANoMatchingCaseFailure", nil, nil)
                case .overflow(let kind):
                    (failurePrefix, operandsPrefix, operation) =
                        ("__SwiftTLAOverflowFailure", "__SwiftTLAOverflowOperands", kind.rawValue)
                case .divisionByZero:
                    (failurePrefix, operandsPrefix, operation) =
                        ("__SwiftTLADivisionByZeroFailure", "__SwiftTLADivisionByZeroDivisor", nil)
                case .negativeModuloDivisor:
                    (failurePrefix, operandsPrefix, operation) =
                        ("__SwiftTLANegativeModuloDivisorFailure", "__SwiftTLANegativeModuloDivisorValue", nil)
                case .functionArgumentOutsideDomain:
                    (failurePrefix, operandsPrefix, operation) =
                        ("__SwiftTLAFunctionArgumentOutsideDomainFailure", nil, nil)
                case .sequenceIndexOutOfBounds:
                    (failurePrefix, operandsPrefix, operation) =
                        ("__SwiftTLASequenceIndexOutOfBoundsFailure", "__SwiftTLASequenceIndexOutOfBoundsOperands", nil)
                case .emptySequence:
                    (failurePrefix, operandsPrefix, operation) = ("__SwiftTLAEmptySequenceFailure", nil, nil)
                }
                let occurrence = occurrences[failurePrefix, default: 0]
                occurrences[failurePrefix] = occurrence + 1
                let siteSuffix = occurrence == 0 ? "\(action.id.ordinal)" : "\(action.id.ordinal)_\(occurrence)"
                try check("\(failurePrefix)\(siteSuffix)", site.predicate)
                if let operandsPrefix, let operands = site.operands {
                    try check("\(operandsPrefix)\(siteSuffix)", operands)
                } else if operandsPrefix != nil { throw mismatch() }
                if let operation {
                    try check("__SwiftTLAOverflowOperation\(siteSuffix)", "\"\(operation)\"")
                }
            }
            return expected.failure
        }
        var references: [String] = []
        for index in behavior.enabledActionIndices {
            let prefix = "__SwiftTLAAnyEvaluationFailure\(index)"
            let action = behavior.actions[index]
            let parameters = try action.bindings.map { try renderer.binderName($0.binder) }
            let checksComposition: Bool
            switch action.body {
            case .or: checksComposition = true
            case .ifElse(let condition, _, _): checksComposition = try checkableCondition(condition)
            case .and(.guard_(let condition), _): checksComposition = try checkableCondition(condition)
            case .and: checksComposition = true
            default: checksComposition = false
            }
            let checkedComposition = checksComposition
                ? try verifyComposedPayloads(action, parameters: parameters) : nil
            let parameterSuffix = parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))"
            let candidates = failureDeclarations.filter { declaration in
                guard let header = declaration.components(separatedBy: " == ").first else { return false }
                guard header.hasPrefix(prefix), header.hasSuffix(parameterSuffix) else { return false }
                let suffix = header.dropFirst(prefix.count).dropLast(parameterSuffix.count)
                return suffix.allSatisfy { $0 == "_" }
            }
            guard candidates.count <= 1,
                  !checksComposition || (checkedComposition != nil) == !candidates.isEmpty else {
                throw mismatch()
            }
            guard let declaration = candidates.first else { continue }
            guard lines.filter({ $0 == declaration }).count == 1,
                  let header = declaration.components(separatedBy: " == ").first else { throw mismatch() }
            if let checkedComposition, declaration != "\(header) == \(checkedComposition)" {
                throw mismatch()
            }
            let name = String(header.dropLast(parameterSuffix.count))
            guard !parameters.isEmpty else {
                references.append(name)
                continue
            }
            let domains = try zip(parameters, action.bindings).map { parameter, binding in
                let domain = try binding.literalMembers.map {
                    try CompiledValue.set(Set($0)).rendered(using: renderer.layout).description
                } ?? renderer.state(binding.domain)
                return "\(parameter) \\in \(domain)"
            }
            let call = "\(name)(\(parameters.joined(separator: ", ")))"
            if action.bindings.allSatisfy({ $0.literalMembers != nil }) {
                references.append("(\\E \(domains.joined(separator: ", ")): \(call))")
            } else {
                references.append(domains.reversed().reduce(call) { "(\\E \($1): \($0))" })
            }
        }
        guard let evaluationInvariant else {
            guard references.isEmpty else { throw mismatch() }
            return
        }
        guard evaluationInvariant.hasPrefix("__SwiftTLAEvaluationOK"),
              evaluationInvariant.dropFirst("__SwiftTLAEvaluationOK".count).allSatisfy({ $0 == "_" }),
              !references.isEmpty else { throw mismatch() }
        let expected = "\(evaluationInvariant) == "
            + references.map { "~(\($0))" }.joined(separator: " /\\ ")
        guard lines.filter({ $0.hasPrefix("\(evaluationInvariant) == ") }) == [expected],
              failureDeclarations.filter({ $0.hasPrefix("\(evaluationInvariant) == ") }) == [expected],
              configuration.intrinsicInvariants.filter({ $0 == evaluationInvariant }).count == 1,
              configuration.assumptionsOnly
                || configuration.render(usesSymmetryReduction: false)
                    .components(separatedBy: "\n").contains("INVARIANT \(evaluationInvariant)")
        else { throw mismatch() }
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
