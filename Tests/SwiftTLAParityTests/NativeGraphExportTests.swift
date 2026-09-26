import Testing
import SwiftTLA
import UpstreamParity

struct NativeGraphExportTests {
    @Test("canonical lookup resolves snapshot hash collisions by complete state")
    func resolvesSnapshotHashCollisions() throws {
        let first = CollidingExportSnapshot(value: 1)
        let second = CollidingExportSnapshot(value: 2)
        let missing = CollidingExportSnapshot(value: 3)
        let firstKey = CanonicalStateKey(canonicalEncoding: "state:[value=integer:1]")
        let secondKey = CanonicalStateKey(canonicalEncoding: "state:[value=integer:2]")
        let missingKey = CanonicalStateKey(canonicalEncoding: "state:[value=integer:3]")
        var index = NativeCanonicalKeyIndex<CollidingExportSnapshot>()
        index.insert(first, key: firstKey)
        index.insert(second, key: secondKey)
        try index.finalize(sortedKeys: [firstKey, secondKey])
        #expect(try index.idForKnownSnapshot(first, projecting: { firstKey }) == 0)
        #expect(try index.idForKnownSnapshot(second, projecting: { secondKey }) == 1)
        #expect(try index.key(for: first, projecting: { firstKey }) == firstKey)
        #expect(try index.key(for: second, projecting: { secondKey }) == secondKey)
        #expect(throws: CanonicalGraphError.missingNativeSnapshot) {
            try index.key(for: missing, projecting: { missingKey })
        }
    }

    @Test("native projection matches the independent formal exporter")
    func matchesIndependentExporter() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let formal = try ModelChecker(
            compilation: CyclicExportModel.spec.compile(),
            configuration: .init(maximumStateLimit: 2, symmetryReduction: .disabled)
        ).explore()
        try #require(formal.isComplete)
        let expected = try FormalGraphExporter().export(formal).graph
        #expect(try CanonicalGraph(native) == expected)
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
