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

        let native = try ReachabilityGraph(initialMachines: HourClockModel.initialMachines(), maximumStates: 100)
        #expect(native.safetyViolations.isEmpty)
        let nativeInitial = Set(native.initialStates.map { $0.state.hr })
        let nativeHours = Set(native.transitions.keys.map { $0.state.hr })
        let nativeEdges = Set(native.transitions.flatMap { source, transitions in
            transitions.map { Edge(source: source.state.hr, action: String(describing: $0.action), target: $0.target.state.hr) }
        })
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
