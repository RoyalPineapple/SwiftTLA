import Testing
import SwiftTLA
import UpstreamParity

struct VoteProofCorpusExecutionTests {
    @Test("Generated voting guards enumerate typed choices without changing disabled or ambiguous state")
    func generatedVotingChoices() throws {
        #expect(try VoteProofModel.initialMachines().count == 1)
        var native = try VoteProofModel.makeMachine()
        #expect(Set(native.state.votes.keys) == Set(VoteProofModel.Acceptor.allCases))
        #expect(native.state.votes.values.allSatisfy { $0.isEmpty })
        #expect(Set(native.state.maxBal.keys) == Set(VoteProofModel.Acceptor.allCases))
        #expect(native.state.maxBal.values.allSatisfy { $0 == -1 })
        #expect(try native.violatedInvariants(atLevel: 1).isEmpty)
        #expect(try Set(native.enabledActions()) == [
            .pcalProcess1(process: .a1), .pcalProcess1(process: .a2), .pcalProcess1(process: .a3)
        ])
        let alternatives = try native.successors().filter { $0.action == .pcalProcess1(process: .a1) }
        #expect(Set(alternatives.map { $0.machine.snapshot }).count > 1)
        #expect(alternatives.contains { $0.machine.state.maxBal[.a1] == 0 })
        #expect(alternatives.contains { $0.machine.state.maxBal[.a1] == 1 })
        #expect(alternatives.contains { $0.machine.state.maxBal[.a1] == 2 })
        #expect(alternatives.allSatisfy { $0.machine.state.maxBal[.a2] == -1
            && $0.machine.state.maxBal[.a3] == -1 })
        let before = native.snapshot
        do {
            _ = try native.send(.pcalProcess1(process: .a1))
            Issue.record("Distinct ballot or vote outcomes must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.snapshot == before)
        #expect(try native.isEnabled(.pcalProcess1(process: .a1)))
    }
}
