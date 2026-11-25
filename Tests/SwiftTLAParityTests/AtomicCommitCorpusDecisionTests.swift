import Testing
import UpstreamParity

struct AtomicCommitCorpusDecisionTests {
    @Test("the published failure trace needs a decision before forwarding")
    func earlyDecisionSplitsParticipants() throws {
        let scenarios = try NonBlockingAtomicCommitModel.validationScenarios()
        for name in ["twoParticipants", "earlyDecision"] {
            let scenario = try #require(scenarios.first { $0.name == name })
            var machine = try #require(scenario.initialMachines().first {
                $0.state.participant[.p0]?.vote == .yes && $0.state.participant[.p1]?.vote == .yes
            })
            let prefix: [NonBlockingAtomicCommitModel.Action] = [
                .request(member: .p0), .sendVote(member: .p0), .request(member: .p1), .sendVote(member: .p1),
                .getVote(member: .p0), .getVote(member: .p1), .makeDecision, .coordBroadcast(member: .p0),
            ]
            for action in prefix { _ = try machine.send(action) }
            if name == "twoParticipants" {
                #expect(try !machine.isEnabled(.decide(member: .p0)))
                _ = try machine.send(.preDecide(member: .p0))
                #expect(machine.state.participant[.p0]?.decision == .undecided)
            } else {
                _ = try machine.send(.decide(member: .p0))
                _ = try machine.send(.parDie(member: .p0))
                _ = try machine.send(.coordDie)
                _ = try machine.send(.abortOnTimeout(member: .p1))
                #expect(machine.state.participant[.p0]?.decision == .commit)
                #expect(machine.state.participant[.p1]?.decision == .abort)
            }
        }
    }
}
