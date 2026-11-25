import SwiftTLA
import Testing
import UpstreamParity

struct AtomicCommitCorpusFairnessTests {
    @Test("non-blocking progress can use either peer but must belong to the same participant")
    func participantFairness() throws {
        let scenario = try #require(NonBlockingAtomicCommitModel.validationScenarios().first)
        let machine = try #require(scenario.initialMachines().first)
        let conditions = try machine.fairnessConditions()
        #expect(conditions.count == 3)
        let matching = conditions.filter { $0.matches(.sendVote(member: .p0)) }
        #expect(matching.count == 1)
        let progress = try #require(matching.first)
        #expect(!progress.isStrong)
        #expect(progress.matches(.forward(sender: .p0, receiver: .p0)))
        #expect(progress.matches(.forward(sender: .p0, receiver: .p1)))
        #expect(progress.matches(.preDecideOnForward(receiver: .p0, sender: .p1)))
        #expect(!progress.matches(.forward(sender: .p1, receiver: .p0)))
        #expect(!progress.matches(.preDecideOnForward(receiver: .p1, sender: .p0)))
        #expect(!progress.matches(.parDie(member: .p0)))
    }
}
