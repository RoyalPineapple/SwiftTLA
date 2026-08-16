import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Published Boulangerie control flow in the upstream source's recorded
    /// two-process, `MaxNat = 3` small-model-checking instance.
    public static let boulangerUpstreamPort = AlgorithmConformanceFixture(
        id: "boulanger-upstream-port",
        swiftConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        specification: { K6BoulangerMCWitness.spec }
    )
}
