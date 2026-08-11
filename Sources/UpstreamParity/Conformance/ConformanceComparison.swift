public struct ObservableNameMappingV1: Hashable, Sendable {
    public let expectedVariables: Set<String>
    public let actualVariables: Set<String>
    public let variables: [String: String]
    public let expectedActions: Set<String>
    public let actualActions: Set<String>
    public let actions: [String: String]

    public init(
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

    public var validationFailures: [String] {
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

public enum ConformanceDifferenceCategoryV1: String, Hashable, Sendable {
    case mapping
    case initialStates
    case states
    case edges
    case observations
    case outcome
    case errors
    case traces
}

public enum ConformanceDifferenceV1: Equatable, Sendable {
    case mapping([String])
    case initialStates(expected: Set<CanonicalStateKeyV1>, actual: Set<CanonicalStateKeyV1>)
    case states(expected: Set<CanonicalStateKeyV1>, actual: Set<CanonicalStateKeyV1>)
    case edges(expected: [CanonicalEdgeV1: Int], actual: [CanonicalEdgeV1: Int])
    case observations(
        expected: [CanonicalStateKeyV1: CanonicalStateObservationV1],
        actual: [CanonicalStateKeyV1: CanonicalStateObservationV1]
    )
    case outcome(expected: CanonicalOutcomeV1, actual: CanonicalOutcomeV1)
    case errors(expected: [CanonicalDiagnosticV1], actual: [CanonicalDiagnosticV1])
    case traces(expected: [CanonicalTraceV1], actual: [CanonicalTraceV1])

    public var category: ConformanceDifferenceCategoryV1 {
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

public struct ExactFiniteTLCComparisonV1: Equatable, Sendable {
    public let differences: [ConformanceDifferenceV1]

    public init(differences: [ConformanceDifferenceV1]) {
        self.differences = differences
    }

    public var isConformant: Bool { differences.isEmpty }
}

public func exactFiniteTLCGraphV1(
    expected: CanonicalRunV1,
    actual: CanonicalRunV1,
    mapping: ObservableNameMappingV1? = nil
) -> ExactFiniteTLCComparisonV1 {
    var differences: [ConformanceDifferenceV1] = []
    let normalizedActual: CanonicalRunV1

    if let mapping {
        let failures = mapping.validationFailures + declaredNameFailures(
            mapping: mapping,
            expected: expected,
            actual: actual
        )
        guard failures.isEmpty else {
            differences.append(.mapping(failures))
            return compare(expected: expected, actual: actual, leadingDifferences: differences)
        }
        normalizedActual = remap(actual, with: mapping)
    } else {
        normalizedActual = actual
        if expected.graph.variableNames != actual.graph.variableNames || expected.observableActions != actual.observableActions {
            differences.append(.mapping(["observable names differ without a declared total bijection"]))
        }
    }

    return compare(expected: expected, actual: normalizedActual, leadingDifferences: differences)
}

private func compare(
    expected: CanonicalRunV1,
    actual: CanonicalRunV1,
    leadingDifferences: [ConformanceDifferenceV1]
) -> ExactFiniteTLCComparisonV1 {
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
    return ExactFiniteTLCComparisonV1(differences: differences)
}

private func declaredNameFailures(
    mapping: ObservableNameMappingV1,
    expected: CanonicalRunV1,
    actual: CanonicalRunV1
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

private func remap(_ run: CanonicalRunV1, with mapping: ObservableNameMappingV1) -> CanonicalRunV1 {
    let actualToExpectedVariables = Dictionary(uniqueKeysWithValues: mapping.variables.map { ($0.value, $0.key) })
    let actualToExpectedActions = Dictionary(uniqueKeysWithValues: mapping.actions.map { ($0.value, $0.key) })
    let remappedStates = run.graph.states.values.map { state in
        CanonicalStateV1(bindings: Dictionary(uniqueKeysWithValues: state.bindings.map {
            (actualToExpectedVariables[$0.key]!, $0.value)
        }))
    }
    let keyMap = Dictionary(uniqueKeysWithValues: run.graph.states.values.map { ($0.key, remapState($0, variables: actualToExpectedVariables).key) })
    let remappedInitialStates = run.graph.initialStateKeys.map { initialKey in
        let remappedKey = keyMap[initialKey]!
        return remappedStates.first { $0.key == remappedKey }!
    }
    let remappedEdges = run.graph.edgeOccurrences.flatMap { edge, count in
        Array(repeating: CanonicalEdgeV1(
            source: keyMap[edge.source]!,
            action: actualToExpectedActions[edge.action]!,
            target: keyMap[edge.target]!
        ), count: count)
    }
    let remappedTraces = run.traces.map { trace in
        CanonicalTraceV1(
            id: trace.id,
            steps: trace.steps.map { step in
                CanonicalTraceStepV1(
                    state: keyMap[step.state]!,
                    action: actualToExpectedActions[step.action] ?? step.action
                )
            }
        )
    }

    do {
        let graph = try CanonicalGraphV1(
            initialStates: remappedInitialStates,
            states: remappedStates,
            edges: remappedEdges
        )
        return try CanonicalRunV1(
            schema: run.schema,
            graph: graph,
            observableActions: Set(run.observableActions.map { actualToExpectedActions[$0]! }),
            outcome: remap(run.outcome, states: keyMap),
            errors: run.errors,
            traces: remappedTraces
        )
    } catch {
        preconditionFailure("A validated total mapping produced invalid canonical evidence: \(error)")
    }
}

private func remapState(
    _ state: CanonicalStateV1,
    variables: [String: String]
) -> CanonicalStateV1 {
    CanonicalStateV1(bindings: Dictionary(uniqueKeysWithValues: state.bindings.map { (variables[$0.key]!, $0.value) }))
}

private func remap(
    _ outcome: CanonicalOutcomeV1,
    states: [CanonicalStateKeyV1: CanonicalStateKeyV1]
) -> CanonicalOutcomeV1 {
    switch outcome {
    case .deadlock(let state): return .deadlock(states[state]!)
    default: return outcome
    }
}
