/// The transition relation and its properties, shared by compiler stages and backends.
package struct CompiledBehavior: Sendable {
    package let checkDeadlock: Bool
    package let parameterDomains: [BinderID: CompiledExpression]
    package let validationScenarios: [CompiledValidationScenario]
    package let initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)]
    package let actions: [CompiledAction]
    /// Indices into actions, with ENABLED dependencies before their users.
    package let enabledActionIndices: [Int]
    /// Transitive ENABLED dependencies, excluding the action itself.
    package let enabledActionDependencies: [ActionID: Set<ActionID>]
    package let invariants: [CompiledStatePredicate]
    package let reachabilityProperties: [CompiledStatePredicate]
    package let temporalProperties: [CompiledTemporal<CompiledStateQuery>]
    package let fairness: [CompiledFairnessCondition]
    package let constraint: CompiledStateQuery?
    package let assume: CompiledStateQuery?

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledBehavior {
        try .init(
            checkDeadlock: checkDeadlock,
            parameterDomains: parameterDomains.mapValues(transform),
            validationScenarios: validationScenarios.map {
                try .init(name: $0.name, bindings: $0.bindings.mapValues(transform),
                    expectations: $0.expectations, deadlockExpectation: $0.deadlockExpectation,
                    checks: $0.checks, checkDeadlock: $0.checkDeadlock, behavior: $0.behavior)
            },
            initializations: initializations.map {
                (variable: $0.variable, initialization: try $0.initialization.map(transform))
            },
            actions: actions.map { try $0.map(transform) },
            enabledActionIndices: enabledActionIndices,
            enabledActionDependencies: enabledActionDependencies,
            invariants: invariants.map { try $0.map(transform) },
            reachabilityProperties: reachabilityProperties.map { try $0.map(transform) },
            temporalProperties: temporalProperties.map { property in
                try .init(id: property.id, name: property.name,
                    expression: property.expression.map { try $0.map(transform) },
                    bindings: property.bindings.map { try $0.map(transform) })
            },
            fairness: fairness.map { try $0.map(transform) },
            constraint: constraint.map { try $0.map(transform) },
            assume: assume.map { try $0.map(transform) })
    }

}

package struct CompiledValidationScenario: Sendable {
    package let name: String
    package let bindings: [BinderID: CompiledExpression]
    package let expectations: [PropertyID: ValidationExpectation]
    package let deadlockExpectation: ValidationExpectation?
    package let checks: Set<PropertyID>
    package let checkDeadlock: Bool
    package let behavior: ModelBehavior
}
