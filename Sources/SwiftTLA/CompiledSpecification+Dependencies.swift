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
        var dependencies: Set<ActionID> = []
        var pending = [self]
        while let action = pending.popLast() {
            switch action {
            case .assign(_, let value), .guard_(let value): dependencies.formUnion(expression(value))
            case .unchanged: break
            case .existsAction(_, let domain, let body), .define(_, let domain, let body):
                dependencies.formUnion(expression(domain))
                pending.append(body)
            case .ifElse(let condition, let then, let otherwise):
                dependencies.formUnion(expression(condition))
                pending.append(contentsOf: [otherwise, then])
            case .and(let lhs, let rhs), .or(let lhs, let rhs): pending.append(contentsOf: [rhs, lhs])
            }
        }
        return dependencies
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
