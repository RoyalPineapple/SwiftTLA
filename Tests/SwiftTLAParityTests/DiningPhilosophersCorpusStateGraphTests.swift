import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite(.serialized)
struct DiningPhilosophersCorpusStateGraphTests {
    @Test("PlusCal-shaped Dining Philosophers preserves the TLC N=5 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {

        let entry = Example.diningPhilosophersNP5
        let compilation = try entry.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: entry.maximumStateLimit
            )
        ).explore()

        #expect(exploration.graph.states.count == entry.expectedDistinct)
    }
}
