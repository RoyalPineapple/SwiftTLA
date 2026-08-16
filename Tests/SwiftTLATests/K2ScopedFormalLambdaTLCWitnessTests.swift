@testable import AlgorithmConformance
import Testing

struct K2ScopedFormalLambdaTLCWitnessTests {
    @Test("K2 scoped formal-lambda witness retains process and lambda bindings")
    func generatedRuntimeUsesProcessScopedFormalLambda() throws {
        K2ScopedFormalLambdaTLCWitness._checkParserTree()

        var model = K2ScopedFormalLambdaTLCWitness()
        let result = try model.apply(.advance(process: .left))

        #expect(result.before.counters[.left] == 0)
        #expect(result.after.counters[.left] == 1)
        #expect(result.after.counters[.right] == 0)
    }

    @Test("K2 fixture exposes one PlusCal source with the formal application")
    func exposesScopedFormalLambdaPlusCalSource() throws {
        let fixture = AlgorithmConformanceRegistry.formalOperatorValues
        let source = try fixture.plusCalModule()

        #expect(source.contains("process (self \\in {\"left\", \"right\"})"))
        #expect(source.contains("LAMBDA value : (value + 1)"))
        #expect(fixture.configuration.contains("SPECIFICATION Spec"))
    }

    @Test("K2 TLA export beta-reduces anonymous formal-lambda application")
    func tlaModuleUsesLegalOperatorApplication() {
        let source = K2ScopedFormalLambdaTLCWitness.spec.tlaModule

        #expect(!source.contains("(LAMBDA"))
        #expect(source.contains("(counters[process] + 1)"))
    }
}
