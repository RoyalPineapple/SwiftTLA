import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct ConstraintBoundaryCheckingTests {
    @Test("constraints restrict exploration, not application transitions or deadlock enabledness")
    func boundaryIsNotADeadlock() throws {
        let configuration = try ConstraintBoundaryCounter.Configuration(safetyLimit: 3)
        var machine = try ConstraintBoundaryCounter.makeMachine(configuration: configuration)
        _ = try machine.send(.advance)
        #expect(try machine.isEnabled(.advance))
        _ = try machine.send(.advance)
        #expect(machine.state.count == 2)
        #expect(try !machine.satisfiesStateConstraint())

        let graph = try ReachabilityGraph(initialMachines: ConstraintBoundaryCounter.initialMachines(configuration: configuration), maximumStates: 10)
        #expect(Set(graph.transitions.keys.map { $0.state.count }) == [0, 1])
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.deadlockedStates.isEmpty)
        #expect(graph.transitions.values.flatMap { $0 }.count == 1)
    }

    @Test("invariants still check excluded successor states and retain their full native trace")
    func boundaryViolationRetainsTrace() throws {
        let configuration = try ConstraintBoundaryCounter.Configuration(safetyLimit: 2)
        let graph = try ReachabilityGraph(initialMachines: ConstraintBoundaryCounter.initialMachines(configuration: configuration), maximumStates: 10)
        let boundary = try #require(graph.safetyViolations.keys.first)
        #expect(graph.safetyViolations[boundary] == [.invariant(.Bounded)])
        #expect(boundary.state.count == 2)
        #expect(graph.transitions[boundary] == nil)
        #expect(try graph.trace(to: boundary).map { $0.state.state.count } == [0, 1, 2])
        #expect(graph.safetyViolations.count == 1)
    }

    @Test("excluded initial states retain initial invariant witnesses without entering the graph")
    func initialConstraintRetainsSafetyChecks() throws {
        let initial = try ConstraintInitialCounter.initialMachines()
        #expect(initial.count == 3)
        let graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 10)
        #expect(Set(graph.initialStates.map { $0.state.count }) == [0, 1])
        #expect(Set(graph.transitions.keys.map { $0.state.count }) == [0, 1])
        let boundary = try #require(graph.safetyViolations.keys.first)
        #expect(boundary.state.count == 2)
        #expect(graph.safetyViolations[boundary] == [.invariant(.Bounded)])
        #expect(try graph.trace(to: boundary).map { $0.state.state.count } == [2])
        let compilation = try ConstraintInitialCounter.spec.compile()
        let formal = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
        #expect(formal.isComplete)
        #expect(formal.initialStateIDs.count == 2)
        #expect(formal.graph.states.count == 2)
        #expect(formal.safetyViolations.map { $0.diagnostic?.kind } == [.invariantViolated])
        #expect(formal.outcome.diagnostic?.trace.count == 1)
        #expect(throws: EvidenceFormatError.self) {
            try NativeModelRun(graph, rendered: compilation.render())
        }
    }
}
