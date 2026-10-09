/// The transition relation and its properties, shared by compiler stages and backends.
package struct CompiledBehavior: Sendable {
    package let checkDeadlock: Bool
    package let parameterDomains: [BinderID: CompiledExpression]
    package let checkingRegisterInitializations: [CheckingRegisterID: CompiledExpression]
    package let validationScenarios: [CompiledValidationScenario]
    package let initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)]
    package let initialInvariant: PropertyID?
    package let actions: [CompiledAction]
    /// Indices into actions, with ENABLED dependencies before their users.
    package let enabledActionIndices: [Int]
    /// Transitive ENABLED dependencies, excluding the action itself.
    package let enabledActionDependencies: [ActionID: Set<ActionID>]
    package let invariants: [CompiledStatePredicate]
    package let reachabilityProperties: [CompiledStatePredicate]
    package let temporalProperties: [CompiledTemporal<CompiledStateQuery>]
    package let fairness: [CompiledFairnessCondition]
    package let fairnessProfiles: [CompiledFairnessProfile]
    package let constraint: CompiledStateQuery?
    package let actionConstraint: CompiledStateQuery?
    package let assume: CompiledStateQuery?

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledBehavior {
        try .init(
            checkDeadlock: checkDeadlock,
            parameterDomains: parameterDomains.mapValues(transform),
            checkingRegisterInitializations: checkingRegisterInitializations.mapValues(transform),
            validationScenarios: try validationScenarios.map { scenario -> CompiledValidationScenario in
                let bindings = try scenario.bindings.mapValues(transform)
                let view = try scenario.view.map(transform)
                let postcondition = try scenario.postcondition.map(transform)
                return .init(name: scenario.name, displayLabel: scenario.displayLabel,
                    bindings: bindings, expectations: scenario.expectations,
                    deadlockExpectation: scenario.deadlockExpectation,
                    checks: scenario.checks, checkDeadlock: scenario.checkDeadlock,
                    behavior: scenario.behavior, checkingMode: scenario.checkingMode,
                    symmetry: scenario.symmetry, fairnessProfileIndex: scenario.fairnessProfileIndex,
                    view: view, postcondition: postcondition,
                    postconditionName: scenario.postconditionName,
                    postconditionExpectation: scenario.postconditionExpectation)
            },
            initializations: initializations.map {
                (variable: $0.variable, initialization: try $0.initialization.map(transform))
            },
            initialInvariant: initialInvariant,
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
            fairnessProfiles: try fairnessProfiles.map { profile in
                .init(name: profile.name, operatorName: profile.operatorName,
                    excludedActions: profile.excludedActions,
                    fairness: try profile.fairness.map { try $0.map(transform) })
            },
            constraint: constraint.map { try $0.map(transform) },
            actionConstraint: actionConstraint.map { try $0.map(transform) },
            assume: assume.map { try $0.map(transform) })
    }

}

package struct CompiledFairnessProfile: Sendable {
    package let name: String
    package let operatorName: String
    package let excludedActions: Set<ActionID>
    package let fairness: [CompiledFairnessCondition]
}

package struct CompiledValidationScenario: Sendable {
    package let name: String
    package let displayLabel: String?
    package let bindings: [BinderID: CompiledExpression]
    package let expectations: [PropertyID: ValidationExpectation]
    package let deadlockExpectation: ValidationExpectation?
    package let checks: Set<PropertyID>
    package let checkDeadlock: Bool
    package let behavior: ModelBehavior
    package let checkingMode: ValidationCheckingMode
    package let symmetry: SymmetrySet?
    package let fairnessProfileIndex: Int?
    package let view: CompiledExpression?
    package let postcondition: CompiledExpression?
    package let postconditionName: String?
    package let postconditionExpectation: ValidationExpectation?
}
