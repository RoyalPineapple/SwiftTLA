import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Published three-process Boulangerie control flow with its bounded
    /// state constraint.
    public static let boulangerUpstreamPort = AlgorithmConformanceFixture(
        id: "boulanger-upstream-port",
        configuration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        specification: { K6BoulangerMCWitness.spec }
    )
}
