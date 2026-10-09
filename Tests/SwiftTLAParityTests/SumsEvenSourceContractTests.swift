import Foundation
import Testing
@testable import UpstreamParity

struct SumsEvenSourceContractTests {
    @Test("the published million-value assumption has no state-machine graph")
    func checksFullPublishedDomain() throws {
        let scenarios = try SumsEvenModel.validationScenarios()
        #expect(scenarios.count == 1)
        let scenario = try #require(scenarios.first)
        #expect(scenario.name == "MC_sums_even")
        #expect(scenario.configuration.MaxNat == 1_000_000)
        let evaluation = try scenario.evaluateAssumptions()
        #expect(evaluation.satisfied)
        #expect(evaluation.evaluatedValues.isEmpty)
        let rendered = try scenario.render()
        #expect(rendered.isAssumptionsOnly)
        #expect(!rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg == "CONSTANT MaxNat = 1000000\n")
        #expect(rendered.tlaBundle.tla.contains("ASSUME"))
        #expect(!rendered.tlaBundle.tla.contains("VARIABLES"))
        #expect(!rendered.tlaBundle.tla.contains("Init =="))
        #expect(!rendered.tlaBundle.tla.contains("Next =="))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "sums-even-0" })
        #expect(declaration.comparisonMode == .assumptionsOnly)
        #expect(declaration.assumptionExpectation == .satisfied)
        #expect(try declaration.resolveAssumptionScenario()?.name == scenario.name)
        let fixtures = root.appendingPathComponent("Verification/FiniteGraph/fixtures")
        let module = try Data(contentsOf: fixtures.appendingPathComponent(declaration.module))
        let configuration = try Data(contentsOf: fixtures.appendingPathComponent(declaration.configuration))
        #expect(SHA256.hex(module) == declaration.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
    }
}
