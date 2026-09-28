import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Stones corpus assumption")
struct StonesSourceContractTests {
    @Test("the published configuration prints the complete ordered solution")
    func publishedSolution() throws {
        let scenario = try #require(StonesModel.validationScenarios().first)
        #expect(scenario.configuration.W == 40)
        #expect(scenario.configuration.N == 4)
        let result = try scenario.evaluateAssumptions()
        #expect(result.satisfied)
        #expect(result.evaluatedValues == [
            .tuple([.int(1), .int(3), .int(9), .int(27)])
        ])
        let rendered = try scenario.render()
        #expect(rendered.isAssumptionsOnly)
        #expect(!rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("W = 40"))
        #expect(rendered.tlaBundle.cfg.contains("N = 4"))
    }

    @Test("the configured assumption is pinned to the published upstream files")
    func pinnedConfiguration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "stones-0" })
        #expect(declaration.comparisonMode == .assumptionsOnly)
        #expect(declaration.assumptionExpectation == .satisfied)
        #expect(try declaration.resolveAssumptionScenario()?.name == "Stones")
        let fixtures = root.appendingPathComponent("Verification/FiniteGraph/fixtures")
        let module = try Data(contentsOf: fixtures.appendingPathComponent(declaration.module))
        let configuration = try Data(contentsOf: fixtures.appendingPathComponent(declaration.configuration))
        #expect(SHA256.hex(module) == declaration.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
        #expect(declaration.sourceInput?.sha256 == declaration.moduleSHA256)
    }
}
