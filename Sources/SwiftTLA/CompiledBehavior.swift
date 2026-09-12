/// The transition relation and its properties, shared by compiler stages and backends.
package struct CompiledBehavior<Expression: Sendable>: Sendable {
    package let checkDeadlock: Bool
    package let initializations: [(variable: VariableID, initialization: CompiledVariableInitialization<Expression>)]
    package let actions: [CompiledAction<Expression>]
    /// Indices into actions, with ENABLED dependencies before their users.
    package let enabledActionIndices: [Int]
    /// Transitive ENABLED dependencies, excluding the action itself.
    package let enabledActionDependencies: [ActionID: Set<ActionID>]
    package let invariants: [CompiledInvariant<Expression>]
    package let temporalProperties: [CompiledTemporal<CompiledStateQuery<Expression>>]
    package let fairness: [CompiledFairnessCondition]
    package let constraint: CompiledStateQuery<Expression>?
    package let assume: CompiledStateQuery<Expression>?

    package func map<Result: Sendable>(
        _ transform: (Expression) throws -> Result
    ) rethrows -> CompiledBehavior<Result> {
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
