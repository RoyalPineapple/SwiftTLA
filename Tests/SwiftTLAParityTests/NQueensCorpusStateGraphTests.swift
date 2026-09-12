import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct NQueensCorpusStateGraphTests {
    private struct Edge: Hashable {
        let source: TLAStateProjection
        let target: TLAStateProjection
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
        let formalPositions = exploration.graph.states
        var formalEdges: Set<Edge> = []
        var terminalStutters = 0
        for (sourceID, transitions) in exploration.graph.transitions {
            let source = try #require(formalPositions[sourceID])
            for transition in transitions {
                let target = try #require(formalPositions[transition.target])
                if transition.label.action == "Terminating" {
                    #expect(source == target)
                    terminalStutters += 1
                } else {
                    #expect(transition.label.action == "nxtQ")
                    formalEdges.insert(Edge(source: source, target: target))
                }
            }
        }
        let native = try ReachabilityGraph(initialMachines: NQueensModel.initialMachines(), maximumStates: 5_000)
        #expect(native.safetyViolations.isEmpty)
        let machine = try NQueensModel.makeMachine()
        let nativePositions = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
            ($0, try machine.formalProjection(of: $0))
        })
        let nativeInitials = try Set(native.initialStates.map { try #require(nativePositions[$0]) })
        let formalInitials = try Set(exploration.initialStateIDs.map { try #require(formalPositions[$0]) })
        #expect(nativeInitials == formalInitials)
        let nativeEdges = try Set(native.transitions.flatMap { source, transitions in
            try transitions.map {
                Edge(source: try #require(nativePositions[source]), target: try #require(nativePositions[$0.target]))
            }
        })
        #expect(terminalStutters == 1)
        #expect(nativePositions.count == 786)
        #expect(Set(nativePositions.values) == Set(formalPositions.values))
        #expect(nativeEdges == formalEdges)
        let terminal = try #require(native.transitions.first { $0.value.isEmpty }?.key)
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
