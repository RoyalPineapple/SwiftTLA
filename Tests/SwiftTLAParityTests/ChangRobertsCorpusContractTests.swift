import Testing
import SwiftTLA
import UpstreamParity

@Suite(.serialized)
struct ChangRobertsCorpusContractTests {
    @Test("PlusCal-shaped Chang–Roberts retains the upstream N=3 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {
        let fixture = Example.changRobertsN3
        let compilation = try fixture.spec.compile()
        #expect(compilation.description.temporalProperties == ["Liveness"])
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000, symmetryReduction: .disabled)
        ).explore()
        let states = exploration.graph.states
        #expect(states.count == fixture.expectedDistinct)
    }

}
