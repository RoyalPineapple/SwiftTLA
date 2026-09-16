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

    @Test("PlusCal-shaped Dining Philosophers preserves the TLC N=5 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {

        let fixture = Example.diningPhilosophersNP5
        let compilation = try fixture.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: fixture.maximumStateLimit,
                symmetryReduction: .disabled
            )
        ).explore()

        #expect(exploration.graph.states.count == fixture.expectedDistinct)
    }
}
