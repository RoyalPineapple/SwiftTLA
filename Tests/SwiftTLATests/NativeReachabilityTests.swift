import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct BranchingControl {
    enum Step: String, CaseIterable { case enter, choose }
    static var spec: TLASpec {
        #spec("BranchingControl") {
            Algorithm("BranchingControl", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(Step.enter) { Goto(Step.choose) }
                Do(Step.choose) {
                    Choose(1...2) { choice in Assign(value, to: choice) }
                }
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
