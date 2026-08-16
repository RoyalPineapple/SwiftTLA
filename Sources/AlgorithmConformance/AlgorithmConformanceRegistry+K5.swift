import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Procedure/call/return lowering evidence, separate from the
    /// structured-update fixture.
    public static let procedureCallReturn = AlgorithmConformanceFixture(
        id: "procedure-call-return",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K5ProcedureCallReturnWitness.spec }
    )
}
