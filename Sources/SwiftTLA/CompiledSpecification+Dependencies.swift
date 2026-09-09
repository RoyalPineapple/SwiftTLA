extension CompiledActionExpr where Expression == CompiledStateExpr {
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

}

extension CompiledSpecification {
    package func enabledActionDependencies(in expression: CompiledStateExpr) -> Set<ActionID> {
        let direct = expression.stateRequirements(
            formalOperators: semantics.formalOperatorDefinitions,
            recursiveFunctions: semantics.recursiveFunctions
        ).enabledActions
        return direct.reduce(into: direct) { dependencies, action in
            dependencies.formUnion(semantics.enabledActionDependencies[action] ?? [])
        }
    }
}
