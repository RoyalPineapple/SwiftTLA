import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Process/formal-lambda binding evidence.
    public static let formalOperatorValues = AlgorithmConformanceFixture(
        id: "formal-operator-values",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K2ScopedFormalLambdaTLCWitness.spec }
    )
}
