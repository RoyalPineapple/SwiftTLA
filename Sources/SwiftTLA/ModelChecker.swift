/// Explores every reachable state of a TLA+ specification (plain BFS).
///
/// Lifecycle self-proof lives in `TLASpec.bfsChecker` / `@TLAModel BFSChecker`
/// and composition APIs — not as a decorative controller inside this loop.
public struct ModelChecker {
    public let spec: TLASpec
    public let maxStates: Int
    public let permutationProductBudget: Int

    public init(spec: TLASpec, maxStates: Int = 100_000, permutationProductBudget: Int = 100_000) {
        self.spec = spec
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
    public static func compose(_ checker: TLASpec, _ user: TLASpec) -> ModelChecker {
        ModelChecker(spec: checker.extending(user))
    }

    public static func checkComposed(
        checker: TLASpec = .bfsChecker(maxStates: 20),
        user: TLASpec,
        maxStates: Int = 10_000
    ) throws -> CheckResult {
        try compose(checker, user).check()
    }

    private typealias State = [String: TLAValue]

    private func runExploration() throws -> ModelExplorationResult {
        if let validationError = validateSymmetricCollections() {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error(validationError.description))
            )
        }
        let substituted = substituteConstants(self.spec)
        let variableNames = substituted.variables.map(\.name)
        let actions = substituted.actions.isEmpty
            ? [NamedAction(name: "", body: .guard_(.value(.bool(false))))]
            : substituted.actions

        let initialStates = computeInitialStates(substituted)
        guard !initialStates.isEmpty else {
            return emptyExploration(
                substituted,
                variableNames: variableNames,
                result: bounded(.error("No initial states"))
            )
        }

        guard try checkAssume(substituted, initial: initialStates[0]) else {
            return emptyExploration(
                substituted,
                variableNames: variableNames,
                result: bounded(.error("ASSUME failed"))
            )
        }

        let seeds = initialStates
        let exploration = try bfs(
            seeds: seeds,
            variableNames: variableNames,
            expand: buildExpander(
                actions,
                variableNames: variableNames,
                constraint: substituted.constraint,
                runtimeFuncs: substituted.runtimeFuncs,
                recursiveFuncs: substituted.recursiveFuncs
            ),
            evaluate: buildEvaluator(runtimeFuncs: substituted.runtimeFuncs, recursiveFuncs: substituted.recursiveFuncs),
            actions: actions,
            invariants: substituted.invariants,
            checkDeadlock: substituted.checkDeadlock,
            specificationName: substituted.name,
            maxStates: self.maxStates,
            symmetrySets: substituted.symmetrySets,
            symmetryGroups: substituted.symmetryGroups,
            symmetricCollections: substituted.symmetricCollections
        )
        return ModelExplorationResult(
            graph: exploration.graph,
            initialStateIDs: exploration.initialStateIDs,
            result: bounded(exploration.result)
        )
    }

    private func buildExpander(
        _ actions: [NamedAction],
        variableNames: [String],
        constraint: StateExpr? = nil,
        runtimeFuncs: [String: StateExpr.RuntimeFunc] = [:],
        recursiveFuncs: [RecursiveFunc] = []
    ) -> (State) throws -> [(StateGraph.TransitionLabel, State)] {
        { state in
            var result: [(StateGraph.TransitionLabel, State)] = []
            for action in actions {
                do {
                    for variant in actionInvocations(action) {
                        let successors = try ActionEnumerator.enumerate(
                            variant.body, from: state, varNames: variableNames
                        )
                        let label = StateGraph.TransitionLabel(variant.invocation)
                        result.append(contentsOf: successors.map { (label, $0) })
                    }
                } catch {
                    throw CheckerEvalError.action(action.name, error)
                }
            }
            if let c = constraint {
                result = try result.filter {
                    try c.evaluateBool(in: $0.1, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs)
                }
            }
            return result
        }
    }

    private func buildEvaluator(runtimeFuncs: [String: StateExpr.RuntimeFunc] = [:], recursiveFuncs: [RecursiveFunc] = []) -> (StateExpr, State) throws -> Bool {
        { expression, state in try expression.evaluateBool(in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs) }
    }

    private func checkAssume(_ specification: TLASpec, initial: State) throws -> Bool {
        guard let assume = specification.assume else { return true }
        return try assume.evaluateBool(in: initial, runtimeFuncs: specification.runtimeFuncs, recursiveFuncs: specification.recursiveFuncs)
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

// MARK: - Plain BFS

private typealias State = [String: TLAValue]

private enum CheckerEvalError: Error, CustomStringConvertible {
    case action(String, Error)
    case invariant(String, Error)
    case enabled(String, Error)

    var description: String {
        switch self {
        case .action(let n, let e): return "Action '\(n)': \(e)"
        case .invariant(let n, let e): return "Invariant '\(n)': \(e)"
        case .enabled(let n, let e): return "ENABLED('\(n)'): \(e)"
        }
    }
}

private func bfs(
    seeds: [State],
    variableNames: [String],
    expand: (State) throws -> [(StateGraph.TransitionLabel, State)],
    evaluate: (StateExpr, State) throws -> Bool,
    actions: [NamedAction],
    invariants: [NamedInvariant],
    checkDeadlock: Bool,
    specificationName: String,
    maxStates: Int,
    symmetrySets: [SymmetrySet] = [],
    symmetryGroups: [SymmetryVariableGroup] = [],
    symmetricCollections: [SymmetricCollectionDecl] = []
) throws -> ModelExplorationResult {
    let symmetricCollectionGroups = symmetricCollections.map {
        SymmetricCollectionPermutationGroup(members: $0.metadata.members)
    }

    func canonicalKey(_ state: State) -> State {
        var candidates = [state]
        for group in symmetricCollectionGroups {
            candidates = candidates.flatMap { candidate in
                group.mappings.map { applySymmetricMemberPermutation(candidate, mapping: $0) }
            }
        }
        let canonical = candidates.min { symmetricStateEncoding($0) < symmetricStateEncoding($1) } ?? state
        return symmetryGroups.reduce(symmetrySets.reduce(canonical) { $1.canonicalize($0) }) { $1.canonicalize($0) }
    }

    var queue: [State] = []
    var stateToID: [State: StateGraph.StateID] = [:]
    var idToState: [StateGraph.StateID: State] = [:]
    var visited = Set<State>()
    var nextID = 0
    var initialStateIDs: [StateGraph.StateID] = []

    for seed in seeds {
        let key = canonicalKey(seed)
        guard !visited.contains(key) else { continue }
        visited.insert(key)
        let id = StateGraph.StateID(nextID)
        stateToID[key] = id
        idToState[id] = seed
        queue.append(seed)
        initialStateIDs.append(id)
        nextID += 1
    }

    var transitions: [StateGraph.StateID: [StateGraph.Transition]] = [:]
    var predecessors: [State: (State, String)] = [:]
    var head = 0
    var processed = 0

    func graph() -> StateGraph {
        StateGraph(
            specName: specificationName,
            variableNames: variableNames,
            transitions: transitions,
            states: idToState
        )
    }

    while head < queue.count {
        guard processed < maxStates else {
            return ModelExplorationResult(
                graph: graph(),
                initialStateIDs: initialStateIDs,
                result: .depthExceeded(statesCount: processed, limit: maxStates)
            )
        }

        let current = queue[head]
        head += 1
        processed += 1

        guard let currentID = stateToID[canonicalKey(current)] else { continue }

        let enabled: State
        do {
            enabled = try enabledState(current, actions: actions, variableNames: variableNames)
        } catch {
            return ModelExplorationResult(
                graph: graph(),
                initialStateIDs: initialStateIDs,
                result: .error(String(describing: error))
            )
        }

        for invariant in invariants {
            let holds: Bool
            do {
                holds = try evaluate(invariant.body, enabled)
            } catch {
                return ModelExplorationResult(
                    graph: graph(),
                    initialStateIDs: initialStateIDs,
                    result: .error("Invariant '\(invariant.name)': \(error)")
                )
            }
            if !holds {
                let trace = buildTrace(
                    to: current,
                    predecessors: predecessors,
                    initial: queue.isEmpty ? current : queue[0]
                )
                return ModelExplorationResult(
                    graph: graph(),
                    initialStateIDs: initialStateIDs,
                    result: .invariantViolated(
                        invariant: invariant.name,
                        state: current,
                        trace: trace
                    )
                )
            }
        }

        let successors: [(StateGraph.TransitionLabel, State)]
        do {
            successors = try expand(current)
        } catch {
            return ModelExplorationResult(
                graph: graph(),
                initialStateIDs: initialStateIDs,
                result: .error(String(describing: error))
            )
        }

        if checkDeadlock && successors.isEmpty {
            return ModelExplorationResult(
                graph: graph(),
                initialStateIDs: initialStateIDs,
                result: .deadlocked(state: current)
            )
        }

        for (successorLabel, successorState) in successors {
            let key = canonicalKey(successorState)
            let targetID: StateGraph.StateID
            if let existing = stateToID[key] {
                targetID = existing
            } else {
                targetID = StateGraph.StateID(nextID)
                stateToID[key] = targetID
                idToState[targetID] = successorState
                predecessors[successorState] = (current, successorLabel.description)
                queue.append(successorState)
                visited.insert(key)
                nextID += 1
            }
            transitions[currentID, default: []] += [
                StateGraph.Transition(label: successorLabel, target: targetID)
            ]
        }
    }

    return ModelExplorationResult(
        graph: graph(),
        initialStateIDs: initialStateIDs,
        result: .ok(statesCount: processed)
    )
}

private func enabledState(
    _ state: State,
    actions: [NamedAction],
    variableNames: [String]
) throws -> State {
    var result = state
    for action in actions where !action.name.isEmpty {
        do {
            let enabled = try actionInvocations(action).contains { variant in
                if try !ActionEnumerator.enumerate(variant.body, from: state, varNames: variableNames).isEmpty {
                    return true
                }
                return false
            }
            result["_enabled_" + action.name] = .bool(enabled)
        } catch {
            throw CheckerEvalError.enabled(action.name, error)
        }
    }
    return result
}

private func buildTrace(
    to final: State,
    predecessors: [State: (State, String)],
    initial: State
) -> [TraceStep] {
    func loop(_ current: State, _ accumulated: [(State, String)]) -> [(State, String)] {
        guard let (predecessor, action) = predecessors[current] else { return accumulated }
        return loop(predecessor, [(current, action)] + accumulated)
    }
    return [TraceStep(state: initial, action: "init")]
        + loop(final, []).map { TraceStep(state: $0.0, action: $0.1) }
}

// MARK: - Results

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

    public var description: String {
        switch self {
        case .ok(let count): return "OK — explored " + String(count) + " state(s)"
        case .invariantViolated(let inv, _, let trace):
            let t = trace.enumerated().map {
                "  " + String($0.offset) + ". [" + $0.element.action + "] " + formatState($0.element.state)
            }
            return "INVARIANT VIOLATED: " + inv + "\n" + t.joined(separator: "\n")
        case .depthExceeded(let count, let l):
            return "DEPTH EXCEEDED — explored " + String(count) + " state(s) before hitting limit of " + String(l)
        case .deadlocked(let s): return "DEADLOCK detected at " + formatState(s)
        case .livenessViolated(let msg): return "LIVENESS VIOLATED: " + msg
        case .error(let message): return "ERROR: " + message
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
