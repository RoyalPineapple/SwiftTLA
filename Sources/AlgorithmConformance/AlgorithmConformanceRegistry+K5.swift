import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K5 is intentionally separate from K4's structured-update fixture: it
    /// admits only procedure/call/return lowering evidence.
    public static let k5ProcedureCallReturn = AlgorithmConformanceFixture(
        id: "k5-procedure-call-return",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K5ProcedureCallReturnWitness.spec }
    )
}
