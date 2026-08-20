/// Explores every reachable state of a TLA+ specification (plain BFS).
///
/// Lifecycle self-proof lives in `TLASpec.bfsChecker` / `@TLAModel BFSChecker`
/// and composition APIs — not as a decorative controller inside this loop.
public struct ModelChecker {
    public let spec: TLASpec
    /// Present when this checker entered through the validated compiler gate.
    private let compiledSpecification: CompiledSpecification
    public var compilation: CompiledSpecification? { compiledSpecification }
    public let maxStates: Int
    public let permutationProductBudget: Int

    init(spec: TLASpec, maxStates: Int = 100_000, permutationProductBudget: Int = 100_000) throws {
        self.init(
            compilation: try spec.compile(),
            maxStates: maxStates,
            permutationProductBudget: permutationProductBudget
        )
    }

    public init(compilation: CompiledSpecification, maxStates: Int = 100_000, permutationProductBudget: Int = 100_000) {
        self.spec = compilation.spec
        self.compiledSpecification = compilation
        self.maxStates = maxStates
        self.permutationProductBudget = permutationProductBudget
    }

    public func check() throws -> CheckResult {
        do {
            return try explore().result
        } catch {
            guard !spec.symmetricCollections.isEmpty else { throw error }
            return bounded(.error(String(describing: error)))
        }
    }
    public func exploreGraph() throws -> StateGraph { try explore().graph }

    public func explore() throws -> ModelExplorationResult { try runExploration() }

    public func checkLiveness() throws -> CheckResult {
        do {
            let exploration = try explore()
            guard case .ok = exploration.result.underlyingOutcome else { return exploration.result }
            guard !self.spec.temporalProperties.isEmpty else { return exploration.result }

            let graph = exploration.graph
            let lc = LivenessChecker(graph: graph)
            for property in self.spec.temporalProperties {
                let result = lc.analyze(
                    property.expr,
                    fairness: self.spec.fairness,
                    actions: self.spec.actions,
                    initialStateIDs: exploration.initialStateIDs,
                    isComplete: exploration.isComplete
                )
                switch result.status {
                case .satisfied:
                    continue
                case .violated:
                    return bounded(.livenessViolated("\(property.name): \(result.reason.rawValue)"))
                case .unavailable:
                    return bounded(.error("Liveness unavailable: \(result.diagnostic ?? result.reason.rawValue)"))
                }
            }
            return bounded(.ok(statesCount: exploration.graph.states.count))
        } catch {
            guard !spec.symmetricCollections.isEmpty else { throw error }
            return bounded(.error(String(describing: error)))
        }
    }

    /// Compose checker lifecycle ⋊ user and explore (bootstrap entry point).
    public static func compose(_ checker: TLASpec, _ user: TLASpec) throws -> ModelChecker {
        ModelChecker(compilation: try checker.extending(user).compile())
    }

    public static func checkComposed(
        checker: TLASpec = .bfsChecker(maxStates: 20),
        user: TLASpec,
        maxStates: Int = 10_000
    ) throws -> CheckResult {
        try compose(checker, user).check()
    }

    private func runExploration() throws -> ModelExplorationResult {
        if let validationError = validateSymmetricCollections() {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error(validationError.description))
            )
        }
        let runtime = CompiledRuntime(compilation: compiledSpecification)
        let initialStates = try runtime.initialStates()
        guard !initialStates.isEmpty else {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error("No initial states"))
            )
        }

        guard try runtime.assumeHolds(in: initialStates[0]) else {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error("ASSUME failed"))
            )
        }

        let exploration = try compiledBFS(
            runtime: runtime,
            seeds: initialStates,
            layout: compiledSpecification.layout,
            checkDeadlock: self.spec.checkDeadlock,
            specificationName: self.spec.name,
            maxStates: self.maxStates
        )
        return ModelExplorationResult(
            graph: exploration.graph,
            initialStateIDs: exploration.initialStateIDs,
            result: bounded(exploration.result)
        )
    }


    private func emptyExploration(
        _ specification: TLASpec,
        variableNames: [String],
        result: CheckResult
    ) -> ModelExplorationResult {
        ModelExplorationResult(
            graph: StateGraph(
                specName: specification.name,
                variableNames: variableNames,
                transitions: [:],
                states: [:]
            ),
            initialStateIDs: [],
            result: result
        )
    }

    private func bounded(_ outcome: CheckResult) -> CheckResult {
        let scopes = spec.symmetricCollections.map {
            SymmetricCollectionScope(collectionName: $0.name, verificationScope: $0.verificationScope)
        }
        return scopes.isEmpty ? outcome : .bounded(scopes: scopes, outcome: outcome)
    }

    private func validateSymmetricCollections() -> SymmetricCollectionValidationError? {
        spec.symmetricCollectionValidationError(
            permutationProductBudget: permutationProductBudget
        )
    }
}

private func compiledBFS(
    runtime: CompiledRuntime,
    seeds: [FormalState],
    layout: CompiledLayout,
    checkDeadlock: Bool,
    specificationName: String,
    maxStates: Int
) throws -> ModelExplorationResult {
    var queue: [FormalState] = []
    var stateToID: [FormalState: StateGraph.StateID] = [:]
    var idToState: [StateGraph.StateID: FormalState] = [:]
    var initialStateIDs: [StateGraph.StateID] = []
    var transitions: [StateGraph.StateID: [StateGraph.Transition]] = [:]
    var predecessors: [FormalState: (FormalState, String)] = [:]
    var nextID = 0

    func projected(_ state: FormalState) throws -> [String: TLAValue] {
        try state.projected(using: layout)
    }

    func graph() throws -> StateGraph {
        var states: [StateGraph.StateID: [String: TLAValue]] = [:]
        for (id, state) in idToState {
            states[id] = try projected(state)
        }
        return StateGraph(
            specName: specificationName,
            variableNames: layout.variables.map(\.declaration.name),
            transitions: transitions,
            states: states
        )
    }

    func trace(to final: FormalState, initial: FormalState) throws -> [TraceStep] {
        var steps: [(FormalState, String)] = []
        var current = final
        while let predecessor = predecessors[current] {
            steps.append((current, predecessor.1))
            current = predecessor.0
        }
        return try [TraceStep(state: projected(initial), action: "init")]
            + steps.reversed().map { try TraceStep(state: projected($0.0), action: $0.1) }
    }

    for seed in seeds {
        let key = runtime.canonicalState(seed)
        guard stateToID[key] == nil else { continue }
        let id = StateGraph.StateID(nextID)
        stateToID[key] = id
        idToState[id] = seed
        queue.append(seed)
        initialStateIDs.append(id)
        nextID += 1
    }

    var head = 0
    var processed = 0
    while head < queue.count {
        guard processed < maxStates else {
            return .init(
                graph: try graph(),
                initialStateIDs: initialStateIDs,
                result: .depthExceeded(statesCount: processed, limit: maxStates)
            )
        }
        let current = queue[head]
        head += 1
        processed += 1
        let key = runtime.canonicalState(current)
        guard let currentID = stateToID[key] else { continue }

        for invariant in runtime.compilation.model.invariants {
            guard try runtime.invariantHolds(invariant, in: current) else {
                return .init(
                    graph: try graph(),
                    initialStateIDs: initialStateIDs,
                    result: .invariantViolated(
                        invariant: invariant.name,
                        state: try projected(current),
                        trace: try trace(to: current, initial: queue[0])
                    )
                )
            }
        }

        let successors = try runtime.successors(from: current)
        if checkDeadlock && successors.isEmpty {
            return .init(
                graph: try graph(),
                initialStateIDs: initialStateIDs,
                result: .deadlocked(state: try projected(current))
            )
        }

        for successor in successors {
            let successorKey = runtime.canonicalState(successor.state)
            let targetID: StateGraph.StateID
            if let existing = stateToID[successorKey] {
                targetID = existing
            } else {
                targetID = StateGraph.StateID(nextID)
                stateToID[successorKey] = targetID
                idToState[targetID] = successor.state
                let actionName = layout.actions[successor.action.ordinal].declaration.name
                predecessors[successor.state] = (current, TLAActionInvocation(name: actionName, arguments: successor.arguments).description)
                queue.append(successor.state)
                nextID += 1
            }
            let actionName = layout.actions[successor.action.ordinal].declaration.name
            transitions[currentID, default: []].append(
                .init(
                    label: .init(.init(name: actionName, arguments: successor.arguments)),
                    target: targetID
                )
            )
        }
    }

    return .init(
        graph: try graph(),
        initialStateIDs: initialStateIDs,
        result: .ok(statesCount: processed)
    )
}

// MARK: - Results

/// The class of a model-checking result that needs an engineer's attention.
/// This is deliberately a domain enum rather than a Boolean or a generic
/// error string so tooling can present the failed formal concept directly.
public enum ModelCheckingFailureKind: String, Sendable, Equatable {
    case invariantViolated
    case deadlock
    case stateLimit
    case liveness
    case assumption
    case initialState
    case evaluation
}

/// One safely projected state in a counterexample trace.
public struct ModelTraceEvidence: Sendable, Equatable, CustomStringConvertible {
    public let action: String
    public let state: TLAStateProjectionResult

    package init(action: String, formalState: [String: TLAValue]) {
        self.action = action
        do {
            self.state = .projected(try .init(formalValues: formalState))
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            self.state = .unavailable(diagnostic)
        } catch {
            self.state = .unavailable(.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            ))
        }
    }

    public var description: String {
        switch state {
        case .projected(let projection): "[\(action)] \(projection)"
        case .unavailable(let diagnostic): "[\(action)] state unavailable: \(diagnostic)"
        }
    }
}

/// Inspection-ready evidence for a model-checking failure.
///
/// This companion is the public diagnostic boundary: it retains the named formal
/// property, the failing state, counterexample trace when there is one, the
/// expected condition, actual result, mutation outcome, and recovery step.
public struct ModelCheckingDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let kind: ModelCheckingFailureKind
    public let subject: String?
    public let expected: String
    public let actual: String
    public let state: TLAStateProjectionResult?
    public let trace: [ModelTraceEvidence]
    public let stateCommitted: Bool
    public let nextSafeAction: String

    public init(
        kind: ModelCheckingFailureKind,
        subject: String? = nil,
        expected: String,
        actual: String,
        state: TLAStateProjectionResult? = nil,
        trace: [ModelTraceEvidence] = [],
        stateCommitted: Bool = false,
        nextSafeAction: String
    ) {
        self.kind = kind
        self.subject = subject
        self.expected = expected
        self.actual = actual
        self.state = state
        self.trace = trace
        self.stateCommitted = stateCommitted
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        let label = subject.map { " \($0)" } ?? ""
        let stateText: String
        if let state {
            switch state {
            case .projected(let projection): stateText = " State: \(projection)."
            case .unavailable(let projectionError): stateText = " State could not be projected: \(projectionError)."
            }
        } else {
            stateText = ""
        }
        let traceText = trace.isEmpty ? "" : " Trace: " + trace.map(\.description).joined(separator: " → ") + "."
        return "\(kind.rawValue)\(label): expected \(expected); found \(actual).\(stateText)\(traceText) State was \(stateCommitted ? "committed" : "not committed"). Next: \(nextSafeAction)"
    }
}

public indirect enum CheckResult: CustomStringConvertible {
    case ok(statesCount: Int)
    case invariantViolated(invariant: String, state: [String: TLAValue], trace: [TraceStep])
    case depthExceeded(statesCount: Int, limit: Int)
    case deadlocked(state: [String: TLAValue])
    case livenessViolated(String)
    case error(String)
    case bounded(scopes: [SymmetricCollectionScope], outcome: CheckResult)

    public var underlyingOutcome: CheckResult {
        if case .bounded(_, let outcome) = self { return outcome.underlyingOutcome }
        return self
    }

    public var boundedScopes: [SymmetricCollectionScope] {
        if case .bounded(let scopes, _) = self { return scopes }
        return []
    }

    /// The typed explanation of any non-success result. This preserves formal
    /// state and counterexample evidence without exposing the engine's raw
    /// string-keyed state map to application code.
    public var diagnostic: ModelCheckingDiagnostic? {
        func project(_ formalState: [String: TLAValue]) -> TLAStateProjectionResult {
            do {
                return .projected(try .init(formalValues: formalState))
            } catch let diagnostic as TLAStateProjectionDiagnostic {
                return .unavailable(diagnostic)
            } catch {
                return .unavailable(.projectionUnavailable(
                    path: "state",
                    reason: String(describing: error)
                ))
            }
        }

        switch self {
        case .ok:
            return nil
        case .invariantViolated(let invariant, let state, let trace):
            return .init(
                kind: .invariantViolated,
                subject: invariant,
                expected: "the invariant to evaluate to true",
                actual: "false",
                state: project(state),
                trace: trace.map { .init(action: $0.action, formalState: $0.state) },
                nextSafeAction: "Inspect the final trace transition and revise the action guard, update, or invariant."
            )
        case .depthExceeded(let count, let limit):
            return .init(
                kind: .stateLimit,
                expected: "at most \(limit) explored states",
                actual: "\(count) states were needed before exploration completed",
                nextSafeAction: "Increase the finite exploration limit only after confirming the model bounds are intentional."
            )
        case .deadlocked(let state):
            return .init(
                kind: .deadlock,
                expected: "at least one enabled action",
                actual: "no action produced a successor",
                state: project(state),
                nextSafeAction: "Inspect the guards and explicit unchanged clauses for this state."
            )
        case .livenessViolated(let message):
            return .init(
                kind: .liveness,
                expected: "the declared temporal property to hold",
                actual: message,
                nextSafeAction: "Inspect the lasso or fairness diagnostic and revise the temporal property or transition relation."
            )
        case .error(let message):
            let kind: ModelCheckingFailureKind
            if message == "No initial states" { kind = .initialState }
            else if message == "ASSUME failed" { kind = .assumption }
            else { kind = .evaluation }
            return .init(
                kind: kind,
                expected: kind == .assumption ? "ASSUME to evaluate to true" : "a complete evaluable model-checking step",
                actual: message,
                nextSafeAction: "Inspect the named construct in the diagnostic and correct the model before rerunning verification."
            )
        case .bounded(_, let outcome):
            return outcome.diagnostic
        }
    }

    public var description: String {
        switch self {
        case .ok(let count): return "OK — explored " + String(count) + " state(s)"
        case .invariantViolated:
            return diagnostic?.description ?? "Invariant violation"
        case .depthExceeded(let count, let l):
            return "DEPTH EXCEEDED — explored " + String(count) + " state(s) before hitting limit of " + String(l)
        case .deadlocked, .livenessViolated, .error:
            return diagnostic?.description ?? "Verification diagnostic unavailable"
        case .bounded(let scopes, let outcome):
            return "BOUNDED VERIFICATION — " + scopes.map(\.description).joined(separator: "; ")
                + "; this does not prove larger populations\n" + outcome.description
        }
    }
}

public struct TraceStep: CustomStringConvertible {
    public let state: [String: TLAValue]
    public let action: String
    public var description: String { "[" + action + "] " + formatState(state) }
}

private func formatState(_ state: [String: TLAValue]) -> String {
    "{" + state.sorted { $0.key < $1.key }.map {
        $0.key + " = " + String(describing: $0.value)
    }.joined(separator: ", ") + "}"
}
