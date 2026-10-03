import Testing
import SwiftTLA
@testable import UpstreamParity

struct PrisonersCorpusStateGraphTests {
    @Test("the configured puzzle preserves four initial states, its complete graph, and every selected check")
    func configuredPuzzle() throws {
        let scenario = try #require(PrisonersModel.validationScenarios().first)
        #expect(scenario.name == "Prisoners")
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == 4)
        #expect(graph.states.count == 214)
        #expect(graph.edges.count == 856)
        #expect(run.native.checks.properties == [
            "TypeOK": .satisfied,
            "CountInvariant": .satisfied,
            "Safety": .satisfied,
            "Liveness": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("(\\A prisoner \\in"))
        #expect(rendered.tlaBundle.tla.contains(": WF_"))
        #expect(rendered.checkNames == ["TypeOK", "CountInvariant", "Safety", "Liveness"])
    }

}
