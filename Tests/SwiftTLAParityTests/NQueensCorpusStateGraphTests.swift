import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct NQueensCorpusStateGraphTests {
    @Test("FourQueens native choices preserve the complete formal graph and invariants")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try NQueensModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5_000, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        #expect(compilation.semantics.behavior.temporalProperties.map(\.name) == ["Termination"])
        let temporal = try exploration.analyzeTemporalProperties(in: compilation)
        #expect(temporal.map(\.status) == [.satisfied])
        let native = try ReachabilityGraph(initialMachines: NQueensModel.initialMachines(), maximumStates: 5_000)
        #expect(native.safetyViolations.isEmpty)
        let machine = try NQueensModel.makeMachine()
        let exported = try CanonicalGraph(native, using: machine)
        let formal = try SwiftGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(exported.states.count == 786)
        let terminalEdges = native.transitions.flatMap { source, transitions in
            transitions.filter { $0.action == .Terminating }.map { (source: source, target: $0.target) }
        }
        #expect(terminalEdges.count == 1)
        let edge = try #require(terminalEdges.first)
        #expect(edge.source == edge.target)
        let terminal = edge.source
        #expect(terminal.state.todo.isEmpty)
        #expect(terminal.state.sols == [[2, 4, 1, 3], [3, 1, 4, 2]])
    }

    @Test("FourQueens reports the upstream NoSolutions counterexample separately from its successful properties")
    func noSolutionsProducesCounterexample() throws {
        var spec = NQueensModel.spec
        // The checked-in FourQueens MC.cfg adds this deliberately false invariant.
        spec.invariants.append(.init(
            name: "NoSolutions",
            body: .equal(.variable("sols"), .setLiteral([]))
        ))
        let result = try ModelChecker(
            compilation: spec.compile(),
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5_000, symmetryReduction: .disabled)
        ).check()
        guard case .invariantViolated(let invariant, let state, let trace) = result else {
            Issue.record("Expected the NoSolutions counterexample, received \(result)")
            return
        }
        #expect(invariant == "NoSolutions")
        #expect(!trace.isEmpty)
        let sols = try #require(TLAStateProjection.Token(validating: "sols"))
        guard case .set(let solutions) = state.value(for: sols) else {
            Issue.record("Expected a set of discovered solutions")
            return
        }
        #expect(!solutions.isEmpty)
    }
}
