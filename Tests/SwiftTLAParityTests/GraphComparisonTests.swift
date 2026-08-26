import Testing
@testable import UpstreamParity

struct GraphComparisonTests {
    @Test("identical complete canonical runs compare exactly")
    func comparesIdenticalRuns() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let graph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "advance", target: second.key)]
        )
        let run = try CompletedGraphRun(
            graph: graph,
            observableActions: ["advance"],
            outcome: .exhaustiveSuccess
        )

        let comparison = compareFiniteGraphs(expected: run, actual: run)

        #expect(comparison.isConformant)
    }

    @Test("observable names must match exactly")
    func rejectsDifferentObservableNames() throws {
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
        let expected = try CompletedGraphRun(
            graph: expectedGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let actual = try CompletedGraphRun(
            graph: actualGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let comparison = compareFiniteGraphs(expected: expected, actual: actual)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .observableNames })
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
        let expected = try CompletedGraphRun(graph: expectedGraph, observableActions: ["advance"], outcome: .exhaustiveSuccess)
        let actual = try CompletedGraphRun(graph: actualGraph, observableActions: ["reset"], outcome: .exhaustiveSuccess)

        let comparison = compareFiniteGraphs(expected: expected, actual: actual)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .edges })
        #expect(comparison.differences.contains { $0.category == .observableNames })
        let edgeReport = try #require(comparison.failureReports.first { $0.whereItFailed.contains("action advance") })
        #expect(edgeReport.expected.contains("TLC permits this transition 1 time(s)."))
        #expect(edgeReport.actual.contains("SwiftTLA permits this transition 0 time(s)."))
        #expect(edgeReport.nextSafeAction.contains("advance"))
    }

    @Test("incomplete outcomes cannot pass")
    func rejectsIncompleteRuns() throws {
        let state = CanonicalState(bindings: ["counter": .integer(1)])
        let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [])
        let complete = try CompletedGraphRun(graph: graph, observableActions: [], outcome: .exhaustiveSuccess)
        let partial = try CompletedGraphRun(graph: graph, observableActions: [], outcome: .incomplete(reason: "state limit"))
        let comparison = compareFiniteGraphs(expected: complete, actual: partial)

        #expect(!comparison.isConformant)
        #expect(comparison.differences.contains { $0.category == .outcome })
    }

}
