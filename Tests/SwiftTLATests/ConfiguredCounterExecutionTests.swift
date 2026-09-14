import Testing
@testable import SwiftTLA

struct ConfiguredCounterExecutionTests {
    @Test("configurations share generated types and preserve ordered execution")
    func executesConfigurations() throws {
        for limit in [2, 4] {
            let configuration = try ConfiguredCounter.Configuration(limit: limit, stopAtLimit: true)
            var machine = try ConfiguredCounter.makeMachine(configuration: configuration)
            for value in 1...limit {
                _ = try machine.send(.advance)
                #expect(machine.state.value == value)
                #expect(machine.state.previous == value - 1)
                #expect(machine.state.copied == value)
            }
            #expect(try !machine.isEnabled(.advance))
            #expect(machine.configuration == configuration)
            let graph = try ReachabilityGraph(initialMachines: ConfiguredCounter.initialMachines(configuration: configuration), maximumStates: 10)
            #expect(graph.safetyViolations.isEmpty)
            #expect(graph.transitions.count == limit + 1)
        }
    }

    @Test("an unfinished bounded counter reports deadlock without truncating exploration")
    func retainsDeadlock() throws {
        let configuration = try ConfiguredCounter.Configuration(limit: 3, stopAtLimit: false)
        let graph = try ReachabilityGraph(initialMachines: ConfiguredCounter.initialMachines(configuration: configuration), maximumStates: 10)
        #expect(graph.transitions.count == 4)
        #expect(graph.safetyViolations.count == 1)
        let state = try #require(graph.safetyViolations.keys.first)
        #expect(state.state.value == 3)
        #expect(graph.safetyViolations[state] == [.deadlock])
        #expect(try graph.trace(to: state).count == 4)
    }

    @Test("configuration domains reject invalid values and exploration rejects mixed configurations")
    func rejectsInvalidConfigurations() throws {
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try ConfiguredCounter.Configuration(limit: 101, stopAtLimit: true)
        }
        let two = try ConfiguredCounter.Configuration(limit: 2, stopAtLimit: true)
        let four = try ConfiguredCounter.Configuration(limit: 4, stopAtLimit: true)
        let machines = try ConfiguredCounter.initialMachines(configuration: two) + ConfiguredCounter.initialMachines(configuration: four)
        #expect(throws: ExplorationError.configurationMismatch) {
            try ReachabilityGraph(initialMachines: machines, maximumStates: 10)
        }
    }
}
