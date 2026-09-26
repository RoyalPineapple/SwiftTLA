import Testing
import SwiftTLA
import UpstreamParity

struct SumSequenceSourceContractTests {
    @Test("Unbounded source model accepts selected sequences without fixture limits")
    func selectedInputsPreserveClaims() throws {
        let configuration = try SumSequenceModel.Configuration(Values: [-2, 1])
        for input in [[], [1, -2, 1], [-2, -2, 1]] {
            var machine = try SumSequenceModel.makeMachine(
                .init(seq: input, sum: 0, n: 1), configuration: configuration)
            #expect(try machine.violatedInvariants().isEmpty)
            for _ in 0...input.count {
                _ = try machine.send(.a)
                #expect(try machine.violatedInvariants().isEmpty)
            }
            #expect(machine.state.seq == input)
            #expect(machine.state.sum == input.reduce(0, +))
            #expect(machine.state.n == input.count + 1)
        }
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try SumSequenceModel.makeMachine(
                .init(seq: [3], sum: 0, n: 1), configuration: configuration)
        }
    }

    @Test("Source claims and unbounded parameter domain survive formal export")
    func exportsSourceClaims() throws {
        let configuration = try SumSequenceModel.Configuration(Values: [-2, 1])
        let bundle = try SumSequenceModel.render(configuration: configuration).tlaBundle
        #expect(bundle.tla.contains("Values \\in SUBSET Int"))
        #expect(bundle.tla.contains("Seq(Values)"))
        #expect(bundle.tla.contains("SubSeq("))
        #expect(bundle.tla.contains("RECURSIVE "))
        #expect(bundle.tla.contains("current \\in Seq(Int)"))
        #expect(bundle.tla.contains("Head(current)"))
        #expect(bundle.tla.contains("Tail(current)"))
        for property in ["TypeOK", "Inv", "PCorrect", "Termination"] {
            #expect(bundle.tla.contains(property))
        }
    }
}
