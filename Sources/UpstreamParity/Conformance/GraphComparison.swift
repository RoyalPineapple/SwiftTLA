import Foundation

package enum GraphDifferenceCategory: String, Codable, Hashable, Sendable {
    case observableNames
    case initialStates
    case states
    case edges
    case outcome
}

package enum GraphDifference: Equatable, Sendable {
    case observableNames(
        expectedVariables: Set<String>,
        actualVariables: Set<String>,
        expectedActions: Set<String>,
        actualActions: Set<String>
    )
    case initialStates(expected: Set<CanonicalStateKey>, actual: Set<CanonicalStateKey>)
    case states(expected: Set<CanonicalStateKey>, actual: Set<CanonicalStateKey>)
    case edges(expected: [CanonicalEdge: Int], actual: [CanonicalEdge: Int])
    case outcome(expected: CanonicalOutcome, actual: CanonicalOutcome)

    package var category: GraphDifferenceCategory {
        switch self {
        case .observableNames: .observableNames
        case .initialStates: .initialStates
        case .states: .states
        case .edges: .edges
        case .outcome: .outcome
        }
    }
}

package struct GraphComparison: Equatable, Sendable {
    package let differences: [GraphDifference]

    package init(differences: [GraphDifference]) {
        self.differences = differences
    }

    package var isConformant: Bool { differences.isEmpty }
}

package func compareFiniteGraphs(
    expected: CompletedGraphRun,
    actual: CompletedGraphRun
) -> GraphComparison {
    var differences: [GraphDifference] = []
    if expected.graph.variableNames != actual.graph.variableNames
        || expected.observableActions != actual.observableActions {
        differences.append(
            .observableNames(
                expectedVariables: expected.graph.variableNames,
                actualVariables: actual.graph.variableNames,
                expectedActions: expected.observableActions,
                actualActions: actual.observableActions
            )
        )
    }
    if expected.graph.initialStateKeys != actual.graph.initialStateKeys {
        differences.append(.initialStates(expected: expected.graph.initialStateKeys, actual: actual.graph.initialStateKeys))
    }
    if Set(expected.graph.states.keys) != Set(actual.graph.states.keys) {
        differences.append(.states(expected: Set(expected.graph.states.keys), actual: Set(actual.graph.states.keys)))
    }
    if expected.graph.edgeOccurrences != actual.graph.edgeOccurrences {
        differences.append(.edges(expected: expected.graph.edgeOccurrences, actual: actual.graph.edgeOccurrences))
    }
    if expected.outcome != actual.outcome || !expected.isPassEligible || !actual.isPassEligible {
        differences.append(.outcome(expected: expected.outcome, actual: actual.outcome))
    }
    return GraphComparison(differences: differences)
}

func graphDifferencesJSON(_ comparison: GraphComparison) -> [[String: Any]] {
    comparison.differences.map { difference in
        switch difference {
        case .observableNames(
            let expectedVariables,
            let actualVariables,
            let expectedActions,
            let actualActions
        ):
            [
                "category": difference.category.rawValue,
                "expected": [
                    "variables": expectedVariables.sorted(),
                    "actions": expectedActions.sorted()
                ],
                "actual": [
                    "variables": actualVariables.sorted(),
                    "actions": actualActions.sorted()
                ]
            ]
        case .initialStates(let expected, let actual), .states(let expected, let actual):
            [
                "category": difference.category.rawValue,
                "expected": expected.subtracting(actual).sorted().prefix(1).map(\.canonicalEncoding),
                "actual": actual.subtracting(expected).sorted().prefix(1).map(\.canonicalEncoding)
            ]
        case .edges(let expected, let actual):
            [
                "category": difference.category.rawValue,
                "expected": firstDifferentEdgeOccurrenceJSON(expected, actual),
                "actual": firstDifferentEdgeOccurrenceJSON(actual, expected)
            ]
        case .outcome(let expected, let actual):
            ["category": difference.category.rawValue, "expected": outcomeJSON(expected), "actual": outcomeJSON(actual)]
        }
    }
}

private func outcomeJSON(_ outcome: CanonicalOutcome) -> [String: String] {
    switch outcome {
    case .exhaustiveSuccess: ["kind": "exhaustiveSuccess"]
    case .invariantViolation(let message): ["kind": "invariantViolation", "message": message]
    case .deadlock(let state): ["kind": "deadlock", "state": state.canonicalEncoding]
    case .incomplete(let message): ["kind": "incomplete", "message": message]
    case .executionError(let message): ["kind": "executionError", "message": message]
    }
}

private func firstDifferentEdgeOccurrenceJSON(
    _ expected: [CanonicalEdge: Int], _ actual: [CanonicalEdge: Int]
) -> [[String: Any]] {
    guard let edge = Set(expected.keys).union(actual.keys).sorted().first(where: {
        expected[$0] != actual[$0]
    }), let count = expected[edge] else { return [] }
    return [["edge": edge.canonicalEncoding, "count": count]]
}
