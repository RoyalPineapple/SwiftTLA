private enum StateRenderingTask {
    case expression(CompiledStateExpr)
    case formalArgument(CompiledFormalCallArgument)
    case formalOperator(CompiledFormalOperator)
    case localOperator(CompiledLocalOperator)
    case text(String)
}

private enum ActionRenderingTask {
    case expression(CompiledActionExpr)
    case text(String)
}

struct CompiledTLARenderer {
    let layout: CompiledLayout
    let bindings: CompiledBindingTable

    func action(_ expression: CompiledActionExpr) throws -> String {
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
                    parts.append(try state(condition))
                case .chooseAction(let variable, let set):
                    parts.append("\(try variableName(variable))' \\in \(try state(set))")
                case .existsAction(let binder, let set, let body):
                    parts.append("\\E \(try binderName(binder)) \\in \(try state(set)): ")
                    tasks.append(.expression(body))
                case .ifElse(let condition, let then, let otherwise):
                    parts.append("IF \(try state(condition)) THEN (")
                    schedule([
                        .expression(then), .text(") ELSE ("), .expression(otherwise), .text(")")
                    ])
                case .define(let binder, let value, let body):
                    parts.append("LET \(try binderName(binder)) == \(try state(value)) IN ")
                    tasks.append(.expression(body))
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

    func temporal(_ expression: CompiledTemporalExpr) throws -> String {
        switch expression {
        case .always(let predicate): return "[]\(try state(predicate))"
        case .eventually(let predicate): return "<>\(try state(predicate))"
        case .alwaysEventually(let predicate): return "[]<>\(try state(predicate))"
        case .eventuallyAlways(let predicate): return "<>[]\(try state(predicate))"
        case .leadsTo(let source, let target): return "(\(try state(source)) ~> \(try state(target)))"
        }
    }

    func formalDefinition(_ definition: CompiledFormalOperatorDefinition) throws -> String {
        let name = try operatorName(definition.id)
        let parameters = try definition.parameters.map(formalParameter).joined(separator: ", ")
        return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == \(try state(definition.body))"
    }

    func recursiveFunction(_ function: CompiledRecursiveFunction) throws -> (declaration: String, body: String) {
        let name = try operatorName(function.id)
        let parameters = try function.parameters.map(binderName)
        return (
            declaration: "RECURSIVE \(name)(\(parameters.map { _ in "_" }.joined(separator: ", ")))",
            body: "\(name)(\(parameters.joined(separator: ", "))) == \(try state(function.body))"
        )
    }

    func fairness(
        _ condition: CompiledFairnessCondition,
        vars: String,
        actionNames: [ActionID: String],
        actionCalls: [CompiledActionCall: String]
    ) throws -> String {
        let action: String
        switch condition.scope {
        case .next:
            action = "Next"
        case .action(let id):
            guard let name = actionNames[id] else { throw missing("action", id.ordinal) }
            action = name
        case .actionCall(let call):
            guard let name = actionCalls[call] else { throw missing("action", call.action.ordinal) }
            action = name
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

    func state(_ expression: CompiledStateExpr) throws -> String {
        var tasks = [StateRenderingTask.expression(expression)]
        var parts: [String] = []

        func schedule(_ prefix: String, _ expressions: [CompiledStateExpr], separator: String, suffix: String) {
            parts.append(prefix)
            tasks.append(.text(suffix))
            for (index, expression) in expressions.enumerated().reversed() {
                tasks.append(.expression(expression))
                if index > 0 {
                    tasks.append(.text(separator))
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
            case .formalArgument(let argument):
                switch argument {
                case .value(let value): tasks.append(.expression(value))
                case .operator(let operation): tasks.append(.formalOperator(operation))
                }
            case .formalOperator(let operation):
                switch operation {
                case .lambda(let lambda):
                    parts.append("LAMBDA \(try lambda.parameters.map(binderName).joined(separator: ", ")) : ")
                    tasks.append(.expression(lambda.body))
                case .reference(let id, _):
                    parts.append(try operatorName(id))
                }
            case .localOperator(let operation):
                let name = try operatorName(operation.id)
                let parameters = try operation.parameters.map(binderName).joined(separator: ", ")
                if let domain = operation.domain, let parameter = operation.parameters.first {
                    parts.append("\(name)[\(try binderName(parameter)) \\in ")
                    schedule([.expression(domain), .text("] == "), .expression(operation.body)])
                } else {
                    parts.append("\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == ")
                    tasks.append(.expression(operation.body))
                }
            case .expression(let expression):
                switch expression {
                case .add(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " + ", suffix: ")")
                case .subtract(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " - ", suffix: ")")
                case .multiply(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " * ", suffix: ")")
                case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs):
                    schedule("(", [lhs, rhs], separator: " \\div ", suffix: ")")
                case .modulo(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " % ", suffix: ")")
                case .equal(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " = ", suffix: ")")
                case .notEqual(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " /= ", suffix: ")")
                case .lessThan(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " < ", suffix: ")")
                case .lessOrEqual(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " <= ", suffix: ")")
                case .greaterThan(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " > ", suffix: ")")
                case .greaterOrEqual(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " >= ", suffix: ")")
                case .and(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " /\\ ", suffix: ")")
                case .or(let lhs, let rhs): schedule("(IF ", [lhs, rhs], separator: " THEN TRUE ELSE ", suffix: ")")
                case .in(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\in ", suffix: ")")
                case .subset(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\subseteq ", suffix: ")")
                case .union(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\cup ", suffix: ")")
                case .intersection(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\cap ", suffix: ")")
                case .setDifference(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\ ", suffix: ")")
                case .tupleDynamicAccess(let lhs, let rhs): schedule("", [lhs, rhs], separator: "[", suffix: "]")
                case .tupleAppend(let lhs, let rhs): schedule("Append(", [lhs, rhs], separator: ", ", suffix: ")")
                case .tupleConcatenate(let lhs, let rhs): schedule("(", [lhs, rhs], separator: " \\o ", suffix: ")")
                case .functionApply(let lhs, let rhs): schedule("", [lhs, rhs], separator: "[", suffix: "]")
                case .functionSet(let lhs, let rhs): schedule("[", [lhs, rhs], separator: " -> ", suffix: "]")
                case .setSum(let lhs, let rhs): schedule("Sum(", [lhs, rhs], separator: ", ", suffix: ")")
                case .integerRange(let lhs, let rhs): schedule("", [lhs, rhs], separator: "..", suffix: "")
                case .negate(let value): schedule("(-", [value], separator: "", suffix: ")")
                case .not(let value): schedule("(~", [value], separator: "", suffix: ")")
                case .cardinality(let value): schedule("Cardinality(", [value], separator: "", suffix: ")")
                case .powerSet(let value): schedule("SUBSET ", [value], separator: "", suffix: "")
                case .unionAll(let value): schedule("UNION ", [value], separator: "", suffix: "")
                case .tupleLength(let value): schedule("Len(", [value], separator: "", suffix: ")")
                case .tupleHead(let value): schedule("Head(", [value], separator: "", suffix: ")")
                case .tupleTail(let value): schedule("Tail(", [value], separator: "", suffix: ")")
                case .domain(let value): schedule("DOMAIN ", [value], separator: "", suffix: "")
                case .sequenceFromSet(let value): schedule("SeqFromSet(", [value], separator: "", suffix: ")")
                case .ifThenElse(let condition, let then, let otherwise):
                    parts.append("(IF ")
                    schedule([
                        .expression(condition), .text(" THEN "), .expression(then),
                        .text(" ELSE "), .expression(otherwise), .text(")")
                    ])
                case .value(let value): parts.append(value.description)
                case .stateVariable(let variable): parts.append(try variableName(variable))
                case .boundValue(let binder): parts.append(try binderName(binder))
                case .controlLocation(let location): parts.append(try controlLocationName(location))
                case .operatorReference(let operation): parts.append(try operatorName(operation))
                case .setLiteral(let values): schedule("{", values, separator: ", ", suffix: "}")
                case .setFilter(let set, let binder, let predicate):
                    parts.append("{\(try binderName(binder)) \\in ")
                    schedule([.expression(set), .text(" : "), .expression(predicate), .text("}")])
                case .setMap(let value, let binder, let set):
                    parts.append("{")
                    schedule([
                        .expression(value), .text(" : \(try binderName(binder)) \\in "),
                        .expression(set), .text("}")
                    ])
                case .tupleLiteral(let values): schedule("<<", values, separator: ", ", suffix: ">>")
                case .tupleAccess(let tuple, let index):
                    schedule([.expression(tuple), .text("[\(index)]")])
                case .recordLiteral(let record):
                    var fields: [StateRenderingTask] = []
                    for (index, field) in record.fields.enumerated() {
                        if index > 0 { fields.append(.text(", ")) }
                        fields.append(.text("\(try fieldName(field.id)) |-> "))
                        fields.append(.expression(field.value))
                    }
                    parts.append("[")
                    fields.append(.text("]"))
                    schedule(fields)
                case .recordAccess(let record, let field, _):
                    parts.append("(")
                    schedule([.expression(record), .text(").\(try fieldName(field))")])
                case .functionLiteral(let domain, let binder, let body):
                    parts.append("[\(try binderName(binder)) \\in ")
                    schedule([.expression(domain), .text(" |-> "), .expression(body), .text("]")])
                case .except(let function, let key, let value):
                    parts.append("[")
                    schedule([
                        .expression(function), .text(" EXCEPT !["), .expression(key),
                        .text("] = "), .expression(value), .text("]")
                    ])
                case .caseExpr(let first, let remaining, let otherwise):
                    var branches: [StateRenderingTask] = []
                    for (index, branch) in ([first] + remaining).enumerated() {
                        if index > 0 { branches.append(.text(" [] ")) }
                        branches.append(.expression(branch.condition))
                        branches.append(.text(" -> "))
                        branches.append(.expression(branch.value))
                    }
                    if let otherwise {
                        branches.append(.text(" [] "))
                        branches.append(.text("OTHER -> "))
                        branches.append(.expression(otherwise))
                    }
                    parts.append("CASE ")
                    schedule(branches)
                case .forAll(let set, let binder, let predicate):
                    parts.append("\\A \(try binderName(binder)) \\in ")
                    schedule([.expression(set), .text(" : "), .expression(predicate)])
                case .exists(let set, let binder, let predicate):
                    parts.append("\\E \(try binderName(binder)) \\in ")
                    schedule([.expression(set), .text(" : "), .expression(predicate)])
                case .choose(let set, let binder, let predicate):
                    parts.append("CHOOSE \(try binderName(binder)) \\in ")
                    schedule([.expression(set), .text(" : "), .expression(predicate)])
                case .enabledAction(let action): parts.append("ENABLED \(try actionName(action))")
                case .foldFunction(let operation, let initial, let sequence):
                    parts.append("FoldFunction(")
                    schedule([
                        .formalOperator(.lambda(operation)), .text(", "), .expression(initial),
                        .text(", "), .expression(sequence), .text(")")
                    ])
                case .lambdaApplication(let lambda, let arguments):
                    var rendered: [StateRenderingTask] = []
                    for (index, pair) in zip(lambda.parameters, arguments).enumerated() {
                        if index > 0 { rendered.append(.text(" ")) }
                        rendered.append(.text("\(try binderName(pair.0)) == "))
                        rendered.append(.expression(pair.1))
                    }
                    parts.append("LET ")
                    rendered.append(.text(" IN "))
                    rendered.append(.expression(lambda.body))
                    schedule(rendered)
                case .operatorApplication(let operation, let arguments):
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
                case .recursiveCall(let operation, let arguments):
                    parts.append(try operatorName(operation))
                    if arguments.isEmpty == false {
                        var rendered: [StateRenderingTask] = []
                        for (index, argument) in arguments.enumerated() {
                            if index > 0 { rendered.append(.text(", ")) }
                            rendered.append(.expression(argument))
                        }
                        parts.append("(")
                        rendered.append(.text(")"))
                        schedule(rendered)
                    }
                case .letValue(let binder, let value, let body):
                    parts.append("LET \(try binderName(binder)) == ")
                    schedule([.expression(value), .text(" IN "), .expression(body)])
                case .letIn(let operations, let body):
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
                    parts.append("LET ")
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
                    schedule(rendered)
                }
            }
        }
        return parts.joined()
    }

    private func formalParameter(_ parameter: CompiledFormalParameter) throws -> String {
        switch parameter {
        case .value(let binder): return try binderName(binder)
        case .operator(let operation, let arity):
            return "\(try operatorName(operation))(\(Array(repeating: "_", count: arity).joined(separator: ", ")))"
        }
    }

    func variableName(_ id: VariableID) throws -> String {
        guard layout.variables.indices.contains(id.ordinal) else { throw missing("variable", id.ordinal) }
        return layout.variables[id.ordinal].declaration.name
    }

    private func actionName(_ id: ActionID) throws -> String {
        guard layout.actions.indices.contains(id.ordinal) else { throw missing("action", id.ordinal) }
        return layout.actions[id.ordinal].declaration.name
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

    private func fieldName(_ id: FieldID) throws -> String {
        guard let field = layout.field(id) else { throw missing("field", id.ordinal) }
        return field.renderedName
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
