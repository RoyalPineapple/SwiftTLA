import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite(.serialized)
struct DiningPhilosophersCorpusStateGraphTests {
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
