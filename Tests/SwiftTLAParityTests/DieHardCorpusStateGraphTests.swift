import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct DieHardCorpusStateGraphTests {
    private struct Edge: Hashable {
        let source: DieHardModel.State
        let action: String
        let target: DieHardModel.State
    }

    @Test("DieHard native execution preserves every labeled edge and self-loop in the formal graph")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try DieHardModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        let big = try #require(TLAStateProjection.Token(validating: "big"))
        let small = try #require(TLAStateProjection.Token(validating: "small"))
        let formalStates = try exploration.graph.states.mapValues { projection in
            try DieHardModel.State(
                big: #require(projection.value(for: big).flatMap(Int.init(formalValue:))),
                small: #require(projection.value(for: small).flatMap(Int.init(formalValue:)))
            )
        }
        let formalInitial = try Set(exploration.initialStateIDs.map { try #require(formalStates[$0]) })
        var formalEdges: Set<Edge> = []
        for (source, transitions) in exploration.graph.transitions {
            for transition in transitions {
                formalEdges.insert(try Edge(
                    source: #require(formalStates[source]), action: transition.label.action,
                    target: #require(formalStates[transition.target])
                ))
            }
        }

        let native = try ReachabilityGraph(initialMachines: DieHardModel.initialMachines(), maximumStates: 100)
        #expect(native.safetyViolations.isEmpty)
        #expect(Set(native.initialStates.map(\.state)) == formalInitial)
        let nativeStates = Set(native.transitions.keys.map(\.state))
        let nativeEdges = Set(native.transitions.flatMap { source, transitions in
            transitions.map { Edge(source: source.state, action: String(describing: $0.action), target: $0.target.state) }
        })
        #expect(nativeStates == Set(formalStates.values))
        #expect(nativeEdges == formalEdges)
        #expect(nativeStates.count == 16)
        #expect(nativeEdges.count == 96)
        #expect(nativeEdges.contains { $0.source == $0.target })
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try DieHardModel.makeMachine(.init(big: 5, small: 3))
        }
    }
}
