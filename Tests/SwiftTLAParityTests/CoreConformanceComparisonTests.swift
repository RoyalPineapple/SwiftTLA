import Testing
@testable import UpstreamParity

struct CoreConformanceComparisonTests {
    @Test("complete canonical runs produce matching receipts before exact comparison")
    func emitsComparableReceipts() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let graph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "advance", target: second.key)]
        )
        let run = try CanonicalRun(
            graph: graph,
            observableActions: ["advance"],
            outcome: .exhaustiveSuccess
        )

        let comparison = exactFiniteTLCGraph(
            expected: run,
            actual: run,
            compiledModelIdentity: "model",
            configurationIdentity: "configuration",
            symmetrySchemaIdentity: "none",
            maximumStateLimit: 10
        )

        #expect(comparison.isConformant)
        #expect(comparison.expectedReceipt == comparison.actualReceipt)
        #expect(comparison.expectedReceipt?.supportsExactConformance == true)
    }

    @Test("declared observable mappings contribute to comparable receipts")
    func recordsDeclaredMappingIdentity() throws {
        let expectedState = CanonicalState(bindings: ["counter": .integer(1)])
        let actualState = CanonicalState(bindings: ["swiftCounter": .integer(1)])
        let expectedGraph = try CanonicalGraph(
            initialStates: [expectedState],
            states: [expectedState],
            edges: []
        )
        let actualGraph = try CanonicalGraph(
            initialStates: [actualState],
            states: [actualState],
            edges: []
        )
        let expected = try CanonicalRun(
            graph: expectedGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let actual = try CanonicalRun(
            graph: actualGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let mapping = ObservableNameMapping(
            expectedVariables: ["counter"],
            actualVariables: ["swiftCounter"],
            variables: ["counter": "swiftCounter"],
            expectedActions: [],
            actualActions: [],
            actions: [:]
        )

        let comparison = exactFiniteTLCGraph(
            expected: expected,
            actual: actual,
            mapping: mapping,
            compiledModelIdentity: "model",
            configurationIdentity: "configuration",
            symmetrySchemaIdentity: "none",
            maximumStateLimit: 10
        )

        #expect(comparison.isConformant)
        #expect(comparison.expectedReceipt?.observableNameMappingIdentity == mapping.canonicalIdentity)
        #expect(comparison.expectedReceipt == comparison.actualReceipt)
    }

    @Test("same state count with a changed edge is semantic non-conformance")
    func reportsCategorizedEdgeDifference() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let expectedGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "advance", target: second.key)]
        )
        let actualGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "reset", target: second.key)]
        )
        let expected = try CanonicalRun(graph: expectedGraph, observableActions: ["advance"], outcome: .exhaustiveSuccess)
        let actual = try CanonicalRun(graph: actualGraph, observableActions: ["reset"], outcome: .exhaustiveSuccess)

        let comparison = exactFiniteTLCGraph(expected: expected, actual: actual)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .edges })
        #expect(comparison.differences.contains { $0.category == .mapping })
        // Edge witnesses are selected in canonical sort order. The missing
        // upstream `advance` edge therefore precedes the extra `reset` edge.
        let edgeReport = try #require(comparison.failureReports.first { $0.whereItFailed.contains("action advance") })
        #expect(edgeReport.expected.contains("TLC permits this transition 1 time(s)."))
        #expect(edgeReport.actual.contains("SwiftTLA permits this transition 0 time(s)."))
        #expect(edgeReport.nextSafeAction.contains("advance"))
    }

    @Test("partial name mappings and incomplete outcomes cannot pass")
    func rejectsPartialMappingsAndIncompleteRuns() throws {
        let state = CanonicalState(bindings: ["counter": .integer(1)])
        let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [])
        let complete = try CanonicalRun(graph: graph, observableActions: [], outcome: .exhaustiveSuccess)
        let partial = try CanonicalRun(graph: graph, observableActions: [], outcome: .incomplete(reason: "state limit"))
        let mapping = ObservableNameMapping(
            expectedVariables: ["counter"],
            actualVariables: ["counter"],
            variables: [:],
            expectedActions: [],
            actualActions: [],
            actions: [:]
        )

        let comparison = exactFiniteTLCGraph(expected: complete, actual: partial, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
        #expect(comparison.differences.contains { $0.category == .outcome })
    }

    @Test("many-to-one variable mappings are reported instead of remapping")
    func rejectsDuplicateVariableTargets() throws {
        let expectedState = CanonicalState(bindings: [
            "first": .integer(1),
            "second": .integer(2)
        ])
        let actualState = CanonicalState(bindings: ["shared": .integer(1)])
        let expectedGraph = try CanonicalGraph(
            initialStates: [expectedState],
            states: [expectedState],
            edges: []
        )
        let actualGraph = try CanonicalGraph(
            initialStates: [actualState],
            states: [actualState],
            edges: []
        )
        let expected = try CanonicalRun(
            graph: expectedGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let actual = try CanonicalRun(
            graph: actualGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let mapping = ObservableNameMapping(
            expectedVariables: ["first", "second"],
            actualVariables: ["shared"],
            variables: ["first": "shared", "second": "shared"],
            expectedActions: [],
            actualActions: [],
            actions: [:]
        )

        let comparison = exactFiniteTLCGraph(expected: expected, actual: actual, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
    }

    @Test("many-to-one action mappings are reported instead of remapping")
    func rejectsDuplicateActionTargets() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let expectedGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [
                .init(source: first.key, action: "advance", target: second.key),
                .init(source: first.key, action: "reset", target: second.key)
            ]
        )
        let actualGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "step", target: second.key)]
        )
        let expected = try CanonicalRun(
            graph: expectedGraph,
            observableActions: ["advance", "reset"],
            outcome: .exhaustiveSuccess
        )
        let actual = try CanonicalRun(
            graph: actualGraph,
            observableActions: ["step"],
            outcome: .exhaustiveSuccess
        )
        let mapping = ObservableNameMapping(
            expectedVariables: ["counter"],
            actualVariables: ["counter"],
            variables: ["counter": "counter"],
            expectedActions: ["advance", "reset"],
            actualActions: ["step"],
            actions: ["advance": "step", "reset": "step"]
        )

        let comparison = exactFiniteTLCGraph(expected: expected, actual: actual, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
    }

    @Test("unknown schemas are rejected before canonical evidence exists")
    func rejectsUnknownSchema() {
        #expect(throws: CanonicalSchemaError.self) {
            try CanonicalSchema(validating: "swifttla.unknown")
        }
    }
}
