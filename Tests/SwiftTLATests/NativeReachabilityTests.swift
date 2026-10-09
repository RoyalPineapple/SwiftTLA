import Testing
import SwiftTLA

@Suite struct NativeReachabilityTests {
    @Test("Exploration distinguishes control locations and retains every choice")
    func completeExecutionState() throws {
        let initial = try BranchingControl.makeMachine()
        let entered = try #require(try initial.successors(for: .enter).first)
        #expect(initial.state == entered.state)
        #expect(initial.snapshot != entered.snapshot)
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 10)
        #expect(graph.initialStates == [initial.snapshot])
        let initialEdges = try #require(graph.transitions[initial.snapshot])
        #expect(initialEdges.count == 1)
        #expect(initialEdges.first?.target == entered.snapshot)
        let choices = try #require(graph.transitions[entered.snapshot])
        #expect(Set(choices.map { $0.target.state.value }) == [1, 2])
        #expect(choices.allSatisfy { $0.action == .choose })
        #expect(graph.transitions.count == 4)
        var application = initial
        #expect(try application.send(.enter).after == entered.state)
        #expect(application.snapshot == entered.snapshot)
        #expect(throws: GeneratedMachineError.ambiguousAction) { try application.send(.choose) }
        #expect(application.snapshot == entered.snapshot)

        var pending = [initial]
        var visited: Set<BranchingControl.Snapshot> = []
        while let machine = pending.popLast() {
            guard visited.insert(machine.snapshot).inserted else { continue }
            let edges = try #require(graph.transitions[machine.snapshot])
            #expect(Set(try machine.enabledActions()) == Set(edges.map(\.action)))
            for action: BranchingControl.Action in [.enter, .choose, .Terminating] {
                let successors = try machine.successors(for: action)
                let targets = edges.filter { $0.action == action }.map(\.target)
                #expect(Set(successors.map(\.snapshot)) == Set(targets))
                #expect(successors.count == targets.count)
                #expect(try machine.isEnabled(action) == !successors.isEmpty)
                var dispatched = machine
                switch successors.count {
                case 0:
                    #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try dispatched.send(action) }
                    #expect(dispatched.snapshot == machine.snapshot)
                case 1:
                    let transition = try dispatched.send(action)
                    #expect(transition.before == machine.state)
                    #expect(transition.after == successors[0].state)
                    #expect(dispatched.snapshot == successors[0].snapshot)
                default:
                    #expect(throws: GeneratedMachineError.ambiguousAction) { try dispatched.send(action) }
                    #expect(dispatched.snapshot == machine.snapshot)
                }
                pending.append(contentsOf: successors)
            }
        }
        #expect(visited == Set(graph.transitions.keys))
    }

    @Test("Safety checking retains the complete graph and a native counterexample")
    func invariantCounterexample() throws {
        let graph = try ReachabilityGraph(initialMachines: BranchingControl.initialMachines(), maximumStates: 10)
        let failure = try #require(graph.safetyViolations.first)
        #expect(graph.safetyViolations.count == 1)
        #expect(failure.value == [.invariant(.AtMostOne)])
        #expect(failure.key.state.value == 2)
        #expect(graph.transitions.count == 4)
        let trace = try graph.trace(to: failure.key)
        #expect(trace.map { $0.state.state.value } == [0, 0, 2])
        #expect(trace.map(\.action) == [nil, .enter, .choose])
        let terminalStates = graph.transitions.filter { $0.value.contains { $0.action == .Terminating } }
        #expect(terminalStates.count == 2)
        for (state, successors) in terminalStates {
            #expect(successors.count == 1)
            #expect(successors.first?.target == state)
        }
        #expect(!graph.safetyViolations.values.joined().contains(.deadlock))
    }

    @Test("An unfinished blocked machine is a deadlock with an initial-state trace")
    func blockedControlIsDeadlocked() throws {
        var initial = try BlockedControl.makeMachine()
        let snapshot = initial.snapshot
        #expect(try initial.successors(for: .wait).isEmpty)
        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try initial.send(.wait) }
        #expect(initial.snapshot == snapshot)
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 10)
        #expect(graph.safetyViolations[initial.snapshot] == [.deadlock])
        let trace = try graph.trace(to: initial.snapshot)
        #expect(trace.count == 1)
        #expect(trace.first?.state == initial.snapshot)
        #expect(trace.first?.action == nil)
    }

    @Test("False generated assumptions reject exploration")
    func rejectsFalseAssumptions() throws {
        #expect(throws: ExplorationError.assumptionViolated) {
            try ReachabilityGraph(initialMachines: InvalidAssumption.initialMachines(), maximumStates: 10)
        }
    }

    @Test("An incomplete exploration never returns a graph")
    func rejectsIncompleteExploration() throws {
        let initial = try BranchingControl.makeMachine()
        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try ReachabilityGraph(initialMachines: [initial], maximumStates: 1)
        }
        #expect(throws: ExplorationError.invalidStateLimit(0)) {
            try ReachabilityGraph(initialMachines: [initial], maximumStates: 0)
        }
        #expect(throws: ExplorationError.noInitialStates) {
            try ReachabilityGraph<BranchingControl>(initialMachines: [], maximumStates: 10)
        }
    }
}
