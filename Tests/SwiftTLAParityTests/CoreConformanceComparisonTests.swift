import Testing
import UpstreamParity

struct CoreConformanceComparisonTests {
    @Test("same state count with a changed edge is semantic non-conformance")
    func reportsCategorizedEdgeDifference() throws {
        let first = CanonicalStateV1(bindings: ["counter": .integer(1)])
        let second = CanonicalStateV1(bindings: ["counter": .integer(2)])
        let expectedGraph = try CanonicalGraphV1(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "advance", target: second.key)]
        )
        let actualGraph = try CanonicalGraphV1(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "reset", target: second.key)]
        )
        let expected = try CanonicalRunV1(graph: expectedGraph, observableActions: ["advance"], outcome: .exhaustiveSuccess)
        let actual = try CanonicalRunV1(graph: actualGraph, observableActions: ["reset"], outcome: .exhaustiveSuccess)

        let comparison = exactFiniteTLCGraphV1(expected: expected, actual: actual)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .edges })
        #expect(comparison.differences.contains { $0.category == .mapping })
        // Edge witnesses are selected in canonical sort order. The missing
        // upstream `advance` edge therefore precedes the extra `reset` edge.
        let edgeReport = try #require(comparison.failureReports.first { $0.whereItFailed.contains("action advance") })
        #expect(edgeReport.expected.contains("TLC permits this transition 1 time(s)."))
        #expect(edgeReport.actual.contains("SwiftTLA permits this transition 0 time(s)."))
        #expect(edgeReport.systemChange == "No graph or generated state machine was changed.")
        #expect(edgeReport.nextSafeAction.contains("advance"))
    }

    @Test("partial name mappings and incomplete outcomes cannot pass")
    func rejectsPartialMappingsAndIncompleteRuns() throws {
        let state = CanonicalStateV1(bindings: ["counter": .integer(1)])
        let graph = try CanonicalGraphV1(initialStates: [state], states: [state], edges: [])
        let complete = try CanonicalRunV1(graph: graph, observableActions: [], outcome: .exhaustiveSuccess)
        let partial = try CanonicalRunV1(graph: graph, observableActions: [], outcome: .incomplete(reason: "state limit"))
        let mapping = ObservableNameMappingV1(
            expectedVariables: ["counter"],
            actualVariables: ["counter"],
            variables: [:],
            expectedActions: [],
            actualActions: [],
            actions: [:]
        )

        let comparison = exactFiniteTLCGraphV1(expected: complete, actual: partial, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
        #expect(comparison.differences.contains { $0.category == .outcome })
    }

    @Test("many-to-one variable mappings are reported instead of remapping")
    func rejectsDuplicateVariableTargets() throws {
        let expectedState = CanonicalStateV1(bindings: [
            "first": .integer(1),
            "second": .integer(2)
        ])
        let actualState = CanonicalStateV1(bindings: ["shared": .integer(1)])
        let expectedGraph = try CanonicalGraphV1(
            initialStates: [expectedState],
            states: [expectedState],
            edges: []
        )
        let actualGraph = try CanonicalGraphV1(
            initialStates: [actualState],
            states: [actualState],
            edges: []
        )
        let expected = try CanonicalRunV1(
            graph: expectedGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let actual = try CanonicalRunV1(
            graph: actualGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let mapping = ObservableNameMappingV1(
            expectedVariables: ["first", "second"],
            actualVariables: ["shared"],
            variables: ["first": "shared", "second": "shared"],
            expectedActions: [],
            actualActions: [],
            actions: [:]
        )

        let comparison = exactFiniteTLCGraphV1(expected: expected, actual: actual, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
    }

    @Test("many-to-one action mappings are reported instead of remapping")
    func rejectsDuplicateActionTargets() throws {
        let first = CanonicalStateV1(bindings: ["counter": .integer(1)])
        let second = CanonicalStateV1(bindings: ["counter": .integer(2)])
        let expectedGraph = try CanonicalGraphV1(
            initialStates: [first],
            states: [first, second],
            edges: [
                .init(source: first.key, action: "advance", target: second.key),
                .init(source: first.key, action: "reset", target: second.key)
            ]
        )
        let actualGraph = try CanonicalGraphV1(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "step", target: second.key)]
        )
        let expected = try CanonicalRunV1(
            graph: expectedGraph,
            observableActions: ["advance", "reset"],
            outcome: .exhaustiveSuccess
        )
        let actual = try CanonicalRunV1(
            graph: actualGraph,
            observableActions: ["step"],
            outcome: .exhaustiveSuccess
        )
        let mapping = ObservableNameMappingV1(
            expectedVariables: ["counter"],
            actualVariables: ["counter"],
            variables: ["counter": "counter"],
            expectedActions: ["advance", "reset"],
            actualActions: ["step"],
            actions: ["advance": "step", "reset": "step"]
        )

        let comparison = exactFiniteTLCGraphV1(expected: expected, actual: actual, mapping: mapping)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .mapping })
    }

    @Test("unknown schemas are rejected before canonical evidence exists")
    func rejectsUnknownSchema() {
        #expect(throws: CanonicalSchemaErrorV1.self) {
            try CanonicalSchemaV1(validating: "swifttla.unknown")
        }
    }
}
