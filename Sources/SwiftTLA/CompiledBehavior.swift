/// The transition relation and its properties, shared by compiler stages and backends.
package struct CompiledBehavior: Sendable {
    package let checkDeadlock: Bool
    package let initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)]
    package let actions: [CompiledAction]
    /// Indices into actions, with ENABLED dependencies before their users.
    package let enabledActionIndices: [Int]
    /// Transitive ENABLED dependencies, excluding the action itself.
    package let enabledActionDependencies: [ActionID: Set<ActionID>]
    package let invariants: [CompiledInvariant]
    package let temporalProperties: [CompiledTemporal<CompiledStateQuery>]
    package let fairness: [CompiledFairnessCondition]
    package let constraint: CompiledStateQuery?
    package let assume: CompiledStateQuery?

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledBehavior {
        try .init(
            checkDeadlock: checkDeadlock,
            initializations: initializations.map {
                (variable: $0.variable, initialization: try $0.initialization.map(transform))
            },
            actions: actions.map { try $0.map(transform) },
            enabledActionIndices: enabledActionIndices,
            enabledActionDependencies: enabledActionDependencies,
            invariants: invariants.map { try $0.map(transform) },
            temporalProperties: temporalProperties.map { property in
                try property.map { try $0.map(transform) }
            },
            fairness: fairness,
            constraint: constraint.map { try $0.map(transform) },
            assume: assume.map { try $0.map(transform) })
    }

}
