import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct NQueensCorpusStateGraphTests {
    @Test("The retained TLC NoSolutions counterexample belongs to the complete native graph")
    func decodesTLCCollectionCounterexample() throws {
        let scenario = try #require(NQueensModel.validationScenarios().first)
        let native = try scenario.explore(maximumStates: 5_000)
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

    @Test("FourQueens preserves its complete graph, generated transitions, and selected properties")
    func completeConfiguredGraph() throws {
        let scenario = try #require(NQueensModel.validationScenarios().first)
        let machine = try NQueensModel.makeMachine(configuration: scenario.configuration)
        let native = try scenario.explore(maximumStates: 5_000)
        #expect(!native.safetyViolations.isEmpty)
        for (snapshot, violations) in native.safetyViolations {
            #expect(violations == [.invariant(.NoSolutions)])
            #expect(!snapshot.state.sols.isEmpty)
        }
        #expect(native.temporalResults[.Termination]?.status == .satisfied)
        let exported = try CanonicalGraph(native)
        #expect(exported.states.count == 786)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["Invariant", "TypeInvariant", "NoSolutions", "Termination"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT N = 4"))
        struct Edge: Hashable {
            let source: NQueensModel.Snapshot
            let action: NQueensModel.Action
            let target: NQueensModel.Snapshot
        }
        let checkedEdges = Set(native.transitions.flatMap { source, transitions in
            transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
        })
        var pending = try scenario.initialMachines()
        var states: Set<NQueensModel.Snapshot> = []
        var edges: Set<Edge> = []
        while let current = pending.popLast() {
            guard states.insert(current.snapshot).inserted else { continue }
            try #require(states.count <= 786)
            for action in try current.enabledActions() {
                let successors = try current.successors(for: action)
                var sent = current
                if successors.count == 1 {
                    let transition = try sent.send(action)
                    #expect(transition.after == successors[0].state)
                    #expect(sent.snapshot == successors[0].snapshot)
                } else {
                    #expect(throws: GeneratedMachineError.ambiguousAction) { try sent.send(action) }
                    #expect(sent.snapshot == current.snapshot)
                }
                edges.formUnion(successors.map { Edge(source: current.snapshot, action: action, target: $0.snapshot) })
                pending.append(contentsOf: successors)
            }
        }
        #expect(states == Set(native.transitions.keys))
        #expect(edges == checkedEdges)
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

    @Test("FourQueens stops at NoSolutions without claiming its unevaluated properties passed")
    func noSolutionsProducesCounterexample() throws {
        let scenario = try #require(NQueensModel.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 5_000)
        let exhaustive = try NativeModelRun(scenario.explore(maximumStates: 5_000), rendered: scenario.render())
        try run.validateExpectations()
        guard case .violated(let trace) = run.native.checks.properties["NoSolutions"] else {
            Issue.record("Expected the NoSolutions counterexample")
            return
        }
        try trace.validate(in: exhaustive.graph.graph)
        let terminal = try #require(trace.steps.last)
        let state = try #require(exhaustive.graph.graph.states[terminal.state])
        guard case .orderedSet(let solutions) = state.bindings["sols"] else {
            Issue.record("Expected a set of discovered solutions")
            return
        }
        #expect(!solutions.isEmpty)
        #expect(run.native.graph == nil)
        #expect(run.native.checks.properties.filter { $0.key != "NoSolutions" }.values.allSatisfy { $0 == .unavailable })
        #expect(run.native.checks.deadlock == .unavailable)
        #expect(exhaustive.checks.properties.filter { $0.key != "NoSolutions" }.values.allSatisfy { $0 == .satisfied })
        #expect(exhaustive.checks.deadlock == .satisfied)
    }
}
