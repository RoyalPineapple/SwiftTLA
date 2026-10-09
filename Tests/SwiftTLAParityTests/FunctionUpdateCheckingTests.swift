import Testing
import SwiftTLA

struct FunctionUpdateCheckingTests {
    @Test("typed function updates retain both choices and the complete labeled graph")
    func checksParameterizedUpdates() throws {
        typealias Process = FunctionUpdateMachine.Process
        typealias Phase = FunctionUpdateMachine.Phase
        typealias Action = FunctionUpdateMachine.Action
        typealias Phases = [Process: Phase]

        let initial: Phases = [.first: .initial, .second: .initial]
        let firstDone: Phases = [.first: .done, .second: .initial]
        let secondDone: Phases = [.first: .initial, .second: .done]
        let bothDone: Phases = [.first: .done, .second: .done]

        let machine = try FunctionUpdateMachine.makeMachine()
        #expect(machine.state.phases == initial)
        #expect(try machine.successors(for: .advance(process: .first)).map(\.state.phases) == [firstDone])
        #expect(try machine.successors(for: .advance(process: .second)).map(\.state.phases) == [secondDone])

        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        let states = graph.transitions.keys.map(\.state.phases)
        #expect(states.count == 4)
        for expected in [initial, firstDone, secondDone, bothDone] {
            #expect(states.contains(expected))
        }
        let expectedEdges: [(Phases, Action, Phases)] = [
            (initial, .advance(process: .first), firstDone),
            (initial, .advance(process: .second), secondDone),
            (firstDone, .advance(process: .second), bothDone),
            (secondDone, .advance(process: .first), bothDone)
        ]
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == expectedEdges.count)
        for (source, action, target) in expectedEdges {
            let outgoing = try #require(graph.transitions.first { $0.key.state.phases == source }?.value)
            #expect(outgoing.contains { $0.action == action && $0.target.state.phases == target })
        }
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.phases == bothDone)
        #expect(graph.safetyViolations.first?.value == [.deadlock])
    }
}
