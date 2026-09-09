extension CompiledStateExpr {
    func requiresEnabledActions(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> Bool {
        stateRequirements(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions).requiresCompleteState
    }
}

extension CompiledActionExpr {
    func requiresEnabledActions(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> Bool {
        func expression(_ value: CompiledStateExpr) -> Bool {
            value.requiresEnabledActions(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions)
        }
        func action(_ value: CompiledActionExpr) -> Bool {
            value.requiresEnabledActions(formalOperators: formalOperators, recursiveFunctions: recursiveFunctions)
        }
        switch self {
        case .assign(_, let value), .guard_(let value): return expression(value)
        case .unchanged: return false
        case .existsAction(_, let domain, let body), .define(_, let domain, let body):
            return expression(domain) || action(body)
        case .ifElse(let condition, let then, let otherwise):
            return expression(condition) || action(then) || action(otherwise)
        case .and(let lhs, let rhs), .or(let lhs, let rhs): return action(lhs) || action(rhs)
        }
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
