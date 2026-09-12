import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct HourClockCorpusStateGraphTests {
    private struct Edge: Hashable {
        let source: Int
        let action: String
        let target: Int
    }

    @Test("HourClock native execution matches the complete formal graph and initial domain")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try HourClockModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)
        ).explore()
        #expect(exploration.isComplete)
        let hour = try #require(TLAStateProjection.Token(validating: "hr"))
        let formalHours = try exploration.graph.states.mapValues { projection in
            try #require(projection.value(for: hour).flatMap(Int.init(formalValue:)))
        }
        let formalInitial = try Set(exploration.initialStateIDs.map { try #require(formalHours[$0]) })
        var formalEdges: Set<Edge> = []
        for (source, transitions) in exploration.graph.transitions {
            for transition in transitions {
                formalEdges.insert(try Edge(
                    source: #require(formalHours[source]), action: transition.label.action,
                    target: #require(formalHours[transition.target])
                ))
            }
        }

        // The pinned HourClock configuration admits every hour as an initial state.
        var pending = try HourClockModel.initialMachines()
        let nativeInitial = Set(pending.map { $0.state.hr })
        var nativeHours: Set<Int> = []
        var nativeEdges: Set<Edge> = []
        while let machine = pending.popLast() {
            try #require((1...12).contains(machine.state.hr), "Native execution escaped the bounded hour domain")
            guard nativeHours.insert(machine.state.hr).inserted else { continue }
            #expect(try machine.violatedInvariants().isEmpty)
            let actions = try machine.enabledActions()
            #expect(actions == [.HCnxt])
            for action in actions {
                var next = machine
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                nativeEdges.insert(Edge(source: machine.state.hr, action: String(describing: action), target: next.state.hr))
                pending.append(next)
            }
        }
        #expect(nativeInitial == formalInitial)
        #expect(nativeHours == Set(formalHours.values))
        #expect(nativeEdges == formalEdges)
        #expect(nativeHours.count == 12)
        #expect(nativeEdges.count == 12)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try HourClockModel.makeMachine() }
        for invalid in [0, 13] {
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try HourClockModel.makeMachine(.init(hr: invalid))
            }
        }
    }
}
