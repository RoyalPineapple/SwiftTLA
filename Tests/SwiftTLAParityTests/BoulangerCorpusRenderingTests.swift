import Testing
@testable import UpstreamParity

struct BoulangerCorpusRenderingTests {
    @Test("Boulanger preserves its Algorithm source through parser and builder")
    func parserBuilderFidelity() throws {

        let scenarios = try BoulangerModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["MCBoulanger"])
        let scenario = try #require(scenarios.first)
        #expect(scenario.configuration.N == 3)
        #expect(scenario.configuration.MaxNat == 3)
        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == ["TypeOK", "Inv", "MutualExclusion"])
        #expect(rendered.checksDeadlock)
        let module = try rendered.plusCalBundle().root.tla
        #expect(module.contains("fair process"))
        #expect(module.contains("StateConstraint =="))
        #expect(module.contains("MutualExclusion =="))
        #expect(module.contains("w2"))
        #expect(module.contains("ncs:-"))
        #expect(module.contains("TypeOK =="))
        #expect(module.contains("Inv =="))
        #expect(!module.contains("LocalTypeOK"))
    }
}
