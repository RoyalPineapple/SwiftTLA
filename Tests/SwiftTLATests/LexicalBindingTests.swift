import Testing
import SwiftTLA

struct LexicalBindingTests {
    @Test("successive saved values keep distinct identities and types after an assignment")
    func preservesSavedValues() throws {
        var machine = try SavedValuesMachine.makeMachine()
        _ = try machine.send(.save)
        #expect(machine.state.value == 9)
        #expect(machine.state.result == 123)
        #expect(machine.state.valid)
        let graph = try ReachabilityGraph(initialMachines: SavedValuesMachine.initialMachines(), maximumStates: 2)
        #expect(graph.transitions.count == 2)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.contains(machine.snapshot))
    }
}
