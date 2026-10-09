import Testing
import SwiftTLA

struct CollectionCheckingTests {
    @Test("independent set steps preserve the complete generated graph")
    func checksSetSteps() throws {
        let graph = try ReachabilityGraph(initialMachines: SetStepMachine.initialMachines(), maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        #expect(Set(graph.transitions.keys.map(\.state.seen)) == [Set<Int>(), Set<Int>([1])])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 3)
        #expect(graph.safetyViolations.isEmpty)
        let empty = try #require(graph.transitions.first { $0.key.state.seen.isEmpty }?.value)
        #expect(empty.count == 1)
        #expect(empty.contains { $0.action == .add && $0.target.state.seen == Set([1]) })
        let occupied = try #require(graph.transitions.first { $0.key.state.seen == Set([1]) }?.value)
        #expect(occupied.count == 2)
        #expect(occupied.contains { $0.action == .add && $0.target.state.seen == Set([1]) })
        #expect(occupied.contains { $0.action == .remove && $0.target.state.seen.isEmpty })
        let tla = try SetStepMachine.render().tlaBundle.tla
        #expect(tla.contains("(seen \\cup {1})"))
        #expect(!tla.contains("VARIABLES pc"))
    }

    @Test("bounded array append has exactly one unfinished deadlock")
    func checksArraySteps() throws {
        let graph = try ReachabilityGraph(initialMachines: ArrayStepMachine.initialMachines(), maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        #expect(Set(graph.transitions.keys.map(\.state.values)) == [[], [1], [1, 1]])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 2)
        #expect(Set(graph.deadlockedStates.map(\.state.values)) == [[1, 1]])
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.values == [1, 1])
        #expect(graph.safetyViolations.first?.value == [.deadlock])
        for (source, target) in [([Int](), [1]), ([1], [1, 1])] {
            let outgoing = try #require(graph.transitions.first { $0.key.state.values == source }?.value)
            #expect(outgoing.count == 1)
            #expect(outgoing.contains { $0.action == .append && $0.target.state.values == target })
        }
        let tla = try ArrayStepMachine.render().tlaBundle.tla
        #expect(tla.contains("Append(values, 1)"))
        #expect(!tla.contains("VARIABLES pc"))
    }

    @Test("finite initial domain retains both states and an unfinished deadlock")
    func checksFiniteInitialStates() throws {
        let graph = try ReachabilityGraph(initialMachines: FiniteInitialStepMachine.initialMachines(), maximumStates: 10)
        #expect(Set(graph.initialStates.map(\.state.phase)) == [1, 2])
        #expect(Set(graph.transitions.keys.map(\.state.phase)) == [1, 2])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 1)
        #expect(Set(graph.deadlockedStates.map(\.state.phase)) == [2])
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.phase == 2)
        #expect(graph.safetyViolations.first?.value == [.deadlock])
        let outgoing = try #require(graph.transitions.first { $0.key.state.phase == 1 }?.value)
        #expect(outgoing.count == 1)
        #expect(outgoing.contains { $0.action == .prepare && $0.target.state.phase == 2 })
    }
}
