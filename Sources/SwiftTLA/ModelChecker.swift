/// Explores every reachable state of a TLA+ specification.
///
/// Pure-functional BFS model checker.
/// The BFS loop drives CheckerController to track its lifecycle
/// (exploring → complete / violated / deadlocked).
/// Verified by CheckerSelfProofTests.
public struct ModelChecker {
    public let spec: TLASpec
    public let maxStates: Int

    public init(spec: TLASpec, maxStates: Int = 10_000) {
        self.spec = spec
        self.maxStates = maxStates
    }

    public func check() throws -> CheckResult { try explore().result }
    public func exploreGraph() throws -> StateGraph { try explore().graph }

    private typealias State = [String: TLAValue]

    fileprivate struct Exploration {
        let result: CheckResult
        let graph: StateGraph
    }

    private func explore() throws -> Exploration {
        let substituted = substituteConstants(self.spec)
        let variableNames = substituted.variables.map(\.name)
        let actions = substituted.actions.isEmpty
            ? [NamedAction(name: "", body: .guard_(.value(.bool(false))))]
            : substituted.actions

        let initialStates = computeInitialStates(substituted)
        let canonical = buildCanonicalizer(substituted.variables)
        let expand = buildExpander(actions, variableNames: variableNames)
        let evaluate = buildEvaluator()

        guard try checkAssume(substituted, initial: initialStates[0]) else {
            return emptyExploration(substituted, variableNames: variableNames, result: .error("ASSUME failed"))
        }

        let seeds = initialStates.enumerated().map { (StateGraph.StateID($0.offset), $0.element) }
        return bfs(
            seeds: seeds,
            variableNames: variableNames,
            canonical: canonical,
            expand: expand,
            evaluate: evaluate,
            actions: actions,
            invariants: substituted.invariants,
            checkDeadlock: substituted.checkDeadlock,
            specificationName: substituted.name,
            maxStates: self.maxStates
        )
    }

    // MARK: - Pure helpers

    private func computeInitialStates(_ specification: TLASpec) -> [State] {
        let base = Dictionary(uniqueKeysWithValues: specification.variables.map { ($0.name, $0.initial) })
        let nondeterministic = specification.variables.filter { v in
            // Only variables with an explicit initialSet (set via `in:` range)
            // are nondeterministic. Plain .set([...]) initial values are
            // concrete (e.g. q = {0} for a set-typed variable).
            guard v.initialSet != nil else { return false }
            if case .set = v.initial { return true }
            return false
        }
        return nondeterministic.reduce([base]) { states, variable in
            guard case .set(let values) = variable.initial else { return states }
            let sorted = TLAValue.sorted(values)
            return states.flatMap { state in sorted.map { state.merging([variable.name: $0]) { _, new in new } } }
        }
    }

    private func buildCanonicalizer(_ variables: [NamedVar]) -> (State) -> State {
        let symmetrySets: [SymmetrySet] = variables.compactMap { variable in
            guard case .set(let values) = variable.initial else { return nil }
            return SymmetrySet(variableName: variable.name, values: values)
        }
        return { state in symmetrySets.reduce(state) { $1.canonicalize($0) } }
    }

    private func buildExpander(_ actions: [NamedAction], variableNames: [String]) -> (State) -> [(String, State)] {
        { state in
            actions.flatMap { action -> [(String, State)] in
                guard let successors = try? ActionEnumerator.enumerate(action.body, from: state, varNames: variableNames) else { return [] }
                return successors.map { (action.name, $0) }
            }
        }
    }

    private func buildEvaluator() -> (StateExpr, State) -> Bool {
        { expression, state in (try? Evaluator.evaluateBool(expression, in: state)) ?? false }
    }

    private func checkAssume(_ specification: TLASpec, initial: State) throws -> Bool {
        guard let assume = specification.assume else { return true }
        return try Evaluator.evaluateBool(assume, in: initial)
    }

    private func emptyExploration(_ specification: TLASpec, variableNames: [String], result: CheckResult) -> Exploration {
        Exploration(result: result, graph: StateGraph(specName: specification.name, variableNames: variableNames, transitions: [:], states: [:]))
    }
}

// MARK: - Pure functional BFS

private typealias State = [String: TLAValue]

private func bfs(
    seeds: [(StateGraph.StateID, State)],
    variableNames: [String],
    canonical: (State) -> State,
    expand: (State) -> [(String, State)],
    evaluate: (StateExpr, State) -> Bool,
    actions: [NamedAction],
    invariants: [NamedInvariant],
    checkDeadlock: Bool,
    specificationName: String,
    maxStates: Int
) -> ModelChecker.Exploration {
    bfsLoop(
        queue: seeds.map(\.1),
        stateToID: Dictionary(seeds.map { (canonical($0.1), $0.0) }, uniquingKeysWith: { existing, _ in existing }),
        idToState: Dictionary(seeds.map { ($0.0, $0.1) }, uniquingKeysWith: { existing, _ in existing }),
        visited: Set(seeds.map { canonical($0.1) }),
        transitions: [:],
        predecessors: [:],
        nextID: seeds.count,
        maxStates: maxStates,
        actions: actions,
        variableNames: variableNames,
        canonical: canonical,
        expand: expand,
        evaluate: evaluate,
        invariants: invariants,
        checkDeadlock: checkDeadlock,
        specificationName: specificationName
    )
}

private func bfsLoop(
    queue: [State],
    stateToID: [State: StateGraph.StateID],
    idToState: [StateGraph.StateID: State],
    visited: Set<State>,
    transitions: [StateGraph.StateID: [StateGraph.Transition]],
    predecessors: [State: (State, String)],
    nextID: Int,
    maxStates: Int,
    actions: [NamedAction],
    variableNames: [String],
    canonical: (State) -> State,
    expand: (State) -> [(String, State)],
    evaluate: (StateExpr, State) -> Bool,
    invariants: [NamedInvariant],
    checkDeadlock: Bool,
    specificationName: String
) -> ModelChecker.Exploration {
    var currentQueue = queue
    var currentStateToID = stateToID
    var currentIDToState = idToState
    var currentVisited = visited
    var currentTransitions = transitions
    var currentPredecessors = predecessors
    var currentNextID = nextID
    var head = 0

    // CheckerController tracks the BFS lifecycle, bounded by maxStates
    var checker = CheckerController(phase: CheckerController.phaseExploring, processed: 0, queued: currentQueue.count, limit: maxStates)

    func graph() -> StateGraph {
        StateGraph(specName: specificationName, variableNames: variableNames, transitions: currentTransitions, states: currentIDToState)
    }

    while checker.isExploring {
        guard checker.processed < maxStates else {
            return ModelChecker.Exploration(result: .depthExceeded(statesCount: checker.processed, limit: maxStates), graph: graph())
        }
        guard head < currentQueue.count else {
            checker.apply(.complete)
            return ModelChecker.Exploration(result: .ok(statesCount: checker.processed), graph: graph())
        }

        let current = currentQueue[head]
        head += 1

        guard let currentID = currentStateToID[canonical(current)] else {
            checker.apply(.stepNoNew)
            continue
        }


        let enabled = enabledState(current, actions: actions, variableNames: variableNames)
        for invariant in invariants where !evaluate(invariant.body, enabled) {
            checker.apply(.violate)
            let trace = buildTrace(to: current, predecessors: currentPredecessors, initial: currentQueue.count > 0 ? currentQueue[0] : current)
            return ModelChecker.Exploration(result: .invariantViolated(invariant: invariant.name, state: current, trace: trace), graph: graph())
        }

        let successors = expand(current)
        if checkDeadlock && successors.isEmpty {
            checker.apply(.deadlock)
            return ModelChecker.Exploration(result: .deadlocked(state: current), graph: graph())
        }

        for (successorAction, successorState) in successors {
            let canonicalForm = canonical(successorState)
            if let targetID = currentStateToID[canonicalForm] {
                currentTransitions[currentID, default: []] += [StateGraph.Transition(action: successorAction, target: targetID)]
            }
        }

        let newStates = successors.filter { !currentVisited.contains(canonical($0.1)) }
        if newStates.isEmpty {
            checker.apply(.stepNoNew)
        } else {
            for successor in newStates {
                let canonicalForm = canonical(successor.1)
                let targetID = currentStateToID[canonicalForm] ?? StateGraph.StateID(currentNextID)
                currentTransitions[currentID, default: []] += [StateGraph.Transition(action: successor.0, target: targetID)]
                if currentStateToID[canonicalForm] != nil { continue }
                currentStateToID[canonicalForm] = StateGraph.StateID(currentNextID)
                currentIDToState[StateGraph.StateID(currentNextID)] = successor.1
                currentPredecessors[successor.1] = (current, successor.0)
                currentQueue.append(successor.1)
                currentVisited.insert(canonicalForm)
                currentNextID += 1
            }
            checker.apply(.stepDiscover)
        }
    }

    // Loop exited — only possible via checker.apply(.complete) when queue is empty
    return ModelChecker.Exploration(result: .ok(statesCount: checker.processed), graph: graph())
}

private func enabledState(_ state: State, actions: [NamedAction], variableNames: [String]) -> State {
    actions.filter { !$0.name.isEmpty }.reduce(state) { currentState, action in
        let isEnabled = (try? ActionEnumerator.enumerate(action.body, from: state, varNames: variableNames))?.isEmpty == false
        return currentState.merging(["_enabled_" + action.name: TLAValue.bool(isEnabled)]) { _, new in new }
    }
}

private func buildTrace(to final: State, predecessors: [State: (State, String)], initial: State) -> [TraceStep] {
    func loop(_ current: State, _ accumulated: [(State, String)]) -> [(State, String)] {
        guard let (predecessor, action) = predecessors[current] else { return accumulated }
        return loop(predecessor, [(current, action)] + accumulated)
    }
    return [TraceStep(state: initial, action: "init")] + loop(final, []).map { TraceStep(state: $0.0, action: $0.1) }
}

// MARK: - Results

public enum CheckResult: CustomStringConvertible {
    case ok(statesCount: Int)
    case invariantViolated(invariant: String, state: [String: TLAValue], trace: [TraceStep])
    case depthExceeded(statesCount: Int, limit: Int)
    case deadlocked(state: [String: TLAValue])
    case error(String)

    public var description: String {
        switch self {
        case .ok(let count): return "OK — explored " + String(count) + " state(s)"
        case .invariantViolated(let inv, _, let trace):
            let t = trace.enumerated().map { "  " + String($0.offset) + ". [" + $0.element.action + "] " + formatState($0.element.state) }
            return "INVARIANT VIOLATED: " + inv + "\n" + t.joined(separator: "\n")
        case .depthExceeded(let count, let l):
            return "DEPTH EXCEEDED — explored " + String(count) + " state(s) before hitting limit of " + String(l)
        case .deadlocked(let s): return "DEADLOCK detected at " + formatState(s)
        case .error(let message): return "ERROR: " + message
        }
    }
}

public struct TraceStep: CustomStringConvertible {
    public let state: [String: TLAValue]
    public let action: String
    public var description: String { "[" + action + "] " + formatState(state) }
}

private func formatState(_ state: [String: TLAValue]) -> String {
    "{" + state.sorted { $0.key < $1.key }.map { $0.key + " = " + String(describing: $0.value) }.joined(separator: ", ") + "}"
}
