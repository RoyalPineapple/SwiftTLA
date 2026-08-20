import Testing
import SwiftTLA
import UpstreamParity

@Suite(.serialized)
struct ChangRobertsCorpusContractTests {
    @Test("PlusCal-shaped Chang–Roberts retains the upstream N=3 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {
        let entry = Example.changRobertsN3
        try ChangRobertsModel.verifySpec()
        #expect(entry.spec.temporalProperties.map(\.name) == ["Liveness"])
        let states = try ModelChecker(spec: entry.spec, maxStates: 50_000).exploreGraph().states
        #expect(states.count == entry.expectedDistinct)
    }

}
