import Testing
import SwiftTLA

struct GuardedStepExecutionTests {
    @Test("Whole-step guards precede body evaluation and preserve every enabled branch", arguments: [0, 1])
    func guardsAlgorithmExecution(ready: Int) throws {
        var machine = try GuardedAlgorithm.makeMachine(.init(ready: ready, value: 0))
        let initial = machine.snapshot
        let successors = try machine.successors(for: .choose)
        #expect(try machine.isEnabled(.choose) == (ready == 1))
        #expect(Set(successors.map { $0.state.value }) == (ready == 1 ? [1, 2] : []))
        #expect(throws: ready == 1 ? GeneratedMachineError.ambiguousAction : .noMatchingSuccessor) {
            try machine.send(.choose)
        }
        #expect(machine.snapshot == initial)

        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 5)
        #expect(Set(graph.transitions[initial, default: []].map(\.target)) == Set(successors.map(\.snapshot)))
        #expect(graph.transitions.count == (ready == 1 ? 5 : 1))
        #expect(graph.deadlockedStates == (ready == 1 ? [] : [initial]))
        for var successor in successors {
            #expect(try !successor.isEnabled(.choose))
            #expect(try successor.isEnabled(.finish))
            let state = successor.state
            _ = try successor.send(.finish)
            #expect(successor.state == state)
            #expect(try successor.isEnabled(.Terminating))
        }
    }
}
