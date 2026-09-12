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

        var pending = [try DieHardModel.makeMachine()]
        #expect(Set(pending.map(\.state)) == formalInitial)
        let allActions: Set<DieHardModel.Action> = [
            .FillSmallJug, .FillBigJug, .EmptySmallJug, .EmptyBigJug, .SmallToBig, .BigToSmall
        ]
        var nativeStates: Set<DieHardModel.State> = []
        var nativeEdges: Set<Edge> = []
        while let machine = pending.popLast() {
            try #require((0...5).contains(machine.state.big) && (0...3).contains(machine.state.small),
                "Native execution escaped the bounded jug capacities")
            guard nativeStates.insert(machine.state).inserted else { continue }
            #expect(try machine.violatedInvariants().isEmpty)
            let actions = try machine.enabledActions()
            #expect(Set(actions) == allActions)
            for action in actions {
                #expect(try machine.isEnabled(action))
                var next = machine
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                nativeEdges.insert(Edge(source: machine.state, action: String(describing: action), target: next.state))
                pending.append(next)
            }
        }
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
