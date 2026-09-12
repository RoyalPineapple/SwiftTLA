import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct NQueensCorpusStateGraphTests {
    private struct Position: Hashable {
        let state: NQueensModel.State
        let finished: Bool
    }

    private struct Edge: Hashable {
        let source: Position
        let target: Position
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
        let todo = try #require(TLAStateProjection.Token(validating: "todo"))
        let sols = try #require(TLAStateProjection.Token(validating: "sols"))
        let pc = try #require(TLAStateProjection.Token(validating: "pc"))
        func boards(_ value: TLAValue?) throws -> Set<[Int]> {
            guard case .set(let values) = value else {
                throw TLAStateProjectionDiagnostic.invalidValue(path: "boards")
            }
            return try Set(values.map { value in
                guard case .tuple(let columns) = value else {
                    throw TLAStateProjectionDiagnostic.invalidValue(path: "board")
                }
                return try columns.map { try #require(Int(formalValue: $0)) }
            })
        }
        let formalPositions = try exploration.graph.states.mapValues { projection in
            let location = try #require(projection.value(for: pc).flatMap(String.init(formalValue:)))
            try #require(location == "nxtQ" || location == "Done")
            return try Position(
                state: .init(todo: boards(projection.value(for: todo)), sols: boards(projection.value(for: sols))),
                finished: location == "Done"
            )
        }
        var formalEdges: Set<Edge> = []
        var terminalStutters = 0
        for (sourceID, transitions) in exploration.graph.transitions {
            let source = try #require(formalPositions[sourceID])
            for transition in transitions {
                let target = try #require(formalPositions[transition.target])
                if transition.label.action == "Terminating" {
                    #expect(source.finished && source == target)
                    terminalStutters += 1
                } else {
                    #expect(transition.label.action == "nxtQ")
                    formalEdges.insert(Edge(source: source, target: target))
                }
            }
        }
        var pending = try NQueensModel.initialMachines()
        let action = try #require(pending.first?.enabledActions().first)
        func position(_ machine: NQueensModel) throws -> Position {
            let actions = try machine.enabledActions()
            #expect(actions.isEmpty || actions == [action])
            // This algorithm has exactly two control locations. Visible state alone
            // cannot distinguish the empty worklist before and after termination.
            return Position(state: machine.state, finished: actions.isEmpty)
        }
        #expect(try Set(pending.map(position)) == Set(exploration.initialStateIDs.map {
            try #require(formalPositions[$0])
        }))
        var nativePositions: Set<Position> = []
        var nativeEdges: Set<Edge> = []
        while let machine = pending.popLast() {
            let source = try position(machine)
            guard nativePositions.insert(source).inserted else { continue }
            try #require(nativePositions.count <= 5_000)
            #expect(try machine.violatedInvariants().isEmpty)
            let successors = try machine.successors(for: action)
            #expect(successors.isEmpty == source.finished)
            for successor in successors {
                nativeEdges.insert(try Edge(source: source, target: position(successor)))
                pending.append(successor)
            }
        }
        #expect(terminalStutters == 1)
        #expect(nativePositions.count == 786)
        #expect(nativePositions == Set(formalPositions.values))
        #expect(nativeEdges == formalEdges)
        let terminal = try #require(nativePositions.first { $0.finished })
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
