@testable import AlgorithmConformance
import Testing

struct K5ProcedureCallReturnWitnessTests {
    @Test("K5 procedure fixture retains typed generated surface and parser fidelity")
    func generatedProcedureCallReturnSurface() throws {
        K5ProcedureCallReturnWitness._checkParserTree()

        var model = K5ProcedureCallReturnWitness()
        let call = try model.apply(.start)
        #expect(call.after.output == 0)

        let apply = try model.apply(.procedure_addOffset_apply)
        #expect(apply.after.output == 7)
        #expect(K5ProcedureCallReturnWitness.spec.algorithmFidelityTokens.count == 1)
    }

    @Test("K5 fixture exposes one authored PlusCal procedure module")
    func exposesProcedureOracleFixture() throws {
        let fixture = AlgorithmConformanceRegistry.k5ProcedureCallReturn
        let source = try fixture.plusCalModule()

        #expect(source.contains("procedure addOffset"))
        #expect(source.contains("return;"))
        #expect(source.contains("call addOffset(5);"))
    }
}
