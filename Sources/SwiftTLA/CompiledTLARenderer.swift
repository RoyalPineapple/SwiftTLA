struct CompiledTLARenderer {
    let layout: CompiledLayout
    let bindings: CompiledBindingTable

    func action(_ expression: CompiledActionExpr) throws -> String {
        switch expression {
        case .assign(let variable, let value):
            return "\(try variableName(variable))' = \(try state(value))"
        case .unchanged(let variable):
            return "UNCHANGED \(try variableName(variable))"
        case .guard_(let condition):
            return try state(condition)
        case .chooseAction(let variable, let set):
            return "\(try variableName(variable))' \\in \(try state(set))"
        case .existsAction(let binder, let set, let body):
            return "\\E \(try binderName(binder)) \\in \(try state(set)): \(try action(body))"
        case .ifElse(let condition, let then, let otherwise):
            return "IF \(try state(condition)) THEN (\(try action(then))) ELSE (\(try action(otherwise)))"
        case .define(let binder, let value, let body):
            return "LET \(try binderName(binder)) == \(try state(value)) IN \(try action(body))"
        case .and(let lhs, let rhs):
            return "(\(try action(lhs)) /\\ \(try action(rhs)))"
        case .or(let lhs, let rhs):
            return "(\(try action(lhs)) \\/ \(try action(rhs)))"
        }
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

    func theorem(_ theorem: CompiledTheorem) throws -> String {
        switch theorem.body {
        case .temporal(let expression):
            return "\(theorem.name) == Spec => \(try temporal(expression))"
        case .state(let expression):
            return "\(theorem.name) == Spec => []\(try state(expression))"
        }
    }

    func formalModuleReplacement(_ replacement: CompiledFormalModuleReplacement) throws -> String {
        "\(replacement.definitionName) == \(try state(replacement.expression))"
    }

    func state(_ expression: CompiledStateExpr) throws -> String {
        switch expression {
        case .value(let value): return value.description
        case .stateVariable(let variable): return try variableName(variable)
        case .boundValue(let binder): return try binderName(binder)
        case .controlLocation(let location): return try controlLocationName(location)
        case .operatorReference(let operation): return try operatorName(operation)
        case .add(let lhs, let rhs): return "(\(try state(lhs)) + \(try state(rhs)))"
        case .subtract(let lhs, let rhs): return "(\(try state(lhs)) - \(try state(rhs)))"
        case .multiply(let lhs, let rhs): return "(\(try state(lhs)) * \(try state(rhs)))"
        case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs): return "(\(try state(lhs)) \\div \(try state(rhs)))"
        case .modulo(let lhs, let rhs): return "(\(try state(lhs)) % \(try state(rhs)))"
        case .negate(let value): return "(-\(try state(value)))"
        case .equal(let lhs, let rhs): return "(\(try state(lhs)) = \(try state(rhs)))"
        case .notEqual(let lhs, let rhs): return "(\(try state(lhs)) /= \(try state(rhs)))"
        case .lessThan(let lhs, let rhs): return "(\(try state(lhs)) < \(try state(rhs)))"
        case .lessOrEqual(let lhs, let rhs): return "(\(try state(lhs)) <= \(try state(rhs)))"
        case .greaterThan(let lhs, let rhs): return "(\(try state(lhs)) > \(try state(rhs)))"
        case .greaterOrEqual(let lhs, let rhs): return "(\(try state(lhs)) >= \(try state(rhs)))"
        case .and(let lhs, let rhs): return "(\(try state(lhs)) /\\ \(try state(rhs)))"
        case .or(let lhs, let rhs): return "(IF \(try state(lhs)) THEN TRUE ELSE \(try state(rhs)))"
        case .not(let value): return "(~\(try state(value)))"
        case .ifThenElse(let condition, let then, let otherwise):
            return "(IF \(try state(condition)) THEN \(try state(then)) ELSE \(try state(otherwise)))"
        case .setLiteral(let values):
            return values.isEmpty ? "{}" : "{\(try values.map(state).joined(separator: ", "))}"
        case .in(let member, let set): return "(\(try state(member)) \\in \(try state(set)))"
        case .subset(let lhs, let rhs): return "(\(try state(lhs)) \\subseteq \(try state(rhs)))"
        case .union(let lhs, let rhs): return "(\(try state(lhs)) \\cup \(try state(rhs)))"
        case .intersection(let lhs, let rhs): return "(\(try state(lhs)) \\cap \(try state(rhs)))"
        case .setDifference(let lhs, let rhs): return "(\(try state(lhs)) \\ \(try state(rhs)))"
        case .cardinality(let value): return "Cardinality(\(try state(value)))"
        case .setFilter(let set, let binder, let predicate):
            return "{\(try binderName(binder)) \\in \(try state(set)) : \(try state(predicate))}"
        case .setMap(let value, let binder, let set):
            return "{\(try state(value)) : \(try binderName(binder)) \\in \(try state(set))}"
        case .powerSet(let value): return "SUBSET \(try state(value))"
        case .unionAll(let value): return "UNION \(try state(value))"
        case .integerRange(let lower, let upper): return "\(try state(lower))..\(try state(upper))"
        case .tupleLiteral(let values): return "<<\(try values.map(state).joined(separator: ", "))>>"
        case .tupleAccess(let tuple, let index): return "\(try state(tuple))[\(index)]"
        case .tupleDynamicAccess(let tuple, let index): return "\(try state(tuple))[\(try state(index))]"
        case .tupleLength(let tuple): return "Len(\(try state(tuple)))"
        case .tupleAppend(let tuple, let value): return "Append(\(try state(tuple)), \(try state(value)))"
        case .tupleHead(let tuple): return "Head(\(try state(tuple)))"
        case .tupleTail(let tuple): return "Tail(\(try state(tuple)))"
        case .tupleConcatenate(let lhs, let rhs): return "(\(try state(lhs)) \\o \(try state(rhs)))"
        case .recordLiteral(let record):
            return "[\(try record.fields.map { "\(try fieldName($0.id)) |-> \(try state($0.value))" }.joined(separator: ", "))]"
        case .recordAccess(let record, let field, _): return "(\(try state(record))).\(try fieldName(field))"
        case .domain(let function): return "DOMAIN \(try state(function))"
        case .functionLiteral(let domain, let binder, let body):
            return "[\(try binderName(binder)) \\in \(try state(domain)) |-> \(try state(body))]"
        case .functionApply(let function, let argument): return "\(try state(function))[\(try state(argument))]"
        case .except(let function, let key, let value):
            return "[\(try state(function)) EXCEPT \u{21}[\(try state(key))] = \(try state(value))]"
        case .caseExpr(let pairs, let otherwise):
            let cases = try stride(from: 0, to: pairs.count, by: 2).map {
                "\(try state(pairs[$0])) -> \(try state(pairs[$0 + 1]))"
            }.joined(separator: " [] ")
            if let otherwise { return "CASE \(cases) [] OTHER -> \(try state(otherwise))" }
            return "CASE \(cases)"
        case .forAll(let set, let binder, let predicate): return "\\A \(try binderName(binder)) \\in \(try state(set)) : \(try state(predicate))"
        case .exists(let set, let binder, let predicate): return "\\E \(try binderName(binder)) \\in \(try state(set)) : \(try state(predicate))"
        case .choose(let set, let binder, let predicate): return "CHOOSE \(try binderName(binder)) \\in \(try state(set)) : \(try state(predicate))"
        case .enabledAction(let action): return "ENABLED \(try actionName(action))"
        case .sequenceFromSet(let value): return "SeqFromSet(\(try state(value)))"
        case .setSum(let function, let set): return "Sum(\(try state(function)), \(try state(set)))"
        case .functionSet(let domain, let range): return "[\(try state(domain)) -> \(try state(range))]"
        case .foldFunction(let operation, let initial, let sequence):
            return "FoldFunction(\(try formalLambda(operation)), \(try state(initial)), \(try state(sequence)))"
        case .operatorApplication(let operation, let arguments):
            switch operation {
            case .lambda(let lambda):
                let bindings = try lambdaBindings(lambda, arguments: arguments)
                return "LET \(bindings) IN \(try state(lambda.body))"
            case .reference:
                let arguments = try arguments.map(formalArgument).joined(separator: ", ")
                let name = try formalOperator(operation)
                return arguments.isEmpty ? name : "\(name)(\(arguments))"
            }
        case .recursiveCall(let operation, let arguments):
            let name = try operatorName(operation)
            return arguments.isEmpty ? name : "\(name)(\(try arguments.map(state).joined(separator: ", ")))"
        case .letValue(let binder, let value, let body):
            return "LET \(try binderName(binder)) == \(try state(value)) IN \(try state(body))"
        case .letIn(let operations, let body):
            let recursiveDeclarations = try operations
                .filter { $0.isRecursive && $0.domain == nil }
                .map { operation in
                    let name = try operatorName(operation.id)
                    let slots = Array(repeating: "_", count: operation.parameters.count).joined(separator: ", ")
                    return operation.parameters.isEmpty ? name : "\(name)(\(slots))"
                }
                .joined(separator: ", ")
            let declarations = try operations.map(localOperator).joined(separator: "\n    ")
            let recursive = recursiveDeclarations.isEmpty ? "" : "RECURSIVE \(recursiveDeclarations)\n    "
            return "LET \(recursive)\(declarations)\nIN \(try state(body))"
        }
    }

    private func formalArgument(_ argument: CompiledFormalCallArgument) throws -> String {
        switch argument {
        case .value(let value): return try state(value)
        case .operator(let operation): return try formalOperator(operation)
        }
    }

    private func formalParameter(_ parameter: CompiledFormalParameter) throws -> String {
        switch parameter {
        case .value(let binder): return try binderName(binder)
        case .operator(let operation, let arity):
            return "\(try operatorName(operation))(\(Array(repeating: "_", count: arity).joined(separator: ", ")))"
        }
    }

    private func lambdaBindings(
        _ lambda: CompiledFormalLambda,
        arguments: [CompiledFormalCallArgument]
    ) throws -> String {
        guard lambda.parameters.count == arguments.count else {
            throw CompilationDiagnostic(
                code: .unknownReference,
                stage: .rendering,
                path: "compiledRenderer.lambdaApplication",
                expected: "one formal value for each lambda parameter",
                actual: "\(arguments.count) arguments for \(lambda.parameters.count) parameters",
                nextSafeAction: "Compile the source model again before rendering."
            )
        }
        return try zip(lambda.parameters, arguments).map { parameter, argument in
            guard case .value(let value) = argument else {
                throw CompilationDiagnostic(
                    code: .unknownReference,
                    stage: .rendering,
                    path: "compiledRenderer.lambdaApplication",
                    expected: "a formal value lambda argument",
                    actual: "a formal operator argument",
                    nextSafeAction: "Compile the source model again before rendering."
                )
            }
            return "\(try binderName(parameter)) == \(try state(value))"
        }.joined(separator: " ")
    }

    private func formalOperator(_ operation: CompiledFormalOperator) throws -> String {
        switch operation {
        case .lambda(let lambda):
            return try formalLambda(lambda)
        case .reference(let id, _): return try operatorName(id)
        }
    }

    private func formalLambda(_ lambda: CompiledFormalLambda) throws -> String {
        "LAMBDA \(try lambda.parameters.map(binderName).joined(separator: ", ")) : \(try state(lambda.body))"
    }

    private func localOperator(_ operation: CompiledLocalOperator) throws -> String {
        let name = try operatorName(operation.id)
        let parameters = try operation.parameters.map(binderName).joined(separator: ", ")
        if let domain = operation.domain, let parameter = operation.parameters.first {
            return "\(name)[\(try binderName(parameter)) \\in \(try state(domain))] == \(try state(operation.body))"
        }
        return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == \(try state(operation.body))"
    }

    private func variableName(_ id: VariableID) throws -> String {
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
