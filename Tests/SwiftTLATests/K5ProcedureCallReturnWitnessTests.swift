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
        let fixture = AlgorithmConformanceRegistry.procedureCallReturn
        let source = try fixture.plusCalModule()

        #expect(source.contains("procedure addOffset"))
        #expect(source.contains("return;"))
        #expect(source.contains("call addOffset(5);"))
        #expect(fixture.swiftConfiguration.contains("SPECIFICATION Spec"))
        #expect(!fixture.swiftConfiguration.contains("defaultInitValue"))
        #expect(fixture.plusCalConfiguration.contains("CONSTANT defaultInitValue = 0"))
    }

    @Test("K5 TLA export gives procedure actions legal operator names")
    func tlaModuleSanitizesProcedureActionOperator() {
        let source = K5ProcedureCallReturnWitness.spec.tlaModule

        #expect(source.contains("procedure_addOffset_apply =="))
        #expect(!source.contains("procedure.addOffset.apply =="))
    }
}
