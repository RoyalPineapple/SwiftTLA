import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite(.serialized)
struct DiningPhilosophersCorpusStateGraphTests {
    @Test("PlusCal-shaped Dining Philosophers preserves the TLC N=5 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {

        let entry = Example.diningPhilosophersNP5
        let graph = try ModelChecker(
            spec: entry.spec,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: entry.maximumStateLimit
            )
        ).exploreGraph()

        #expect(graph.states.count == entry.expectedDistinct)
    }
}
