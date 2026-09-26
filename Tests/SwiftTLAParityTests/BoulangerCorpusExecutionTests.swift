import Testing
@testable import SwiftTLA
import UpstreamParity

struct BoulangerCorpusExecutionTests {
    @Test("configured Boulanger dispatch retains all process and ambiguous successors")
    func nativeProcessControl() throws {
        let scenario = try #require(try BoulangerModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 1)
        var machine = try #require(initial.first)
        #expect(machine.state.num == [1: 0, 2: 0, 3: 0])
        #expect(machine.state.flag == [1: false, 2: false, 3: false])
        #expect(try machine.violatedInvariants().isEmpty)
        #expect(Set(BoulangerModel.Property.allCases) == [.TypeOK, .Inv, .MutualExclusion])
        #expect(try Set(machine.enabledActions()) == [
            .ncs(process: 1), .ncs(process: 2), .ncs(process: 3)
        ])

        let successors = try machine.successors().filter { $0.action == .ncs(process: 1) }
        #expect(successors.count == 1)
        _ = try machine.send(.ncs(process: 1))
        #expect(machine.snapshot == successors.first?.machine.snapshot)
        #expect(try machine.violatedInvariants().isEmpty)
        #expect(try Set(machine.enabledActions()) == [
            .ncs(process: 2), .ncs(process: 3), .e1(process: 1)
        ])

        let choices = try machine.successors().filter { $0.action == .e1(process: 1) }
        #expect(Set(choices.map { $0.machine.snapshot }).count == 2)
        for choice in choices {
            #expect(try choice.machine.violatedInvariants().isEmpty)
        }
        let before = machine.snapshot
        do {
            _ = try machine.send(.e1(process: 1))
            Issue.record("Distinct control successors must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.snapshot == before)
        #expect(try machine.isEnabled(.e1(process: 1)))
    }
}
