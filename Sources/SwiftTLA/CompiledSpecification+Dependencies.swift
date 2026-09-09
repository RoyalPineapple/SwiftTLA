extension CompiledStateExpr {
    func requiresEnabledActions(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> Bool {
        stateRequirements(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions).requiresCompleteState
    }
}

extension CompiledActionExpr {
    func enabledActionDependencies(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> Set<ActionID> {
        func expression(_ value: CompiledStateExpr) -> Set<ActionID> {
            value.stateRequirements(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions).enabledActions
        }
        func action(_ value: CompiledActionExpr) -> Set<ActionID> {
            value.enabledActionDependencies(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions)
        }
        switch self {
        case .assign(_, let value), .guard_(let value): return expression(value)
        case .unchanged: return []
        case .existsAction(_, let domain, let body), .define(_, let domain, let body):
            return expression(domain).union(action(body))
        case .ifElse(let condition, let then, let otherwise):
            return expression(condition).union(action(then)).union(action(otherwise))
        case .and(let lhs, let rhs), .or(let lhs, let rhs): return action(lhs).union(action(rhs))
        }
    }

    func requiresEnabledActions(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> Bool {
        !enabledActionDependencies(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions).isEmpty
    }
}

extension CompiledSpecification {
    package func requiresEnabledActions(in expression: CompiledStateExpr) -> Bool {
        expression.requiresEnabledActions(formalOperators: semantics.formalOperatorDefinitions, recursiveFunctions: semantics.recursiveFunctions)
    }

    package func requiresEnabledActions(in action: CompiledActionExpr) -> Bool {
        action.requiresEnabledActions(formalOperators: semantics.formalOperatorDefinitions, recursiveFunctions: semantics.recursiveFunctions)
    }
}
