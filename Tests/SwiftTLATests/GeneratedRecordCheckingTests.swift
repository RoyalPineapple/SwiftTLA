import Testing
import SwiftTLA

struct GeneratedRecordCheckingTests {
    @Test("complete record-state checking replays through generated application transitions")
    func replaysCompleteGraph() throws {
        let machines = try GeneratedSwiftRecord.initialMachines()
        let initial = try #require(machines.first)
        #expect(machines.count == 1)
        let graph = try ReachabilityGraph(initialMachines: machines, maximumStates: 2)
        #expect(graph.initialStates == [initial.snapshot])
        #expect(graph.transitions.count == 2)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.deadlockedStates.isEmpty)

        for (source, edges) in graph.transitions {
            var machine = initial
            for step in try graph.trace(to: source).dropFirst() {
                _ = try machine.send(#require(step.action))
                #expect(machine.snapshot == step.state)
            }
            #expect(machine.snapshot == source)
            #expect(try Set(machine.enabledActions()) == Set(edges.map(\.action)))
            for edge in edges {
                var successor = machine
                _ = try successor.send(edge.action)
                #expect(successor.snapshot == edge.target)
            }
        }

        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try ReachabilityGraph(initialMachines: machines, maximumStates: 1)
        }
    }
}
