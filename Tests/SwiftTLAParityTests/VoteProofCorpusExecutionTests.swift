import Testing
@testable import SwiftTLA
import UpstreamParity

struct VoteProofCorpusExecutionTests {
    @Test("Native voting guards, invariants and ambiguity agree with the formal corpus")
    func nativeVotingRelation() throws {
        let compilation = try VoteProofModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        #expect(initialStates.count == 1)
        let initial = try #require(initialStates.first)
        var native = try VoteProofModel.makeMachine()
        let votes = try #require(compilation.layout.testVariableID(named: "votes"))
        let maxBal = try #require(compilation.layout.testVariableID(named: "maxBal"))
        let voteAction = try #require(compilation.layout.testActionID(named: "pcalProcess1"))
        let formalVotes = CompiledValue.function(Dictionary(uniqueKeysWithValues:
            native.state.votes.map { acceptor, votes in
                (CompiledValue(formal: acceptor.tlaValue), .set(Set(votes.map { vote in
                    .tuple([.integer(vote.first), CompiledValue(formal: vote.second.tlaValue)])
                })))
            }
        ))
        let formalBallots = CompiledValue.function(Dictionary(uniqueKeysWithValues:
            native.state.maxBal.map { (CompiledValue(formal: $0.key.tlaValue), .integer($0.value)) }
        ))
        #expect(try initial.value(for: votes) == formalVotes)
        #expect(try initial.value(for: maxBal) == formalBallots)
        let violations = try compilation.semantics.behavior.invariants.filter {
            try !runtime.invariantHolds($0, in: initial)
        }.map(\.name)
        #expect(violations.isEmpty)
        #expect(try native.violatedInvariants() == violations)
        #expect(try Set(native.enabledActions()) == [
            .pcalProcess1(process: .a1), .pcalProcess1(process: .a2), .pcalProcess1(process: .a3)
        ])
        let alternatives = try runtime.successors(for: voteAction, from: initial).filter {
            $0.arguments == [CompiledValue(formal: VoteProofModel.Acceptor.a1.tlaValue)]
        }
        #expect(Set(alternatives.map(\.state)).count > 1)
        let before = native.state
        do {
            _ = try native.send(.pcalProcess1(process: .a1))
            Issue.record("Distinct ballot or vote outcomes must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.state == before)
        #expect(try native.isEnabled(.pcalProcess1(process: .a1)))
    }
}
