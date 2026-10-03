import Testing
import SwiftTLA
@testable import UpstreamParity

struct RecursiveStepTests {
    @Test("a recursive expression executes inside a generated transition")
    func computesWithinGeneratedStep() throws {
        let scenario = try #require(RecursiveStep.validationScenarios().first)
        var machine = try #require(scenario.initialMachines().first)
        #expect(machine.state.total == 0)
        #expect(try machine.send(.compute).after.total == 10)
        #expect(try machine.enabledActions().isEmpty)

        let graph = try scenario.explore(maximumStates: 3)
        #expect(graph.transitions.count == 2)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 1)
        #expect(graph.deadlockedStates == [machine.snapshot])
        let run = try NativeScenarioRun(scenario, maximumStates: 3)
        try run.validateExpectations()
    }
}
