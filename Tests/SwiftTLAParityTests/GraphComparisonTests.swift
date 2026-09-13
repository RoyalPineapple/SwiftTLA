import Testing
@testable import UpstreamParity

struct GraphComparisonTests {
    @Test("complete transition relations compare exactly despite repeated existential witnesses")
    func comparesRelationsIndependentlyOfWitnessCounts() throws {
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

        let repeated = try CompletedGraphRun(
            graph: CanonicalGraph(initialStates: [first], states: [first, second],
                edges: Array(repeating: CanonicalEdge(source: first.key, action: "advance", target: second.key), count: 100)),
            observableActions: ["advance"], outcome: .exhaustiveSuccess)
        let comparison = compareFiniteGraphs(tlc: repeated, swift: run)

        #expect(comparison.matches)
    }

    @Test("observable names must match exactly")
    func rejectsDifferentObservableNames() throws {
        let tlcState = CanonicalState(bindings: ["counter": .integer(1)])
        let swiftState = CanonicalState(bindings: ["swiftCounter": .integer(1)])
        let tlcGraph = try CanonicalGraph(
            initialStates: [tlcState],
            states: [tlcState],
            edges: []
        )
        let swiftGraph = try CanonicalGraph(
            initialStates: [swiftState],
            states: [swiftState],
            edges: []
        )
        let tlc = try CompletedGraphRun(
            graph: tlcGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let swift = try CompletedGraphRun(
            graph: swiftGraph,
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let comparison = compareFiniteGraphs(tlc: tlc, swift: swift)

        #expect(comparison.matches == false)
        #expect(comparison.differences.contains { if case .observableNames = $0 { true } else { false } })
    }

    @Test("same state count with a changed edge is semantic non-conformance")
    func reportsCategorizedEdgeDifference() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let tlcGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "advance", target: second.key)]
        )
        let swiftGraph = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [.init(source: first.key, action: "reset", target: second.key)]
        )
        let tlc = try CompletedGraphRun(graph: tlcGraph, observableActions: ["advance"], outcome: .exhaustiveSuccess)
        let swift = try CompletedGraphRun(graph: swiftGraph, observableActions: ["reset"], outcome: .exhaustiveSuccess)

        let comparison = compareFiniteGraphs(tlc: tlc, swift: swift)

        #expect(comparison.matches == false)
        #expect(comparison.differences.contains { if case .edges = $0 { true } else { false } })
        #expect(comparison.differences.contains { if case .observableNames = $0 { true } else { false } })
        let edgeReport = try #require(comparison.failureReports.first { $0.whereItFailed.contains("action advance") })
        #expect(edgeReport.expected.contains("TLC permits this transition."))
        #expect(edgeReport.actual.contains("SwiftTLA does not permit this transition."))
        #expect(edgeReport.nextSafeAction.contains("advance"))
    }

    @Test("incomplete outcomes cannot pass")
    func rejectsIncompleteRuns() throws {
        let state = CanonicalState(bindings: ["counter": .integer(1)])
        let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [])
        let complete = try CompletedGraphRun(graph: graph, observableActions: [], outcome: .exhaustiveSuccess)
        let partial = try CompletedGraphRun(graph: graph, observableActions: [], outcome: .incomplete(reason: "state limit"))
        let comparison = compareFiniteGraphs(tlc: complete, swift: partial)

        #expect(comparison.matches == false)
        #expect(comparison.differences.contains { if case .outcome = $0 { true } else { false } })
    }

    @Test("TLC tuples match Swift sequence functions exactly")
    func comparesSequenceRepresentations() throws {
        let tlcState = CanonicalState(bindings: [
            "levels": .tuple([.integer(0), .integer(1)])
        ])
        let swiftState = CanonicalState(bindings: [
            "levels": try .function([
                .init(key: .integer(1), value: .integer(0)),
                .init(key: .integer(2), value: .integer(1))
            ])
        ])
        let tlc = try CompletedGraphRun(
            graph: CanonicalGraph(initialStates: [tlcState], states: [tlcState], edges: []),
            observableActions: [],
            outcome: .exhaustiveSuccess
        )
        let swift = try CompletedGraphRun(
            graph: CanonicalGraph(initialStates: [swiftState], states: [swiftState], edges: []),
            observableActions: [],
            outcome: .exhaustiveSuccess
        )

        #expect(compareFiniteGraphs(tlc: tlc, swift: swift).matches)
    }

}
