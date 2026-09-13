import Foundation

package enum GraphDifference: Equatable, Sendable {
    case observableNames(
        tlcVariables: Set<String>,
        swiftVariables: Set<String>,
        tlcActions: Set<String>,
        swiftActions: Set<String>
    )
    case initialStates(tlc: Set<CanonicalStateKey>, swift: Set<CanonicalStateKey>)
    case states(tlc: Set<CanonicalStateKey>, swift: Set<CanonicalStateKey>)
    case edges(tlc: Set<CanonicalEdge>, swift: Set<CanonicalEdge>)
    case completion(tlc: Bool, swift: Bool)
    case outcome(tlc: GraphRunOutcome, swift: GraphRunOutcome)
}

package struct GraphComparison: Equatable, Sendable {
    package let differences: [GraphDifference]

    package init(differences: [GraphDifference]) {
        self.differences = differences
    }

    package var matches: Bool { differences.isEmpty }
}

package func compareFiniteGraphs(
    tlc: GraphRun,
    swift: GraphRun
) -> GraphComparison {
    var differences: [GraphDifference] = []
    if (tlc.graph.variableNames == swift.graph.variableNames) == false
        || (tlc.observableActions == swift.observableActions) == false {
        differences.append(
            .observableNames(
                tlcVariables: tlc.graph.variableNames,
                swiftVariables: swift.graph.variableNames,
                tlcActions: tlc.observableActions,
                swiftActions: swift.observableActions
            )
        )
    }
    if (tlc.graph.initialStateKeys == swift.graph.initialStateKeys) == false {
        differences.append(.initialStates(tlc: tlc.graph.initialStateKeys, swift: swift.graph.initialStateKeys))
    }
    if (Set(tlc.graph.states.keys) == Set(swift.graph.states.keys)) == false {
        differences.append(.states(tlc: Set(tlc.graph.states.keys), swift: Set(swift.graph.states.keys)))
    }
    if (tlc.graph.edges == swift.graph.edges) == false {
        differences.append(.edges(tlc: tlc.graph.edges, swift: swift.graph.edges))
    }
    if !tlc.isComplete || !swift.isComplete {
        differences.append(.completion(tlc: tlc.isComplete, swift: swift.isComplete))
    }
    if (tlc.outcome == swift.outcome) == false
        || !tlc.outcome.isConclusive || !swift.outcome.isConclusive {
        differences.append(.outcome(tlc: tlc.outcome, swift: swift.outcome))
    }
    return GraphComparison(differences: differences)
}

func graphDifferencesJSON(_ comparison: GraphComparison) -> [[String: Any]] {
    comparison.differences.map { difference in
        switch difference {
        case .observableNames(
            let tlcVariables,
            let swiftVariables,
            let tlcActions,
            let swiftActions
        ):
            [
                "kind": "observableNames",
                "tlc": [
                    "variables": tlcVariables.sorted(),
                    "actions": tlcActions.sorted()
                ],
                "swift": [
                    "variables": swiftVariables.sorted(),
                    "actions": swiftActions.sorted()
                ]
            ]
        case .initialStates(let tlc, let swift):
            [
                "kind": "initialStates",
                "tlc": tlc.subtracting(swift).min().map { [$0.canonicalEncoding] } ?? [],
                "swift": swift.subtracting(tlc).min().map { [$0.canonicalEncoding] } ?? []
            ]
        case .states(let tlc, let swift):
            [
                "kind": "states",
                "tlc": tlc.subtracting(swift).min().map { [$0.canonicalEncoding] } ?? [],
                "swift": swift.subtracting(tlc).min().map { [$0.canonicalEncoding] } ?? []
            ]
        case .edges(let tlc, let swift):
            [
                "kind": "edges",
                "tlc": tlc.subtracting(swift).min().map { [$0.canonicalEncoding] } ?? [],
                "swift": swift.subtracting(tlc).min().map { [$0.canonicalEncoding] } ?? []
            ]
        case .completion(let tlc, let swift):
            ["kind": "completion", "tlcComplete": tlc, "swiftComplete": swift]
        case .outcome(let tlc, let swift):
            [
                "kind": "outcome",
                "tlc": GraphRunRecords.outcomeRecord(tlc),
                "swift": GraphRunRecords.outcomeRecord(swift)
            ]
        }
    }
}
