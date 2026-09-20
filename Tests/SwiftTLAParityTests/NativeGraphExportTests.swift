import Testing
import SwiftTLA
import UpstreamParity

struct NativeGraphExportTests {
    @Test("provided native projections preserve the complete graph and require every snapshot")
    func validatesProvidedProjections() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
            ($0, try CanonicalState(native.formalProjection(of: $0)))
        })
        let formal = try ModelChecker(
            compilation: CyclicExportModel.spec.compile(),
            configuration: .init(maximumStateLimit: 2, symmetryReduction: .disabled)
        ).explore()
        try #require(formal.isComplete)
        #expect(try CanonicalGraph(native, states: states) == FormalGraphExporter().export(formal).graph)
        for snapshot in native.transitions.keys {
            var missing = states
            missing.removeValue(forKey: snapshot)
            #expect(throws: CanonicalGraphError.missingNativeSnapshot) {
                try CanonicalGraph(native, states: missing)
            }
            missing[CyclicExportModel.Snapshot(state: .init(value: 99))] = states[snapshot]
            #expect(missing.count == states.count)
            #expect(throws: CanonicalGraphError.missingNativeSnapshot) {
                try CanonicalGraph(native, states: missing)
            }
        }
    }

    @Test("native export checks projections of sources with no outgoing edges")
    func rejectsMissingDeadlockedSourceProjection() throws {
        let initial = try #require(FailingExportModel.initialMachines().first { $0.state.value == 0 })
        let native = try ReachabilityGraph(initialMachines: [initial], maximumStates: 1)
        #expect(native.transitions.count == 1)
        #expect(native.transitions.values.allSatisfy(\.isEmpty))
        let projection = try CanonicalState(native.formalProjection(of: initial.snapshot))
        let states = [FailingExportModel.Snapshot(state: .init(value: 99)): projection]
        #expect(throws: CanonicalGraphError.missingNativeSnapshot) {
            try CanonicalGraph(native, states: states)
        }
    }

    @Test("native export retains all reachability targets and a shortest witness without truncation")
    func exportsPositiveOutcomes() throws {
        let graph = try ReachabilityGraph(initialMachines: ReachabilityExportModel.initialMachines(), maximumStates: 3)
        let native = try NativeModelRun(graph, rendered: ReachabilityExportModel.render())
        #expect(native.graph.graph.states.count == 3)
        #expect(native.graph.graph.edges.count == 2)
        #expect(native.reachabilityTargets["Positive"]?.count == 2)
        #expect(native.reachabilityTargets["BeyondLimit"] == [])
        #expect(native.checks.properties["BeyondLimit"] == .unreachable)
        guard case .reached(let witness) = native.checks.properties["Positive"] else {
            Issue.record("Missing positive witness")
            return
        }
        #expect(witness.steps.count == 2)
        try native.validateReachabilityWitness(witness, for: "Positive")
        let last = try #require(graph.transitions.keys.first { $0.state.value == 2 })
        let alternate = GraphTrace(id: "alternate", steps: try graph.trace(to: last).map {
            .init(state: try CanonicalState(graph.formalProjection(of: $0.state)).key,
                action: try $0.action.map { try graph.formalCall(for: $0).description })
        })
        try native.validateReachabilityWitness(alternate, for: "Positive")
    }

    @Test("positive reachability requires matching native result coverage")
    func rejectsUnreportedReachability() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let original = try CyclicExportModel.spec.compile()
        let exported = try NativeModelRun(native, rendered: original.render())
        var specification = CyclicExportModel.spec
        specification.reachabilityProperties = [.init(name: "ReachGoal", body: .value(.bool(true)))]
        let rendered = try specification.compile().render()
        #expect(throws: EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name,
            field: "native check coverage")) {
            try NativeModelRun(rendered: rendered, graph: exported.graph, checks: exported.checks)
        }
    }

    @Test("native lasso export retains named transitions and their rendered names")
    func retainsNamedCycleTransitions() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let compilation = try CyclicExportModel.spec.compile()
        let namedCase = try fixtureCase(testReferencePin(), renderedActions: [
            RenderedAction(sourceName: "advance", arguments: [], renderedName: "ConcreteAdvance")
        ])
        let exported = try NativeModelRun(native, rendered: compilation.render(), for: namedCase)
        let trace = try counterexample(exported.checks.properties["ReachesTwo"])
        let start = try #require(trace.cycleStartIndex)
        #expect(trace.steps[start].state == trace.steps.last?.state)
        #expect(trace.steps.dropFirst(start + 1).allSatisfy { $0.action == "ConcreteAdvance" })
        #expect(exported.graph.isComplete)
    }

    @Test("native export retains every property verdict when safety and temporal checks fail together")
    func retainsAllNativeChecks() throws {
        let compilation = try FailingExportModel.spec.compile()
        let rendered = try compilation.render()
        for initial in try FailingExportModel.initialMachines() {
            let native = try ReachabilityGraph(initialMachines: [initial], maximumStates: 3)
            let exported = try NativeModelRun(native, rendered: rendered, checkingDeadlock: true)
            let defaultChecks = try NativeModelRun(native, rendered: rendered)
            #expect(defaultChecks.checks == exported.checks)
            #expect(defaultChecks.graph == exported.graph)
            #expect(exported.graph.isComplete)
            #expect(try exported.graph.graph == CanonicalGraph(native))
            #expect(Set(exported.checks.properties.keys) == ["BelowTwo", "BelowThree", "ReachesThree"])
            #expect(exported.checks.properties["BelowThree"] == .satisfied)
            #expect(!exported.checks.allSatisfied)
            _ = try counterexample(exported.checks.deadlock)
            let temporal = try counterexample(exported.checks.properties["ReachesThree"])
            #expect(temporal.cycleStartIndex != nil)
            if initial.state.value == 0 {
                #expect(exported.checks.properties["BelowTwo"] == .satisfied)
                #expect(temporal.steps.map(\.action) == [nil, nil])
            } else {
                let trace = try counterexample(exported.checks.properties["BelowTwo"])
                #expect(trace.steps.map(\.action) == [nil, "advance"])
                let values = trace.steps.map { exported.graph.graph.states[$0.state]?.bindings["value"] }
                #expect(values == [.integer(1), .integer(2)])
                let namedCase = try fixtureCase(testReferencePin(), renderedActions: [
                    RenderedAction(sourceName: "advance", arguments: [], renderedName: "ConcreteAdvance")
                ])
                let named = try NativeModelRun(native, rendered: rendered, checkingDeadlock: true, for: namedCase)
                #expect(try counterexample(named.checks.properties["BelowTwo"]).steps.map(\.action) == [nil, "ConcreteAdvance"])
                #expect(Set(named.graph.graph.edges.map(\.action)) == ["ConcreteAdvance"])
            }
        }
    }

    @Test("export requires the native temporal results to cover the resolved declarations")
    func rejectsMismatchedDeclarations() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let other = try FailingExportModel.spec.compile()
        #expect(throws: EvidenceFormatError.self) {
            try NativeModelRun(native, rendered: other.render())
        }
    }

    private func counterexample(_ result: PropertyResult?) throws -> GraphTrace {
        guard case .violated(let trace) = result else {
            throw EvidenceFormatError.invalidField(record: "test", field: "missing counterexample")
        }
        return trace
    }
}
