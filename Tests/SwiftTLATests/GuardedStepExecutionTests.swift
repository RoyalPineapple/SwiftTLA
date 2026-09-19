import Testing
import SwiftTLA

struct GuardedStepExecutionTests {
    @Test("Process and procedure guards suppress failing bodies and discard only blocked choice updates",
        arguments: [0, 1], [0, 1])
    func guardsProcessAndProcedure(entryReady: Int, bodyReady: Int) throws {
        let initial = try #require(try GuardedProcesses.initialMachines().first {
            $0.state.entryReady == entryReady && $0.state.bodyReady == bodyReady
        })
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 100)
        #expect(graph.deadlockedStates.isEmpty == (entryReady == 1 && bodyReady == 1))
        #expect(graph.transitions.keys.filter { $0.state.value == 0 }.count == 1)
        for node in GuardedProcesses.Node.allCases {
            var machine = initial
            let enter = GuardedProcesses.Action.enter(process: node)
            #expect(try machine.isEnabled(enter) == (entryReady == 1))
            if entryReady == 0 {
                #expect(try machine.successors(for: enter).isEmpty)
                #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try machine.send(enter) }
                #expect(machine.snapshot == initial.snapshot)
                continue
            }
            _ = try machine.send(enter)
            #expect(machine.state.value == 1)
            let before = machine.snapshot
            let body = GuardedProcesses.Action.procedure_choose_body(process: node)
            let successors = try machine.successors(for: body)
            #expect(try machine.isEnabled(body) == (bodyReady == 1))
            #expect(Set(successors.map { $0.state.value }) == (bodyReady == 1 ? [1, 2] : []))
            #expect(throws: bodyReady == 1 ? GeneratedMachineError.ambiguousAction : .noMatchingSuccessor) {
                try machine.send(body)
            }
            #expect(machine.snapshot == before)
            #expect(Set(graph.transitions[before, default: []].filter { $0.action == body }.map(\.target))
                == Set(successors.map(\.snapshot)))
            for successor in successors {
                #expect(try successor.isEnabled(.finish(process: node)))
                for other in GuardedProcesses.Node.allCases where other != node {
                    #expect(try successor.isEnabled(.enter(process: other)))
                    #expect(try !successor.isEnabled(.finish(process: other)))
                }
            }
        }
    }

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
