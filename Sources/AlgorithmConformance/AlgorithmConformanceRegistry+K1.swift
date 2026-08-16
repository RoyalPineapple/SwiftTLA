import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Canonical PlusCal lexical bindings and typed macro substitution in one
    /// deterministic, externally renderable step.
    public static let scopeBindingSubstitution = AlgorithmConformanceFixture(
        id: "scope-binding-substitution",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K1ScopeBindingSubstitutionTLCWitness.spec }
    )
}
