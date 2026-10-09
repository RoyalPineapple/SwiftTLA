import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct DieHardCorpusStateGraphTests {
    @Test("DieHard stops at the upstream expected violation and retains an independently checked complete graph")
    func preservesUpstreamChecks() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "die-hard" })
        #expect(declaration.sourceModel.rawValue == "die-hard")
        #expect(try declaration.resolveScenario()?.name == "Upstream")
        let reference = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/die-hard/DieHard.cfg"))
        #expect(SHA256.hex(reference) == declaration.cfgSHA256)
        #expect(String(decoding: reference, as: UTF8.self) == "SPECIFICATION Spec\nINVARIANTS TypeOK NotSolved\n")
        let scenarios = try DieHardModel.validationScenarios()
        #expect(scenarios.count == 1)
        let scenario = try #require(scenarios.first)
        let run = try NativeScenarioRun(scenario, maximumStates: 100)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let exhaustive = try NativeModelRun(scenario.explore(maximumStates: 100), rendered: scenario.render())
        #expect(exhaustive.graph.graph.states.count == 16)
        #expect(exhaustive.graph.graph.edges.count == 96)
        #expect(exhaustive.checks.properties["TypeOK"] == .satisfied)
        #expect(exhaustive.checks.deadlock == .satisfied)
        #expect(run.native.graph == nil)
        #expect(run.native.checks.properties["TypeOK"] == .unavailable)
        #expect(run.native.checks.deadlock == .unavailable)
        guard case .violated(let trace) = run.native.checks.properties["NotSolved"] else {
            Issue.record("Expected the upstream NotSolved counterexample")
            return
        }
        try trace.validate(in: exhaustive.graph.graph)
        #expect(trace.cycleStartIndex == nil)
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.cfg.contains("INVARIANT TypeOK"))
        #expect(bundle.cfg.contains("INVARIANT NotSolved"))
        #expect(!bundle.tla.contains("VARIABLES pc"))
    }
}
