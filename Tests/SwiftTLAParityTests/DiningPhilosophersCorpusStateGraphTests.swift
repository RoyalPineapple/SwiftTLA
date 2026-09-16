import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite(.serialized)
struct DiningPhilosophersCorpusStateGraphTests {
    @Test("native Dining Philosophers checks every upstream NP=5 claim with explicit fairness")
    func checksNativeClaims() throws {
        let scenario = try #require(DiningPhilosophersModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 50_000)
        #expect(graph.transitions.count == 67)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.deadlockedStates.isEmpty)
        #expect(graph.temporalResults["NobodyStarves"]?.status == .satisfied)
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.cfg.contains("NobodyStarves"))
        #expect(rendered.tlaBundle.tla.contains("WF_<<pc, forks, hungry>>"))
        #expect(try rendered.plusCalBundle().tla.contains("fair process"))
    }

    @Test("every Dining Philosophers graph edge replays through application dispatch")
    func dispatchMatchesCompleteGraph() throws {
        let scenario = try #require(DiningPhilosophersModel.validationScenarios().first)
        let initialMachines = try scenario.initialMachines()
        try #require(initialMachines.count == 1)
        let initial = try #require(initialMachines.first)
        let graph = try scenario.explore(maximumStates: 67)
        #expect(graph.initialStates == [initial.snapshot])
        for (source, edges) in graph.transitions {
            var machine = initial
            for step in try graph.trace(to: source).dropFirst() {
                _ = try machine.send(#require(step.action))
                #expect(machine.snapshot == step.state)
            }
            #expect(machine.snapshot == source)
            #expect(try Set(machine.enabledActions()) == Set(edges.map(\.action)))
            for edge in edges {
                var successor = machine
                _ = try successor.send(edge.action)
                #expect(successor.snapshot == edge.target)
            }
        }
        #expect(throws: ExplorationError.stateLimitExceeded(66)) {
            try scenario.explore(maximumStates: 66)
        }
    }
}
