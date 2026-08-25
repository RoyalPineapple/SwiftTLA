import Foundation

package struct ObservableNameMapping: Hashable, Sendable {
    package let expectedVariables: Set<String>
    package let actualVariables: Set<String>
    package let variables: [String: String]
    package let expectedActions: Set<String>
    package let actualActions: Set<String>
    package let actions: [String: String]

    package init(
        expectedVariables: Set<String>,
        actualVariables: Set<String>,
        variables: [String: String],
        expectedActions: Set<String>,
        actualActions: Set<String>,
        actions: [String: String]
    ) {
        self.expectedVariables = expectedVariables
        self.actualVariables = actualVariables
        self.variables = variables
        self.expectedActions = expectedActions
        self.actualActions = actualActions
        self.actions = actions
    }

    package var validationFailures: [String] {
        var failures: [String] = []
        if expectedVariables.count != actualVariables.count
            || variables.count != expectedVariables.count
            || Set(variables.keys) != expectedVariables
            || Set(variables.values) != actualVariables {
            failures.append("variable mapping is not a total bijection")
        }
        if expectedActions.count != actualActions.count
            || actions.count != expectedActions.count
            || Set(actions.keys) != expectedActions
            || Set(actions.values) != actualActions {
            failures.append("action mapping is not a total bijection")
        }
        return failures
    }

}

package enum ConformanceDifferenceCategory: String, Codable, Hashable, Sendable {
    case mapping
    case initialStates
    case states
    case edges
    case observations
    case outcome
    case errors
    case traces
}

package enum ConformanceDifference: Equatable, Sendable {
    case mapping([String])
    case initialStates(expected: Set<CanonicalStateKey>, actual: Set<CanonicalStateKey>)
    case states(expected: Set<CanonicalStateKey>, actual: Set<CanonicalStateKey>)
    case edges(expected: [CanonicalEdge: Int], actual: [CanonicalEdge: Int])
    case observations(
        expected: [CanonicalStateKey: CanonicalStateObservation],
        actual: [CanonicalStateKey: CanonicalStateObservation]
    )
    case outcome(expected: CanonicalOutcome, actual: CanonicalOutcome)
    case errors(expected: [CanonicalDiagnostic], actual: [CanonicalDiagnostic])
    case traces(expected: [CanonicalTrace], actual: [CanonicalTrace])

    package var category: ConformanceDifferenceCategory {
        switch self {
        case .mapping: .mapping
        case .initialStates: .initialStates
        case .states: .states
        case .edges: .edges
        case .observations: .observations
        case .outcome: .outcome
        case .errors: .errors
        case .traces: .traces
        }
    }
}

package struct ExactFiniteTLCComparison: Equatable, Sendable {
    package let differences: [ConformanceDifference]

    package init(differences: [ConformanceDifference]) {
        self.differences = differences
    }

    package var isConformant: Bool { differences.isEmpty }
}

package func exactFiniteTLCGraph(
    expected: CanonicalRun,
    actual: CanonicalRun,
    mapping: ObservableNameMapping? = nil
) -> ExactFiniteTLCComparison {
    let inputs = normalizedComparisonInputs(expected: expected, actual: actual, mapping: mapping)
    return compare(expected: expected, actual: inputs.actual, leadingDifferences: inputs.differences)
}

private struct NormalizedComparisonInputs {
    let actual: CanonicalRun
    let differences: [ConformanceDifference]
}

private func normalizedComparisonInputs(
    expected: CanonicalRun,
    actual: CanonicalRun,
    mapping: ObservableNameMapping?
) -> NormalizedComparisonInputs {
    var differences: [ConformanceDifference] = []
    if let mapping {
        let failures = mapping.validationFailures + declaredNameFailures(
            mapping: mapping,
            expected: expected,
            actual: actual
        )
        guard failures.isEmpty else {
            return .init(actual: actual, differences: [.mapping(failures)])
        }
        guard let remapped = remap(actual, with: mapping) else {
            return .init(
                actual: actual,
                differences: [.mapping(["the declared mapping could not remap the canonical evidence"])]
            )
        }
        return .init(actual: remapped, differences: [])
    }
    if expected.graph.variableNames != actual.graph.variableNames || expected.observableActions != actual.observableActions {
        differences.append(.mapping(["observable names differ without a declared total bijection"]))
    }
    return .init(actual: actual, differences: differences)
}

private func compare(
    expected: CanonicalRun,
    actual: CanonicalRun,
    leadingDifferences: [ConformanceDifference]
) -> ExactFiniteTLCComparison {
    var differences = leadingDifferences
    if expected.graph.initialStateKeys != actual.graph.initialStateKeys {
        differences.append(.initialStates(expected: expected.graph.initialStateKeys, actual: actual.graph.initialStateKeys))
    }
    if Set(expected.graph.states.keys) != Set(actual.graph.states.keys) {
        differences.append(.states(expected: Set(expected.graph.states.keys), actual: Set(actual.graph.states.keys)))
    }
    if expected.graph.edgeOccurrences != actual.graph.edgeOccurrences {
        differences.append(.edges(expected: expected.graph.edgeOccurrences, actual: actual.graph.edgeOccurrences))
    }
    if expected.graph.observations != actual.graph.observations {
        differences.append(.observations(expected: expected.graph.observations, actual: actual.graph.observations))
    }
    if expected.outcome != actual.outcome || !expected.isPassEligible || !actual.isPassEligible {
        differences.append(.outcome(expected: expected.outcome, actual: actual.outcome))
    }
    if expected.errors != actual.errors {
        differences.append(.errors(expected: expected.errors, actual: actual.errors))
    }
    if expected.traces != actual.traces {
        differences.append(.traces(expected: expected.traces, actual: actual.traces))
    }
    return ExactFiniteTLCComparison(differences: differences)
}

private func declaredNameFailures(
    mapping: ObservableNameMapping,
    expected: CanonicalRun,
    actual: CanonicalRun
) -> [String] {
    var failures: [String] = []
    if mapping.expectedVariables != expected.graph.variableNames || mapping.actualVariables != actual.graph.variableNames {
        failures.append("variable mapping declarations do not match the complete state bindings")
    }
    if mapping.expectedActions != expected.observableActions || mapping.actualActions != actual.observableActions {
        failures.append("action mapping declarations do not match the complete observable actions")
    }
    return failures
}

private func remap(_ run: CanonicalRun, with mapping: ObservableNameMapping) -> CanonicalRun? {
    let actualToExpectedVariables = Dictionary(uniqueKeysWithValues: mapping.variables.map { ($0.value, $0.key) })
    let actualToExpectedActions = Dictionary(uniqueKeysWithValues: mapping.actions.map { ($0.value, $0.key) })
    var remappedStates: [CanonicalState] = []
    var keyMap: [CanonicalStateKey: CanonicalStateKey] = [:]
    for state in run.graph.states.values {
        var bindings: [String: CanonicalValue] = [:]
        for (name, value) in state.bindings {
            guard let remappedName = actualToExpectedVariables[name] else { return nil }
            bindings[remappedName] = value
        }
        let remapped = CanonicalState(bindings: bindings)
        remappedStates.append(remapped)
        keyMap[state.key] = remapped.key
    }

    let statesByKey = Dictionary(uniqueKeysWithValues: remappedStates.map { ($0.key, $0) })
    let remappedInitialStates = run.graph.initialStateKeys.compactMap { initialKey -> CanonicalState? in
        guard let remappedKey = keyMap[initialKey] else { return nil }
        return statesByKey[remappedKey]
    }
    guard remappedInitialStates.count == run.graph.initialStateKeys.count else { return nil }

    var remappedEdges: [CanonicalEdge] = []
    for (edge, count) in run.graph.edgeOccurrences {
        guard let source = keyMap[edge.source],
              let action = actualToExpectedActions[edge.action],
              let target = keyMap[edge.target]
        else { return nil }
        remappedEdges += Array(repeating: .init(source: source, action: action, target: target), count: count)
    }
    let remappedTraces = run.traces.map { trace in
        CanonicalTrace(
            id: trace.id,
            steps: trace.steps.compactMap { step -> CanonicalTraceStep? in
                guard let state = keyMap[step.state] else { return nil }
                return CanonicalTraceStep(
                    state: state,
                    action: actualToExpectedActions[step.action] ?? step.action
                )
            }
        )
    }
    guard zip(run.traces, remappedTraces).allSatisfy({ original, remapped in
        original.steps.count == remapped.steps.count
    }) else { return nil }

    guard let graph = try? CanonicalGraph(
        initialStates: remappedInitialStates,
        states: remappedStates,
        edges: remappedEdges
    ) else { return nil }
    let observableActions = Set(run.observableActions.compactMap { actualToExpectedActions[$0] })
    guard observableActions.count == run.observableActions.count else { return nil }
    guard let outcome = remap(run.outcome, states: keyMap) else { return nil }
    return try? CanonicalRun(
        schema: run.schema,
        graph: graph,
        observableActions: observableActions,
        outcome: outcome,
        errors: run.errors,
        traces: remappedTraces
    )
}

private func remap(
    _ outcome: CanonicalOutcome,
    states: [CanonicalStateKey: CanonicalStateKey]
) -> CanonicalOutcome? {
    switch outcome {
    case .deadlock(let state):
        guard let remappedState = states[state] else { return nil }
        return .deadlock(remappedState)
    default: return outcome
    }
}

func comparisonDifferencesJSON(_ comparison: ExactFiniteTLCComparison) -> [[String: Any]] {
    comparison.differences.map { difference in
        switch difference {
        case .mapping(let messages):
            ["category": difference.category.rawValue, "expected": [], "actual": [], "details": messages]
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
        case .observations(let expected, let actual):
            [
                "category": difference.category.rawValue,
                "expected": firstDifferentObservationJSON(expected, actual),
                "actual": firstDifferentObservationJSON(actual, expected)
            ]
        case .outcome(let expected, let actual):
            ["category": difference.category.rawValue, "expected": outcomeJSON(expected), "actual": outcomeJSON(actual)]
        case .errors(let expected, let actual):
            [
                "category": difference.category.rawValue,
                "expected": expected.map { ["code": $0.code, "message": $0.message] },
                "actual": actual.map { ["code": $0.code, "message": $0.message] }
            ]
        case .traces(let expected, let actual):
            [
                "category": difference.category.rawValue,
                "expected": expected.map(traceJSON), "actual": actual.map(traceJSON)
            ]
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

private func traceJSON(_ trace: CanonicalTrace) -> [String: Any] {
    ["id": trace.id, "steps": trace.steps.map { ["state": $0.state.canonicalEncoding, "action": $0.action] }]
}

private func firstDifferentEdgeOccurrenceJSON(
    _ expected: [CanonicalEdge: Int], _ actual: [CanonicalEdge: Int]
) -> [[String: Any]] {
    guard let edge = Set(expected.keys).union(actual.keys).sorted().first(where: {
        expected[$0] != actual[$0]
    }), let count = expected[edge] else { return [] }
    return [["edge": edge.canonicalEncoding, "count": count]]
}

private func firstDifferentObservationJSON(
    _ expected: [CanonicalStateKey: CanonicalStateObservation],
    _ actual: [CanonicalStateKey: CanonicalStateObservation]
) -> [[String: Any]] {
    guard let state = Set(expected.keys).union(actual.keys).sorted().first(where: {
        expected[$0] != actual[$0]
    }), let observation = expected[state] else { return [] }
    return [[
        "state": state.canonicalEncoding,
        "enabledActions": observation.enabledActions.sorted(),
        "isTerminal": observation.isTerminal
    ]]
}
