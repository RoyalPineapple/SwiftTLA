private enum StateRenderingTask {
    case expression(CompiledStateExpr)
    case text(String)
}

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

        while let task = tasks.popLast() {
            switch task {
            case .text(let text):
                parts.append(text)
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
                    tasks.append(.text(")"))
                    tasks.append(.expression(otherwise))
                    tasks.append(.text(" ELSE "))
                    tasks.append(.expression(then))
                    tasks.append(.text(" THEN "))
                    tasks.append(.expression(condition))
                default:
                    parts.append(try recursiveState(expression))
                }
            }
        }
        return parts.joined()
    }

    private func recursiveState(_ expression: CompiledStateExpr) throws -> String {
        switch expression {
        case .value(let value): return value.description
        case .stateVariable(let variable): return try variableName(variable)
        case .boundValue(let binder): return try binderName(binder)
        case .controlLocation(let location): return try controlLocationName(location)
        case .operatorReference(let operation): return try operatorName(operation)
        case .add, .subtract, .multiply, .divide, .modulo, .integerDivide,
             .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
             .and, .or, .in, .subset, .union, .intersection, .setDifference,
             .tupleDynamicAccess, .tupleAppend, .tupleConcatenate,
             .functionApply, .functionSet, .setSum, .integerRange,
             .negate, .not, .cardinality, .powerSet, .unionAll,
             .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet,
             .ifThenElse:
            throw invalidStateTraversal()
        case .setLiteral(let values):
            return values.isEmpty ? "{}" : "{\(try values.map(state).joined(separator: ", "))}"
        case .setFilter(let set, let binder, let predicate):
            return "{\(try binderName(binder)) \\in \(try state(set)) : \(try state(predicate))}"
        case .setMap(let value, let binder, let set):
            return "{\(try state(value)) : \(try binderName(binder)) \\in \(try state(set))}"
        case .tupleLiteral(let values): return "<<\(try values.map(state).joined(separator: ", "))>>"
        case .tupleAccess(let tuple, let index): return "\(try state(tuple))[\(index)]"
        case .recordLiteral(let record):
            return "[\(try record.fields.map { "\(try fieldName($0.id)) |-> \(try state($0.value))" }.joined(separator: ", "))]"
        case .recordAccess(let record, let field, _): return "(\(try state(record))).\(try fieldName(field))"
        case .functionLiteral(let domain, let binder, let body):
            return "[\(try binderName(binder)) \\in \(try state(domain)) |-> \(try state(body))]"
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

    private func invalidStateTraversal() -> CompilationDiagnostic {
        .init(
            code: .invalidFormalDeclaration,
            stage: .rendering,
            path: "compiledRenderer.state",
            expected: "one rendered expression for each compiled expression",
            actual: "the rendering traversal bypassed its expression stack",
            nextSafeAction: "Retain the compiled specification and report this compiler defect."
        )
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
