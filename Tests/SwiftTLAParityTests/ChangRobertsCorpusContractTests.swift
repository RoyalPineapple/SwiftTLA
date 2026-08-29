import Testing
@testable import SwiftTLA
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

    @Test("Compiled liveness property is satisfied for the canonical N=3 model")
    func compiledLivenessPropertyIsSatisfied() throws {
        let compilation = try Example.changRobertsN3.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: 500,
                symmetryReduction: .disabled
            )
        ).explore()
        let checker = LivenessChecker(
            compilation: compilation,
            graph: exploration.graph,
            states: exploration.compiledStates
        )
        #expect(compilation.description.temporalProperties == ["Liveness"])
        let property = try #require(
            checker.analyze(initialStateIDs: exploration.initialStateIDs).first
        )
        #expect(property.status == .satisfied)
    }
}
