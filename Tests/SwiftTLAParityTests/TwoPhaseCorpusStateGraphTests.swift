import Testing
import SwiftTLA
@testable import UpstreamParity

struct TwoPhaseCorpusStateGraphTests {
    @Test("TwoPhase's configured machine alternates both steps and retains its invariant")
    func configuredHandshake() throws {
        let scenario = try #require(TwoPhaseModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 1)
        var machine = try #require(initial.first)
        let start = machine.state
        #expect(start.p == 0 && start.c == 0 && start.x == 0)
        #expect(try machine.enabledActions() == [.ProducerStep])
        try machine.send(.ProducerStep)
        #expect(machine.state.p == 1)
        #expect(try machine.enabledActions() == [.ConsumerStep])
        try machine.send(.ConsumerStep)
        #expect(machine.state.c == 1)
        try machine.send(.ProducerStep)
        #expect(machine.state.p == 0)
        try machine.send(.ConsumerStep)
        #expect(machine.state == start)

        let run = try NativeScenarioRun(scenario, maximumStates: 1000)
        try run.validateExpectations()
        #expect(run.native.graph?.isComparable == true)
        #expect(run.native.checks.properties == ["Inv": .satisfied])
        #expect(run.native.checks.deadlock == .satisfied)
    }
}
