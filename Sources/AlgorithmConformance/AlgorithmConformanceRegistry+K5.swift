import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Procedure/call/return lowering evidence, separate from the
    /// structured-update fixture.
    public static let procedureCallReturn = AlgorithmConformanceFixture(
        id: "procedure-call-return",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        plusCalConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nCONSTANT defaultInitValue = 0\n",
        specification: { K5ProcedureCallReturnWitness.spec }
    )
}
