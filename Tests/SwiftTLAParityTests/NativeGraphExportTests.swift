import Testing
import SwiftTLA
import UpstreamParity

struct NativeGraphExportTests {
    @Test("positive reachability cannot pass through an adapter without witness-aware outcomes")
    func rejectsUnreportedReachability() throws {
        let native = try ReachabilityGraph(initialMachines: CyclicExportModel.initialMachines(), maximumStates: 2)
        let original = try CyclicExportModel.spec.compile()
        let exported = try NativeModelRun(native, description: original.description, rendered: original.render())
        var specification = CyclicExportModel.spec
        specification.reachabilityProperties = [.init(name: "ReachGoal", body: .value(.bool(true)))]
        let rendered = try specification.compile().render()
        #expect(throws: EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name,
            field: "positive reachability requires witness-aware property comparison")) {
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
        let exported = try NativeModelRun(native, description: compilation.description,
            rendered: compilation.render(), for: namedCase)
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
            let exported = try NativeModelRun(native, description: compilation.description, rendered: rendered, checkingDeadlock: true)
            let defaultChecks = try NativeModelRun(native, description: compilation.description, rendered: rendered)
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
                let named = try NativeModelRun(native, description: compilation.description, rendered: rendered, checkingDeadlock: true, for: namedCase)
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
            try NativeModelRun(native, description: other.description, rendered: other.render())
        }
    }

    private func counterexample(_ result: PropertyResult?) throws -> GraphTrace {
        guard case .violated(let trace) = result else {
            throw EvidenceFormatError.invalidField(record: "test", field: "missing counterexample")
        }
        return trace
    }
}
