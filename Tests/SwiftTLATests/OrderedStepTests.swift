import Testing
@testable import SwiftTLA

@Suite struct OrderedStepTests {
    @Test("Later reads observe earlier writes in one atomic transition")
    func orderedReadsAndRepeatedWrites() throws {
        var machine = try OrderedCopyModel.makeMachine()
        let transition = try machine.send(.copy)
        #expect(transition.before.x == 1)
        #expect(transition.after.x == 3)
        #expect(transition.after.y == 2)
        let graph = try ReachabilityGraph(
            initialMachines: OrderedCopyModel.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 2)
        #expect(graph.transitions.keys.allSatisfy { $0.state.x != 2 })
    }

    @Test("Choices and following statements read their current branch values")
    func orderedChoice() throws {
        let machine = try OrderedGuardModel.makeMachine()
        let successors = try machine.successors(for: .choose)
        #expect(successors.count == 1)
        let next = try #require(successors.first)
        #expect(next.state.value == 2)
        #expect(next.state.copied == 2)
    }

    @Test("A later blocked guard discards every earlier write")
    func blockedBranchDoesNotCommit() throws {
        var machine = try OrderedBlockedModel.makeMachine()
        let before = machine.snapshot
        #expect(try machine.successors(for: .advance).isEmpty)
        #expect(throws: GeneratedMachineError.noMatchingSuccessor) {
            try machine.send(.advance)
        }
        #expect(machine.snapshot == before)
    }
    @Test("Assertions read the value at their position in the step")
    func assertionReadsUpdatedValue() throws {
        let graph = try ReachabilityGraph(
            initialMachines: OrderedAssertionModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.count == 2)
    }

    @Test("Procedure arguments capture earlier writes in the caller")
    func callReadsUpdatedValue() throws {
        let graph = try ReachabilityGraph(
            initialMachines: OrderedCallModel.initialMachines(), maximumStates: 8)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.contains { $0.state.output == 7 })
        #expect(graph.transitions.keys.allSatisfy { $0.state.output == 0 || $0.state.output == 7 })
    }

    @Test("Ordinary let captures at its declaration and preserves shadowed values")
    func savedValuesAreStable() throws {
        var machine = try SavedStepValueModel.makeMachine()
        let result = try machine.send(.advance)
        #expect(result.after.count == 4)
        #expect(result.after.copied == 3)
        let graph = try ReachabilityGraph(
            initialMachines: SavedStepValueModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)

        let compilation = try SavedStepValueModel.spec.compile()
        let initial = try firstCompiledState(in: compilation)
        let next = try #require(try compiledSuccessors(
            named: "advance", arguments: [], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "count", in: next, compilation: compilation) == .int(4))
        #expect(try renderedValue(named: "copied", in: next, compilation: compilation) == .int(3))
    }

}
