import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct BranchingControl {
    enum Step: String, CaseIterable { case enter, choose }
    static var spec: TLASpec {
        #spec("BranchingControl") {
            DeadlockCheck()
            Algorithm("BranchingControl", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Invariant("AtMostOne") { value <= 1 }
                Do(Step.enter) { Goto(Step.choose) }
                Do(Step.choose) {
                    Choose(1...2) { choice in Assign(value, to: choice) }
                }
            })
        }
    }
}

@TLAModel
private struct BlockedControl {
    enum Step: String, CaseIterable { case wait }
    static var spec: TLASpec {
        #spec("BlockedControl") {
            DeadlockCheck()
            Algorithm("BlockedControl", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(Step.wait) {
                    When(value == 1)
                    Assign(value, to: 2)
                }
            })
        }
    }
}

@TLAModel
private struct InvalidAssumption {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("InvalidAssumption") {
            Assume(false)
            Algorithm("InvalidAssumption", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(Step.advance) { Assign(value, to: 1) }
            })
        }
    }
}

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
    }

    @Test("Safety checking retains the complete graph and a native counterexample")
    func invariantCounterexample() throws {
        let graph = try ReachabilityGraph(initialMachines: BranchingControl.initialMachines(), maximumStates: 10)
        let failure = try #require(graph.safetyViolations.first)
        #expect(graph.safetyViolations.count == 1)
        #expect(failure.value == [.invariant("AtMostOne")])
        #expect(failure.key.state.value == 2)
        #expect(graph.transitions.count == 4)
        let trace = try graph.trace(to: failure.key)
        #expect(trace.map { $0.state.state.value } == [0, 0, 2])
        #expect(trace.map(\.action) == [nil, .enter, .choose])
        #expect(graph.transitions.filter { $0.value.isEmpty }.count == 2)
        #expect(!graph.safetyViolations.values.joined().contains(.deadlock))
    }

    @Test("An unfinished blocked machine is a deadlock with an initial-state trace")
    func blockedControlIsDeadlocked() throws {
        let initial = try BlockedControl.makeMachine()
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
