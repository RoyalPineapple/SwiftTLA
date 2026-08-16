import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K6 preserves the published three-process Boulangerie control flow and
    /// its bounded state constraint in the dedicated Algorithm corpus.
    public static let k6BoulangerMC = AlgorithmConformanceFixture(
        id: "k6-boulanger-mc",
        configuration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        specification: { K6BoulangerMCWitness.spec }
    )
}
