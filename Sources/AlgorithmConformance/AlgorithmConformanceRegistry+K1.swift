import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K1 isolates canonical PlusCal lexical bindings and typed macro
    /// substitution in one deterministic, externally renderable step.
    public static let k1ScopeBindingSubstitution = AlgorithmConformanceFixture(
        id: "k1-scope-binding-substitution",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K1ScopeBindingSubstitutionTLCWitness.spec }
    )
}
