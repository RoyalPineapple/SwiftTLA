public struct ObservableNameMapping: Hashable, Sendable {
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

public enum ConformanceDifferenceCategory: String, Hashable, Sendable {
    case mapping
    case initialStates
    case states
    case edges
    case observations
    case outcome
    case errors
    case traces
}

public enum ConformanceDifference: Equatable, Sendable {
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

    public var category: ConformanceDifferenceCategory {
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

public struct ExactFiniteTLCComparison: Equatable, Sendable {
    public let differences: [ConformanceDifference]

    public init(differences: [ConformanceDifference]) {
        self.differences = differences
    }

    public var isConformant: Bool { differences.isEmpty }
}

public func exactFiniteTLCGraph(
    expected: CanonicalRun,
    actual: CanonicalRun,
    mapping: ObservableNameMapping? = nil
) -> ExactFiniteTLCComparison {
    var differences: [ConformanceDifference] = []
    let normalizedActual: CanonicalRun

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

private func remap(_ run: CanonicalRun, with mapping: ObservableNameMapping) -> CanonicalRun {
    let actualToExpectedVariables = Dictionary(uniqueKeysWithValues: mapping.variables.map { ($0.value, $0.key) })
    let actualToExpectedActions = Dictionary(uniqueKeysWithValues: mapping.actions.map { ($0.value, $0.key) })
    let remappedStates = run.graph.states.values.map { state in
        CanonicalState(bindings: Dictionary(uniqueKeysWithValues: state.bindings.map {
            (actualToExpectedVariables[$0.key]!, $0.value)
        }))
    }
    let keyMap = Dictionary(uniqueKeysWithValues: run.graph.states.values.map { ($0.key, remapState($0, variables: actualToExpectedVariables).key) })
    let remappedInitialStates = run.graph.initialStateKeys.map { initialKey in
        let remappedKey = keyMap[initialKey]!
        return remappedStates.first { $0.key == remappedKey }!
    }
    let remappedEdges = run.graph.edgeOccurrences.flatMap { edge, count in
        Array(repeating: CanonicalEdge(
            source: keyMap[edge.source]!,
            action: actualToExpectedActions[edge.action]!,
            target: keyMap[edge.target]!
        ), count: count)
    }
    let remappedTraces = run.traces.map { trace in
        CanonicalTrace(
            id: trace.id,
            steps: trace.steps.map { step in
                CanonicalTraceStep(
                    state: keyMap[step.state]!,
                    action: actualToExpectedActions[step.action] ?? step.action
                )
            }
        )
    }

    do {
        let graph = try CanonicalGraph(
            initialStates: remappedInitialStates,
            states: remappedStates,
            edges: remappedEdges
        )
        return try CanonicalRun(
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
    _ state: CanonicalState,
    variables: [String: String]
) -> CanonicalState {
    CanonicalState(bindings: Dictionary(uniqueKeysWithValues: state.bindings.map { (variables[$0.key]!, $0.value) }))
}

private func remap(
    _ outcome: CanonicalOutcome,
    states: [CanonicalStateKey: CanonicalStateKey]
) -> CanonicalOutcome {
    switch outcome {
    case .deadlock(let state): return .deadlock(states[state]!)
    default: return outcome
    }
}
