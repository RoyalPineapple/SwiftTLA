import Testing
@testable import UpstreamParity

struct BakeryCorpusConfigurationTests {
    @Test("MCBakery is available to independent native validation")
    func nativePipelineSelectsPublishedConfiguration() throws {
        #expect(try modelValidationScenarios().contains {
            $0.id == "bakery-0" && $0.scenario.name == "MCBakery"
        })
    }

    @Test("MCBakery enumerates the pinned ISpec initial-state population")
    func publishedInitialPopulation() throws {
        let scenario = try #require(BakeryModel.validationScenarios().first)
        #expect(try scenario.initialMachines().count == 655_200)
    }

    @Test("MCBakery selects invariant-defined initial states and its published checks")
    func publishedConfiguration() throws {
        let scenario = try #require(BakeryModel.validationScenarios().first)
        #expect(scenario.name == "MCBakery")
        #expect(scenario.configuration.N == 2)
        #expect(scenario.configuration.MaxNat == 2)

        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == ["MutualExclusion", "TypeOK", "Inv"])
        #expect(!rendered.checksDeadlock)
        let configuration = try #require(rendered.tlaBundle.root.cfg)
        #expect(configuration.contains("INIT Init\nNEXT Next\nCHECK_DEADLOCK FALSE"))
        #expect(!configuration.contains("PROPERTY"))
        #expect(rendered.tlaBundle.root.tla.contains("/\\ Inv"))
    }
}
