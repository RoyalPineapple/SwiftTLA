import Testing
import SwiftTLA
import UpstreamParity

@Suite(.serialized)
struct ChangRobertsMigrationTests {
    @Test("PlusCal-shaped Chang–Roberts retains the upstream N=3 state count")
    func generatedAlgorithmMatchesUpstreamStateCount() throws {
        let entry = Example.changRobertsN3
        try ChangRobertsModel.verifySpec()
        #expect(entry.spec.temporalProperties.map(\.name) == ["Liveness"])
        let states = try ModelChecker(spec: entry.spec, maxStates: 50_000).exploreGraph().states
        #expect(states.count == entry.expectedDistinct)
    }

    @Test("Generated labels preserve an integer-backed process identifier")
    func integerBackedProcessIdentifierRoundTripsThroughActionLabel() {
        let label = ChangRobertsModel.ActionLabel.n0(process: .one)

        #expect(label.toInvocation() == .init(name: "n0", arguments: [.int(1)]))
        #expect(ChangRobertsModel.ActionLabel(invocation: label.toInvocation()) == label)
    }
}
