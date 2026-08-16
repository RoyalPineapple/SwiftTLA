import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K2 admits only process/formal-lambda binding evidence.
    public static let k2ScopedFormalLambda = AlgorithmConformanceFixture(
        id: "k2-scoped-formal-lambda",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K2ScopedFormalLambdaTLCWitness.spec }
    )
}
