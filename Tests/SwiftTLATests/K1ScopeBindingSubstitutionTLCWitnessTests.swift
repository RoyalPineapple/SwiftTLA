@testable import AlgorithmConformance
import Testing

struct K1ScopeBindingSubstitutionTLCWitnessTests {
    @Test("K1 preserves canonical binding scopes in the generated typed action")
    func generatedRuntimeAppliesBoundMacroArgument() throws {
        K1ScopeBindingSubstitutionTLCWitness._checkParserTree()

        var model = K1ScopeBindingSubstitutionTLCWitness()
        let result = try model.apply(.bind)

        #expect(result.before.total == 0)
        #expect(result.after.total == 6)
        #expect(model.state == result.after)
    }

    @Test("K1 fixture exposes authored PlusCal bindings after macro substitution")
    func exposesScopeBindingSubstitutionPlusCalSource() throws {
        let fixture = try #require(AlgorithmConformanceRegistry.fixture(id: "scope-binding-substitution"))
        let source = try fixture.plusCalModule()

        #expect(source.contains("(*--algorithm K1ScopeBindingSubstitutionTLCWitness"))
        #expect(source.contains("with (") && source.contains(" = 1)"))
        #expect(source.contains("\\in {2}"))
        #expect(source.contains("\\in {3}"))
        #expect(!source.contains("__pcal_macro_parameter"))
        #expect(fixture.swiftConfiguration.contains("SPECIFICATION Spec"))
    }
}
