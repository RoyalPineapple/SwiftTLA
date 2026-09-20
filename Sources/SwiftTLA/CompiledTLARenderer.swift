private enum StateRenderingTask {
    case expression(CompiledExpression)
    case setMember(CompiledExpression)
    case finishSetMember(start: Int)
    case finishSet(start: Int)
    case checkedView(FormalValueShape, start: Int)
    case formalArgument(CompiledFormalCallArgument)
    case formalOperator(CompiledFormalOperator)
    case localOperator(CompiledOperatorDefinition)
    case text(String)
}

private enum ActionRenderingTask {
    case expression(CompiledActionExpr)
    case text(String)
}

struct CompiledTLARenderer {
    let moduleName: String
    let reservedNames: Set<String>
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let operators: CompiledOperators
    let actions: [CompiledAction]
    let functions: [ResolvedFunction]
    var moduleNames: [String: String] = [:]

    func assumptions(_ behavior: CompiledBehavior) throws -> [String] {
        var result = try layout.parameters.map { parameter in
            guard let domain = behavior.parameterDomains[parameter.binder] else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "parameters.\(parameter.reference.name).domain", expected: "a resolved domain", actual: "missing domain",
                    nextSafeAction: "Resolve the parameter domain before export.")
            }
            return "ASSUME \(try binderName(parameter.binder)) \\in \(try state(domain))"
        }
        for register in layout.checkingRegisters {
            guard let initial = behavior.checkingRegisterInitializations[register.id] else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "checkingRegisters.\(register.reference.name).initial",
                    expected: "a resolved initialization", actual: "missing initialization",
                    nextSafeAction: "Resolve the checking register initialization before export.")
            }
            result.append("ASSUME TLCSet(\(register.id.ordinal), \(try state(initial)))")
        }
        if let assume = behavior.assume {
            result.append("ASSUME \(try state(assume.expression))")
        }
        return result
    }

    func resolvedFunctionDefinitions() throws -> [String] {
        guard !functions.isEmpty else { return [] }
        let signatures = try functions.enumerated().map { index, function in
            let name = try resolvedFunctionName(.init(ordinal: index))
            let captures = try functionStateCaptures(.init(ordinal: index))
            let slots = Array(repeating: "_", count: function.parameters.count + captures.count).joined(separator: ", ")
            return name + (slots.isEmpty ? "" : "(\(slots))")
        }
        return try ["RECURSIVE " + signatures.joined(separator: ", ")] + functions.enumerated().map { index, function in
            let name = try resolvedFunctionName(.init(ordinal: index))
            let captures = try functionStateCaptures(.init(ordinal: index))
            let names = try captures.map { try stateCaptureName($0) }
            let substitutions = Dictionary(uniqueKeysWithValues: zip(captures, names))
            let parameters = try (function.parameters.map { try binderName($0.binder) } + names).joined(separator: ", ")
            let body = try state(function.body, stateNames: substitutions)
            let value = try function.domainGuard.map { "CASE \(try state($0, stateNames: substitutions)) -> (\(body))" } ?? body
            return name + (parameters.isEmpty ? "" : "(\(parameters))") + " == " + value
        }
    }

    private func functionStateCaptures(_ id: ResolvedFunctionID) throws -> [VariableID] {
        var pending = [id]
        var visited: Set<ResolvedFunctionID> = []
        var variables: Set<VariableID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard functions.indices.contains(current.ordinal) else { throw missing("resolved function", current.ordinal) }
            let function = functions[current.ordinal]
            var expressions = [function.body] + (function.domainGuard.map { [$0] } ?? [])
            while let expression = expressions.popLast() {
                switch expression.operation {
                case .stateVariable(let variable): variables.insert(variable)
                case .call(let callee): pending.append(callee)
                default: break
                }
                expressions.append(contentsOf: expression.children)
            }
        }
        return variables.sorted { $0.ordinal < $1.ordinal }
    }

    private func stateCaptureName(_ variable: VariableID) throws -> String {
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
        var name = "__\(moduleName)_state\(variable.ordinal)"
        while occupied.contains(name) { name += "_" }
        return name
    }

    private func resolvedFunctionName(_ id: ResolvedFunctionID) throws -> String {
        guard functions.indices.contains(id.ordinal) else { throw missing("resolved function", id.ordinal) }
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
        var name = "__\(moduleName)_resolvedFunction\(id.ordinal)"
        while occupied.contains(name) { name += "_" }
        return name
    }

    func action(
        _ expression: CompiledActionExpr
    ) throws -> String {
        var tasks = [ActionRenderingTask.expression(expression)]
        var parts: [String] = []
        func schedule(_ values: [ActionRenderingTask]) {
            tasks.append(contentsOf: values.reversed())
        }
        while let task = tasks.popLast() {
            switch task {
            case .text(let value):
                parts.append(value)
            case .expression(let action):
                switch action {
                case .assign(let variable, let value):
                    parts.append("\(try variableName(variable))' = \(try state(value))")
                case .unchanged(let variable):
                    parts.append("UNCHANGED \(try variableName(variable))")
                case .guard_(let condition):
                    let predicate = try state(condition)
                    // A state predicate produces one Boolean, not a successor per existential witness.
                    if case .value(.boolean) = condition.operation {
                        parts.append(predicate)
                    } else {
                        parts.append("(\(predicate)) = TRUE")
                    }
                case .existsAction(let binder, let set, let body):
                    parts.append("(\\E \(try binderName(binder)) \\in \(try state(set)): ")
                    schedule([.expression(body), .text(")")])
                case .ifElse(let condition, let then, let otherwise):
                    parts.append("(IF \(try state(condition)) THEN (")
                    schedule([
                        .expression(then), .text(") ELSE ("), .expression(otherwise), .text("))")
                    ])
                case .define(let binder, let value, let body):
                    parts.append("(LET \(try binderName(binder)) == \(try state(value)) IN ")
                    schedule([.expression(body), .text(")")])
                case .and(let lhs, let rhs):
                    parts.append("(")
                    schedule([.expression(lhs), .text(" /\\ "), .expression(rhs), .text(")")])
                case .or(let lhs, let rhs):
                    parts.append("(")
                    schedule([.expression(lhs), .text(" \\/ "), .expression(rhs), .text(")")])
                }
            }
        }
        return parts.joined()
    }

    func temporal(_ property: CompiledTemporal<CompiledStateQuery>) throws -> String {
        var result = try temporal(property.expression)
        for binding in property.bindings.reversed() {
            result = "(\\A \(try binderName(binding.binder)) \\in \(try state(binding.domain)): \(result))"
        }
        return result
    }

    func temporal(
        _ expression: TemporalCondition<CompiledStateQuery>
    ) throws -> String {
        switch expression {
        case .always(let predicate):
            let claim = predicate.expression
            if case .stutteringStep = claim.operation {
                return "[][\(try state(claim))]_(\(try state(claim.children[0])))"
            }
            return "[]\(try state(claim))"
        case .eventually(let predicate): return "<>\(try state(predicate.expression))"
        case .alwaysEventually(let predicate): return "[]<>\(try state(predicate.expression))"
        case .eventuallyAlways(let predicate): return "<>[]\(try state(predicate.expression))"
        case .leadsTo(let source, let target): return "(\(try state(source.expression)) ~> \(try state(target.expression)))"
        case .all(let conditions):
            return conditions.isEmpty ? "TRUE" : "(" + (try conditions.map { try temporal($0) }).joined(separator: " /\\ ") + ")"
        case .conditional(let predicate, let yes, let no):
            return "(IF \(try state(predicate.expression)) THEN \(try temporal(yes)) ELSE \(try temporal(no)))"
        }
    }

    func formalDefinition(_ id: OperatorID) throws -> String {
        guard let definition = operators[id] else { throw missing("operator", id.ordinal) }
        let name = try operatorName(definition.id)
        let parameters = try definition.parameters.map(formalParameter).joined(separator: ", ")
        return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == \(try state(definition.body))"
    }

    func recursiveFunction(_ id: OperatorID) throws -> (declaration: String, body: String) {
        guard let function = operators[id] else { throw missing("recursive function", id.ordinal) }
        let name = try operatorName(function.id)
        let parameters = try function.parameters.map(formalParameter)
        return (
            declaration: "RECURSIVE \(name)(\(parameters.map { _ in "_" }.joined(separator: ", ")))",
            body: "\(name)(\(parameters.joined(separator: ", "))) == \(try state(function.body))"
        )
    }

    func fairness(
        _ condition: CompiledFairnessCondition,
        vars: String,
        actionCalls: [CompiledActionCall: String]
    ) throws -> String {
        let action: String
        let vars = try condition.projection.map { "(\(try state($0)))" } ?? vars
        switch condition.scope {
        case .next:
            action = "Next"
        case .action(let id):
            action = try actionReference(id)
        case .actionCall(let call):
            guard let name = actionCalls[call] else { throw missing("action", call.action.ordinal) }
            action = name
        case .eachAction(let id):
            let bindings = actions[id.ordinal].bindings
            let parameters = try bindings.map { try binderName($0.binder) }
            let name = layout.actions[id.ordinal].renderedName
            let invocation = name + (parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))")
            var result = "\(condition.isStrong ? "SF" : "WF")_\(vars)(\(invocation))"
            for (parameter, binding) in zip(parameters, bindings).reversed() {
                result = "(\\A \(parameter) \\in \(try state(binding.domain)): \(result))"
            }
            return result
        }
        return "\(condition.isStrong ? "SF" : "WF")_\(vars)(\(action))"
    }

    func refinement(_ refinement: CompiledRefinement) throws -> String {
        guard let instance = layout.moduleInstances.first(where: { $0.id == refinement.instance }) else {
            throw missing("module instance", refinement.instance.ordinal)
        }
        let target: String
        switch refinement.operator {
        case .spec: target = "Spec"
        case .liveSpec: target = "LiveSpec"
        case .liveSpecEquals: target = "LiveSpecEquals"
        }
        return "\(refinement.name) == \(instance.namespace)!\(target)"
    }

    func formalModuleReplacement(_ replacement: CompiledFormalModuleReplacement) throws -> String {
        "\(replacement.definitionName) == \(try state(replacement.expression))"
    }

    func moduleInstance(_ instance: CompiledModuleInstance) throws -> String {
        guard let layout = layout.moduleInstances.first(where: { $0.id == instance.id }) else {
            throw missing("module instance", instance.id.ordinal)
        }
        let arguments = try instance.arguments.map {
            "\($0.parameter) <- \(try state($0.value))"
        }.joined(separator: ", ")
        let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
        return "\(layout.namespace) == INSTANCE \(moduleNames[layout.moduleName] ?? layout.moduleName)\(withClause)"
    }

    func state(_ expression: CompiledExpression, stateNames: [VariableID: String] = [:]) throws -> String {
        var tasks = [StateRenderingTask.expression(expression)]
        var parts: [String] = []

        func schedule(_ operation: CompiledOperation, _ operands: [CompiledExpression]) throws {
            let syntax = try operation.tlaSyntax(operandCount: operands.count,
                binderName: binderName)
            for part in syntax.reversed() {
                switch part {
                case .text(let text): tasks.append(.text(text))
                case .operand(let index): tasks.append(.expression(operands[index]))
                }
            }
        }

        func schedule(_ scheduled: [StateRenderingTask]) {
            tasks.append(contentsOf: scheduled.reversed())
        }

        while let task = tasks.popLast() {
            switch task {
            case .text(let text):
                parts.append(text)
            case .setMember(let member):
                tasks.append(.finishSetMember(start: parts.count))
                tasks.append(.expression(member))
            case .finishSetMember(let start):
                let member = parts[start...].joined()
                parts.replaceSubrange(start..., with: [member])
            case .finishSet(let start):
                let members = parts[start...].sorted().joined(separator: ", ")
                parts.replaceSubrange(start..., with: ["{\(members)}"])
            case .formalArgument(let argument):
                switch argument {
                case .value(let value): tasks.append(.expression(value))
                case .operator(let operation): tasks.append(.formalOperator(operation))
                }
            case .formalOperator(let operation):
                switch operation {
                case .lambda(let id, _):
                    guard let lambda = operators[id] else { throw missing("lambda", id.ordinal) }
                    parts.append("LAMBDA \(try lambda.parameters.map(formalParameter).joined(separator: ", ")) : ")
                    tasks.append(.expression(lambda.body))
                case .reference(let id, _):
                    parts.append(try operatorName(id))
                }
            case .localOperator(let operation):
                let name = try operatorName(operation.id)
                let parameters = try operation.parameters.map(formalParameter).joined(separator: ", ")
                if let domain = operation.domain, case .value(let parameter, _) = operation.parameters.first {
                    parts.append("\(name)[\(try binderName(parameter)) \\in ")
                    schedule([.expression(domain), .text("] == "), .expression(operation.body)])
                } else {
                    parts.append("\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == ")
                    tasks.append(.expression(operation.body))
                }
            case .checkedView(let shape, let start):
                let operand = parts[start...].joined()
                parts.removeSubrange(start...)
                var name = "_checkedValue"
                let shapeNames = String(describing: shape)
                while operand.contains(name) || shapeNames.contains(name) { name += "_" }
                parts.append("(LET \(name) == \(operand) IN CASE \(shape.predicate(for: name)) -> \(name))")
            case .expression(let expression):
                switch expression.operation {
                case .setMap, .unionAll:
                    if let fields = cartesianRecordFields(expression) {
                        var rendered: [StateRenderingTask] = [.text("[")]
                        for (index, field) in fields.enumerated() {
                            if index > 0 { rendered.append(.text(", ")) }
                            rendered.append(.text("\(field.name): "))
                            rendered.append(.expression(field.domain))
                        }
                        rendered.append(.text("]"))
                        schedule(rendered)
                    } else {
                        try schedule(expression.operation, expression.children)
                    }
                case .setLiteral:
                    tasks.append(.finishSet(start: parts.count))
                    tasks.append(contentsOf: expression.children.reversed().map(StateRenderingTask.setMember))
                case .assertView(let shape):
                    let value = expression.children[0]

                    tasks.append(.checkedView(shape, start: parts.count))
                    tasks.append(.expression(value))
                case .nextState, .stutteringStep:
                    try schedule(expression.operation, expression.children)
                case .value(let value): parts.append(try value.rendered(using: layout).description)
                case .stateVariable(let variable): parts.append(try stateNames[variable] ?? variableName(variable))
                case .boundValue(let binder): parts.append(try binderName(binder))
                case .checkingRegister(let id): parts.append("TLCGet(\(id.ordinal))")
                case .checkingLevel: parts.append("TLCGet(\"level\")")
                case .setCheckingRegister(let id):
                    parts.append("TLCSet(\(id.ordinal), ")
                    tasks.append(.text(")"))
                    tasks.append(.expression(expression.children[0]))
                case .controlLocation(let location): parts.append(try controlLocationName(location))
                case .operatorReference(let operation): parts.append(try operatorName(operation))
                case .enabledAction(let action): parts.append("ENABLED \(try actionReference(action))")
                case .convert:
                    tasks.append(.expression(expression.children[0]))
                case .call(let id):
                    let name = try resolvedFunctionName(id)
                    guard expression.children.count == functions[id.ordinal].parameters.count else {
                        throw missing("resolved function arguments", id.ordinal)
                    }
                    parts.append(name)
                    let captures = try functionStateCaptures(id)
                    if !expression.children.isEmpty || !captures.isEmpty {
                        parts.append("(")
                        var arguments: [StateRenderingTask] = []
                        for (index, child) in expression.children.enumerated() {
                            if index > 0 { arguments.append(.text(", ")) }
                            arguments.append(.expression(child))
                        }
                        for variable in captures {
                            if !arguments.isEmpty { arguments.append(.text(", ")) }
                            arguments.append(.text(try stateNames[variable] ?? variableName(variable)))
                        }
                        arguments.append(.text(")"))
                        schedule(arguments)
                    }
                case .checkedCall:
                    throw missing("resolved function", 0)
                case .operatorApplication(.lambda(let id, _), let arguments):
                    guard let lambda = operators[id] else { throw missing("lambda", id.ordinal) }
                    var rendered: [StateRenderingTask] = []
                    for (parameter, argument) in zip(lambda.parameters, arguments) {
                        rendered.append(.text("LET \(try formalParameter(parameter)) == "))
                        rendered.append(.formalArgument(argument))
                        rendered.append(.text(" IN "))
                    }
                    parts.append("(")
                    rendered.append(.expression(lambda.body))
                    rendered.append(.text(")"))
                    schedule(rendered)
                case .operatorApplication(.reference(let operation, _), let arguments):
                    parts.append(try operatorName(operation))
                    if arguments.isEmpty == false {
                        var rendered: [StateRenderingTask] = []
                        for (index, argument) in arguments.enumerated() {
                            if index > 0 { rendered.append(.text(", ")) }
                            rendered.append(.formalArgument(argument))
                        }
                        parts.append("(")
                        rendered.append(.text(")"))
                        schedule(rendered)
                    }
                case .letIn(let ids):
                    let body = expression.children[0]

                    let operations = try ids.map { id in
                        guard let operation = operators[id] else {
                            throw missing("local operator", id.ordinal)
                        }
                        return operation
                    }
                    if operations.isEmpty {
                        tasks.append(.expression(body))
                        continue
                    }
                    let recursiveDeclarations = try operations
                        .filter { $0.isRecursive && $0.domain == nil }
                        .map { operation in
                            let name = try operatorName(operation.id)
                            let slots = Array(repeating: "_", count: operation.parameters.count).joined(separator: ", ")
                            return operation.parameters.isEmpty ? name : "\(name)(\(slots))"
                        }
                        .joined(separator: ", ")
                    parts.append("(LET ")
                    if recursiveDeclarations.isEmpty == false {
                        parts.append("RECURSIVE \(recursiveDeclarations)\n    ")
                    }
                    var rendered: [StateRenderingTask] = []
                    for (index, operation) in operations.enumerated() {
                        if index > 0 { rendered.append(.text("\n    ")) }
                        rendered.append(.localOperator(operation))
                    }
                    rendered.append(.text("\nIN "))
                    rendered.append(.expression(body))
                    rendered.append(.text(")"))
                    schedule(rendered)
                case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .and, .or, .in, .subset, .union, .intersection, .setDifference, .tupleDynamicAccess, .tupleAppend, .tupleConcatenate, .tupleRemoving, .sequenceSelect, .functionApply, .functionSet, .setSum, .integerRange, .negate, .not, .cardinality, .powerSet, .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet, .ifThenElse, .setFilter, .tupleLiteral, .tupleAccess, .recordLiteral, .recordAccess, .functionLiteral, .except, .caseExpr, .forAll, .exists, .choose, .foldFunction, .letValue:
                    try schedule(expression.operation, expression.children)

                }
            }
        }
        return parts.joined()
    }

    /// Serialize a bijective, independent record comprehension without materializing a UNION of sets.
    private func cartesianRecordFields(_ expression: CompiledExpression) -> [(name: String, domain: CompiledExpression)]? {
        var body = expression.computation
        var domains: [BinderID: CompiledExpression] = [:]
        while true {
            let flattened: Bool
            if case .unionAll = body.operation {
                body = body.children[0].computation
                flattened = true
            } else {
                flattened = false
            }
            guard case .setMap(let binder) = body.operation,
                  domains[binder] == nil else { return nil }
            domains[binder] = body.children[1]
            body = body.children[0].computation
            if !flattened { break }
        }
        guard case .recordLiteral(let names) = body.operation,
              names.count == domains.count, names.count == body.children.count,
              Set(names).count == names.count else { return nil }
        var fields: [(name: String, domain: CompiledExpression)] = []
        var used: Set<BinderID> = []
        for (name, value) in zip(names, body.children) {
            guard case .boundValue(let binder) = value.computation.operation,
                  let domain = domains[binder], used.insert(binder).inserted else { return nil }
            fields.append((name, domain))
        }
        var pending = Array(domains.values)
        while let domain = pending.popLast() {
            switch domain.operation {
            case .boundValue(let binder):
                if used.contains(binder) { return nil }
            case .value, .stateVariable, .integerRange, .convert:
                break
            // Moving a fallible domain outside an empty outer iteration can introduce an error.
            // Other operations can also hide lexical captures outside their expression children.
            default: return nil
            }
            pending.append(contentsOf: domain.children)
        }
        return fields
    }

    private func formalParameter(_ parameter: CompiledFormalParameter) throws -> String {
        switch parameter {
        case .value(let binder, _): return try binderName(binder)
        case .operator(let operation, let arity):
            return "\(try operatorName(operation))(\(Array(repeating: "_", count: arity).joined(separator: ", ")))"
        }
    }

    func variableName(_ id: VariableID) throws -> String {
        guard layout.variables.indices.contains(id.ordinal) else { throw missing("variable", id.ordinal) }
        return layout.variables[id.ordinal].declaration.name
    }

    func actionReference(_ id: ActionID) throws -> String {
        guard layout.actions.indices.contains(id.ordinal),
              actions.indices.contains(id.ordinal) else { throw missing("action", id.ordinal) }
        let name = layout.actions[id.ordinal].renderedName
        let action = actions[id.ordinal]
        guard !action.bindings.isEmpty else { return name }
        let parameters = try action.bindings.map { try binderName($0.binder) }
        let domains = try zip(parameters, action.bindings).map { parameter, binding in
            let domain = try binding.literalMembers.map { try CompiledValue.set(Set($0)).rendered(using: layout).description }
                ?? state(binding.domain)
            return "\(parameter) \\in \(domain)"
        }
        if action.bindings.contains(where: { $0.literalMembers == nil }) {
            return domains.reversed().reduce("\(name)(\(parameters.joined(separator: ", ")))") {
                "(\\E \($1): \($0))"
            }
        }
        return "(\\E \(domains.joined(separator: ", ")): \(name)(\(parameters.joined(separator: ", "))))"
    }

    func binderName(_ id: BinderID) throws -> String {
        guard let name = bindings.binderName(id) else { throw missing("binder", id.ordinal) }
        return name
    }

    func procedureName(_ id: ProcedureID) throws -> String {
        guard let procedure = layout.procedure(id) else { throw missing("procedure", id.ordinal) }
        return procedure.name
    }

    func controlLocationSourceName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return location.sourceName
    }

    private func operatorName(_ id: OperatorID) throws -> String {
        guard let name = bindings.operatorName(id) else { throw missing("operator", id.ordinal) }
        return name
    }

    private func controlLocationName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return "\"\(location.sourceName)\""
    }

    private func missing(_ kind: String, _ ordinal: Int) -> CompilationDiagnostic {
        .init(
            code: .unknownReference,
            stage: .rendering,
            path: "compiledRenderer.\(kind)[\(ordinal)]",
            expected: "a rendered declaration name",
            actual: "no declaration",
            nextSafeAction: "Compile the source model again before rendering."
        )
    }
}

/// Operand-delimited TLA+ syntax, independent of the expression representation.
extension CompiledOperation {
    private var tlaOperandSyntax: (prefix: String, separator: String, suffix: String)? {
        switch self {
        case .convert: ("(", "", ")")
        case .add: ("(", " + ", ")")
        case .subtract: ("(", " - ", ")")
        case .multiply: ("(", " * ", ")")
        case .modulo: ("(", " % ", ")")
        case .equal: ("(", " = ", ")")
        case .notEqual: ("(", " /= ", ")")
        case .lessThan: ("(", " < ", ")")
        case .lessOrEqual: ("(", " <= ", ")")
        case .greaterThan: ("(", " > ", ")")
        case .greaterOrEqual: ("(", " >= ", ")")
        case .and: ("(", " /\\ ", ")")
        case .or: ("(IF ", " THEN TRUE ELSE ", ")")
        case .in: ("(", " \\in ", ")")
        case .subset: ("(", " \\subseteq ", ")")
        case .union: ("(", " \\cup ", ")")
        case .intersection: ("(", " \\cap ", ")")
        case .setDifference: ("(", " \\ ", ")")
        case .tupleDynamicAccess: ("", "[", "]")
        case .tupleAppend: ("Append(", ", ", ")")
        case .tupleConcatenate: ("(", " \\o ", ")")
        case .functionApply: ("", "[", "]")
        case .functionSet: ("[", " -> ", "]")
        case .setSum: ("Sum(", ", ", ")")
        case .integerRange: ("", "..", "")
        case .negate: ("(-", "", ")")
        case .nextState: ("(", "", ")'")
        case .not: ("(~", "", ")")
        case .cardinality: ("Cardinality(", "", ")")
        case .powerSet: ("SUBSET ", "", "")
        case .unionAll: ("UNION ", "", "")
        case .tupleLength: ("Len(", "", ")")
        case .tupleHead: ("Head(", "", ")")
        case .tupleTail: ("Tail(", "", ")")
        case .domain: ("DOMAIN ", "", "")
        case .sequenceFromSet: ("SeqFromSet(", "", ")")
        case .setLiteral: ("{", ", ", "}")
        case .tupleLiteral: ("<<", ", ", ">>")
        case .divide, .integerDivide: ("(", " \\div ", ")")
        default: nil
        }
    }
}

/// A rendering instruction refers to an operand without owning another expression tree.
enum TLAExpressionPart: Equatable, Sendable {
    case text(String)
    case operand(Int)
}

extension CompiledOperation {
    func tlaSyntax(
        operandCount: Int,
        binderName: (BinderID) throws -> String
    ) throws -> [TLAExpressionPart] {
        if let syntax = tlaOperandSyntax {
            var parts: [TLAExpressionPart] = [.text(syntax.prefix)]
            for index in 0..<operandCount {
                if index > 0 { parts.append(.text(syntax.separator)) }
                parts.append(.operand(index))
            }
            parts.append(.text(syntax.suffix))
            return parts
        }
        let parts: [TLAExpressionPart]
        switch self {
        case .stutteringStep:
            parts = [.text("(IF ("), .operand(0), .text(" = ("), .operand(0),
                .text(")') THEN TRUE ELSE "), .operand(1), .text(")")]
        case .ifThenElse:
            parts = [.text("(IF "), .operand(0), .text(" THEN "), .operand(1),
                .text(" ELSE "), .operand(2), .text(")")]
        case .tupleRemoving:
            parts = [.text("(SubSeq("), .operand(0), .text(", 1, ("), .operand(1),
                .text(" - 1)) \\o SubSeq("), .operand(0), .text(", ("), .operand(1),
                .text(" + 1), Len("), .operand(0), .text(")))")]
        case .sequenceSelect(let binder):
            parts = [.text("SelectSeq("), .operand(0), .text(", LAMBDA \(try binderName(binder)): "),
                .operand(1), .text(")")]
        case .setFilter(let binder):
            parts = [.text("{\(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text("}")]
        case .setMap(let binder):
            parts = [.text("{"), .operand(0), .text(" : \(try binderName(binder)) \\in "), .operand(1), .text("}")]
        case .tupleAccess(let index):
            parts = [.operand(0), .text("[\(index)]")]
        case .recordLiteral(let fields):
            guard fields.count == operandCount else {
                throw CompiledValueType.diagnostic("rendering.record", "each record field requires one operand")
            }
            var record: [TLAExpressionPart] = [.text("[")]
            for (index, field) in fields.enumerated() {
                if index > 0 { record.append(.text(", ")) }
                record += [.text("\(field) |-> "), .operand(index)]
            }
            record.append(.text("]"))
            parts = record
        case .recordAccess(let field):
            parts = [.text("("), .operand(0), .text(").\(field)")]
        case .functionLiteral(let binder):
            parts = [.text("[\(try binderName(binder)) \\in "), .operand(0), .text(" |-> "), .operand(1), .text("]")]
        case .except:
            parts = [.text("["), .operand(0), .text(" EXCEPT !["), .operand(1), .text("] = "), .operand(2), .text("]")]
        case .caseExpr(let hasOtherwise):
            let branchOperands = operandCount - (hasOtherwise ? 1 : 0)
            guard branchOperands >= 2, branchOperands.isMultiple(of: 2) else {
                throw CompiledValueType.diagnostic("rendering.case", "CASE requires condition/value pairs and an optional default")
            }
            var branches: [TLAExpressionPart] = [.text("CASE ")]
            for index in stride(from: 0, to: branchOperands, by: 2) {
                if index > 0 { branches.append(.text(" [] ")) }
                branches += [.operand(index), .text(" -> "), .operand(index + 1)]
            }
            if hasOtherwise { branches += [.text(" [] OTHER -> "), .operand(branchOperands)] }
            parts = branches
        case .forAll(let binder):
            parts = [.text("(\\A \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .exists(let binder):
            parts = [.text("(\\E \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .choose(let binder):
            parts = [.text("(CHOOSE \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .foldFunction(let binders):
            parts = [.text("FoldFunction(LAMBDA \(try binders.map(binderName).joined(separator: ", ")) : "),
                .operand(0), .text(", "), .operand(1), .text(", "), .operand(2), .text(")")]
        case .letValue(let binder):
            parts = [.text("(LET \(try binderName(binder)) == "), .operand(0), .text(" IN "), .operand(1), .text(")")]
        default:
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                path: "compiledRenderer.operation", expected: "an operand syntax template",
                actual: String(describing: self), nextSafeAction: "Check operation lowering before rendering.")
        }
        return parts
    }
}
