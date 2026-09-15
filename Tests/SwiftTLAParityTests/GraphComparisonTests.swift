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
        let run = try GraphRun(
            isComplete: true,
            graph: graph,
            observableActions: ["advance"],
            outcome: .noViolation
        )

        let repeated = try GraphRun(
            isComplete: true,
            graph: CanonicalGraph(initialStates: [first], states: [first, second],
                edges: Array(repeating: CanonicalEdge(source: first.key, action: "advance", target: second.key), count: 100)),
            observableActions: ["advance"], outcome: .noViolation)
        let comparison = compareFiniteGraphs(tlc: repeated, swift: run)

        #expect(comparison.matches)
    }

    @Test("matching violations agree only after both complete graphs are available")
    func comparesCompleteNegativeRuns() throws {
        let state = CanonicalState(bindings: ["counter": .integer(0)])
        let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [])
        let outcomes: [GraphRunOutcome] = [
            .invariantViolation("Safe"), .refinementViolation("Refines"), .deadlock(state.key)
        ]
        for outcome in outcomes {
            let complete = try GraphRun(isComplete: true, graph: graph, observableActions: [], outcome: outcome)
            let partial = try GraphRun(isComplete: false, graph: graph, observableActions: [], outcome: outcome)
            #expect(complete.isComparable)
            #expect(compareFiniteGraphs(tlc: complete, swift: complete).matches)
            #expect(!compareFiniteGraphs(tlc: partial, swift: complete).matches)
            #expect(!compareFiniteGraphs(tlc: partial, swift: partial).matches)
            let different = try GraphRun(isComplete: true, graph: graph, observableActions: [],
                outcome: .invariantViolation("DifferentProperty"))
            #expect(!compareFiniteGraphs(tlc: different, swift: complete).matches)
        }
    }

    @Test("matching timeouts, decoding failures, and unavailable checks never establish agreement")
    func rejectsInconclusiveResults() throws {
        let state = CanonicalState(bindings: ["counter": .integer(0)])
        let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [])
        let outcomes: [GraphRunOutcome] = [
            .incomplete(reason: "timeout"), .executionError("undecodable output")
        ]
        for outcome in outcomes {
            let run = try GraphRun(isComplete: true, graph: graph, observableActions: [], outcome: outcome)
            #expect(!run.isComparable)
            #expect(!compareFiniteGraphs(tlc: run, swift: run).matches)
        }
        let truncated = try GraphRun(isComplete: false, graph: graph, observableActions: [], outcome: .noViolation)
        let comparison = compareFiniteGraphs(tlc: truncated, swift: truncated)
        #expect(comparison.differences == [.completion(tlc: false, swift: false)])
        #expect(comparison.failureReports.first?.whereItFailed == "finite graph completion")
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
        let tlc = try GraphRun(
            isComplete: true,
            graph: tlcGraph,
            observableActions: [],
            outcome: .noViolation
        )
        let swift = try GraphRun(
            isComplete: true,
            graph: swiftGraph,
            observableActions: [],
            outcome: .noViolation
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
        let tlc = try GraphRun(isComplete: true, graph: tlcGraph, observableActions: ["advance"], outcome: .noViolation)
        let swift = try GraphRun(isComplete: true, graph: swiftGraph, observableActions: ["reset"], outcome: .noViolation)

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
        let complete = try GraphRun(isComplete: true, graph: graph, observableActions: [], outcome: .noViolation)
        let partial = try GraphRun(isComplete: false, graph: graph, observableActions: [], outcome: .incomplete(reason: "state limit"))
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
        let tlc = try GraphRun(
            isComplete: true,
            graph: CanonicalGraph(initialStates: [tlcState], states: [tlcState], edges: []),
            observableActions: [],
            outcome: .noViolation
        )
        let swift = try GraphRun(
            isComplete: true,
            graph: CanonicalGraph(initialStates: [swiftState], states: [swiftState], edges: []),
            observableActions: [],
            outcome: .noViolation
        )

        #expect(compareFiniteGraphs(tlc: tlc, swift: swift).matches)
    }

}
