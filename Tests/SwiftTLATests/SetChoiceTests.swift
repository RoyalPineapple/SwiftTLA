import Testing
@testable import SwiftTLA

struct SetChoiceTests {
    @Test("configured Swift sets retain nondeterministic choices under one action label")
    func completeGraphs() throws {
        for scenario in try SetChoiceMachine.validationScenarios() {
            let members = scenario.configuration.members
            let graph = try scenario.explore(maximumStates: 10)
            #expect(graph.initialStates.count == 1)
            #expect(graph.transitions.count == members.count + 1)
            #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == (members.count + 1) * members.count)
            #expect(graph.deadlockedStates.count == (members.isEmpty ? 1 : 0))
            for edges in graph.transitions.values {
                #expect(Set(edges.map { $0.target.state.selected }) == members)
                #expect(edges.allSatisfy { $0.action == .pick })
            }
            var machine = try #require(scenario.initialMachines().first)
            let before = machine.snapshot
            if members.count == 1 {
                _ = try machine.send(.pick)
                #expect(machine.state.selected == 1)
            } else {
                #expect(throws: GeneratedMachineError.self) { try machine.send(.pick) }
                #expect(machine.snapshot == before)
            }
            let rendered = try scenario.render()
            #expect(rendered.tlaBundle.tla.contains("\\in members"))
            #expect(!rendered.tlaBundle.tla.contains("VARIABLES pc"))
        }
    }
}
