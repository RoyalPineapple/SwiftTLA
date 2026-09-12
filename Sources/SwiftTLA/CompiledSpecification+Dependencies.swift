extension CompiledActionExpr where Expression == CompiledStateExpr {
    func enabledActionDependencies(
        operators: CompiledOperators
    ) -> Set<ActionID> {
        func expression(_ value: CompiledStateExpr) -> Set<ActionID> {
            value.stateRequirements(operators: operators).enabledActions
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

}

extension CompiledStateExpr {
    package func enabledActionDependencies(
        operators: CompiledOperators, actionDependencies: [ActionID: Set<ActionID>]
    ) -> Set<ActionID> {
        let direct = stateRequirements(operators: operators).enabledActions
        return direct.reduce(into: direct) { dependencies, action in
            dependencies.formUnion(actionDependencies[action] ?? [])
        }
    }
}

extension CompiledStateQuery where Expression == CompiledStateExpr {
    init(expression: CompiledStateExpr, operators: CompiledOperators,
         actionDependencies: [ActionID: Set<ActionID>]) {
        self.init(expression: expression, enabledActions: expression.enabledActionDependencies(
            operators: operators, actionDependencies: actionDependencies))
    }
}
