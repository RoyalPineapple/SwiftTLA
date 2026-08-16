import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K6 preserves the published three-process Boulangerie source and its
    /// MCBoulanger bounds in the dedicated Algorithm conformance corpus.
    public static let k6BoulangerMC = AlgorithmConformanceFixture(
        id: "k6-boulanger-mc",
        configuration: "CONSTANT N = 3\nCONSTANT MaxNat = 3\nCONSTANT Nat <- NatOverride\nSPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        specification: { K6BoulangerMCWitness.spec }
    )
}
