import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct NQueensCorpusStateGraphTests {
    @Test("The retained TLC NoSolutions counterexample belongs to the complete native graph")
    func decodesTLCCollectionCounterexample() throws {
        let native = try ReachabilityGraph(initialMachines: NQueensModel.initialMachines(), maximumStates: 5_000)
        let graph = try CanonicalGraph(native)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/FiniteGraph/TLCTrace/nqueens-nosolutions.json")
        let trace = try TLCTraceParser().parseCounterexample(Data(contentsOf: fixture), states: graph.states.values)
        #expect(trace.steps.count == 5)
        #expect(trace.cycleStartIndex == nil)
        try trace.validate(in: graph)
        let final = try #require(trace.steps.last)
        let state = try #require(graph.states[final.state])
        #expect(state.bindings["sols"] == .set([.tuple([.integer(2), .integer(4), .integer(1), .integer(3)])]))
    }

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
        let machine = try NQueensModel.makeMachine()
        let native = try ReachabilityGraph(initialMachines: NQueensModel.initialMachines(), maximumStates: 5_000)
        #expect(!native.safetyViolations.isEmpty)
        for (snapshot, violations) in native.safetyViolations {
            #expect(violations == [.invariant(.NoSolutions)])
            #expect(!snapshot.state.sols.isEmpty)
        }
        #expect(native.temporalResults[.Termination]?.status == .satisfied)
        let exported = try CanonicalGraph(native)
        let formal = try FormalGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(exported.states.count == 786)
        let terminalEdges = native.transitions.flatMap { source, transitions in
            transitions.filter { $0.action == .Terminating }.map { (source: source, target: $0.target) }
        }
        #expect(terminalEdges.count == 1)
        let edge = try #require(terminalEdges.first)
        #expect(edge.source == edge.target)
        let terminal = edge.source
        guard case .eventually(let isDone) = try machine.temporalProperties()[.Termination] else {
            Issue.record("Expected the generated termination predicate")
            return
        }
        #expect(try Set(native.transitions.keys.filter { try isDone($0, $0) }) == [terminal])
        #expect(terminal.state.todo.isEmpty)
        #expect(terminal.state.sols == [[2, 4, 1, 3], [3, 1, 4, 2]])
    }

    @Test("FourQueens reports the upstream NoSolutions counterexample separately from its successful properties")
    func noSolutionsProducesCounterexample() throws {
        let result = try ModelChecker(
            compilation: NQueensModel.spec.compile(),
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
