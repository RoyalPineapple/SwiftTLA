import Foundation
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
        #expect(!native.safetyViolations.isEmpty)
        #expect(native.safetyViolations.allSatisfy { state, failures in
            state.state.big == 4 && failures == [.invariant(.NotSolved)]
        })
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

    @Test("DieHard retains the upstream expected violation and a valid solution trace without truncating the graph")
    func preservesUpstreamChecks() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "die-hard" })
        #expect(declaration.sourceModel == .dieHard)
        #expect(try declaration.resolveScenario()?.name == "Upstream")
        let reference = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/die-hard/DieHard.cfg"))
        #expect(SHA256.hex(reference) == declaration.cfgSHA256)
        #expect(String(decoding: reference, as: UTF8.self) == "SPECIFICATION Spec\nINVARIANTS TypeOK NotSolved\n")
        let scenarios = try DieHardModel.validationScenarios()
        #expect(scenarios.count == 1)
        let scenario = try #require(scenarios.first)
        let run = try NativeScenarioRun(scenario, maximumStates: 100)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        #expect(run.native.graph.graph.states.count == 16)
        #expect(run.native.graph.graph.edges.count == 96)
        #expect(run.native.checks.properties["TypeOK"] == .satisfied)
        #expect(run.native.checks.deadlock == .satisfied)
        guard case .violated(let trace) = run.native.checks.properties["NotSolved"] else {
            Issue.record("Expected the upstream NotSolved counterexample")
            return
        }
        try trace.validate(in: run.native.graph.graph)
        #expect(trace.cycleStartIndex == nil)
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.cfg.contains("INVARIANT TypeOK"))
        #expect(bundle.cfg.contains("INVARIANT NotSolved"))
        #expect(!bundle.tla.contains("VARIABLES pc"))
    }
}
