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

    @Test("K5 TLA export matches official PlusCal procedure administration")
    func tlaModuleUsesOfficialProcedureAdministration() {
        let source = K5ProcedureCallReturnWitness.spec.tlaModule

        // The generated Swift surface keeps its qualified action label, while
        // the exported TLA+ matches the official translator's global label
        // and procedure-frame representation for differential TLC evidence.
        #expect(source.contains("VARIABLES output, parameter0, offset, pc, stack"))
        #expect(source.contains("apply =="))
        #expect(source.contains("pc = \"apply\""))
        #expect(source.contains("procedure |-> \"addOffset\""))
        #expect(source.contains("pc |-> \"done\""))
        #expect(!source.contains("__pcal_stack"))
        #expect(!source.contains("procedure.addOffset.apply"))
        #expect(!source.contains("returnPC"))
    }
}
