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
            constraint: substituted.constraint,
            checkDeadlock: substituted.checkDeadlock,
            specificationName: substituted.name
        )
    }

    // MARK: - Pure helpers

    private func computeInitialStates(_ specification: TLASpec) -> [State] {
        let base = Dictionary(uniqueKeysWithValues: specification.variables.map { ($0.name, $0.initial) })
        let nondeterministic = specification.variables.filter { if case .set = $0.initial { return true }; return false }
        return nondeterministic.reduce([base]) { states, variable in
            guard case .set(let values) = variable.initial else { return states }
            return states.flatMap { state in values.map { state.merging([variable.name: $0]) { _, new in new } } }
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
            actions.flatMap { action in
                (try? ActionEnumerator.enumerate(action.body, from: state, varNames: variableNames))?
                    .map { (action.name, $0) } ?? []
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
    constraint: StateExpr?,
    checkDeadlock: Bool,
    specificationName: String
) -> ModelChecker.Exploration {
    bfsLoop(
        queue: seeds.map(\.1),
        stateToID: Dictionary(uniqueKeysWithValues: seeds.map { (canonical($0.1), $0.0) }),
        idToState: Dictionary(uniqueKeysWithValues: seeds.map { ($0.0, $0.1) }),
        visited: Set(seeds.map { canonical($0.1) }),
        transitions: [:],
        predecessors: [:],
        nextID: seeds.count,
        stepCount: 0,
        maxStates: 10_000,
        actions: actions,
        variableNames: variableNames,
        canonical: canonical,
        expand: expand,
        evaluate: evaluate,
        invariants: invariants,
        constraint: constraint,
        checkDeadlock: checkDeadlock,
        specificationName: specificationName
    )
}

private func bfsLoop(
    queue: [State],
    stateToID: [State: StateGraph.StateID],
    idToState: [StateGraph.StateID: State],
    visited: Set<State>,
    transitions: [StateGraph.StateID: [(String, StateGraph.StateID)]],
    predecessors: [State: (State, String)],
    nextID: Int,
    stepCount: Int,
    maxStates: Int,
    actions: [NamedAction],
    variableNames: [String],
    canonical: (State) -> State,
    expand: (State) -> [(String, State)],
    evaluate: (StateExpr, State) -> Bool,
    invariants: [NamedInvariant],
    constraint: StateExpr?,
    checkDeadlock: Bool,
    specificationName: String
) -> ModelChecker.Exploration {
    func graph() -> StateGraph {
        StateGraph(specName: specificationName, variableNames: variableNames, transitions: transitions, states: idToState)
    }

    guard stepCount < maxStates else {
        return ModelChecker.Exploration(result: .depthExceeded(statesCount: stepCount, limit: maxStates), graph: graph())
    }
    guard !queue.isEmpty else {
        return ModelChecker.Exploration(result: .ok(statesCount: stepCount), graph: graph())
    }

    let current = queue[0]
    let rest = Array(queue.dropFirst())
    guard let currentID = stateToID[canonical(current)] else {
        return bfsLoop(queue: rest, stateToID: stateToID, idToState: idToState, visited: visited, transitions: transitions, predecessors: predecessors, nextID: nextID, stepCount: stepCount + 1, maxStates: maxStates, actions: actions, variableNames: variableNames, canonical: canonical, expand: expand, evaluate: evaluate, invariants: invariants, constraint: constraint, checkDeadlock: checkDeadlock, specificationName: specificationName)
    }

    if let checkConstraint = constraint, evaluate(checkConstraint, current) {
        return bfsLoop(queue: rest, stateToID: stateToID, idToState: idToState, visited: visited, transitions: transitions, predecessors: predecessors, nextID: nextID, stepCount: stepCount + 1, maxStates: maxStates, actions: actions, variableNames: variableNames, canonical: canonical, expand: expand, evaluate: evaluate, invariants: invariants, constraint: constraint, checkDeadlock: checkDeadlock, specificationName: specificationName)
    }

    let enabled = enabledState(current, actions: actions, variableNames: variableNames)
    for invariant in invariants where !evaluate(invariant.body, enabled) {
        let trace = buildTrace(to: current, predecessors: predecessors, initial: queue.count > 0 ? queue[0] : current)
        return ModelChecker.Exploration(result: .invariantViolated(invariant: invariant.name, state: current, trace: trace), graph: graph())
    }

    let successors = expand(current)
    if checkDeadlock && successors.isEmpty {
        return ModelChecker.Exploration(result: .deadlocked(state: current), graph: graph())
    }

    var updatedTransitions = transitions
    for (successorAction, successorState) in successors {
        let canonicalForm = canonical(successorState)
        if let targetID = stateToID[canonicalForm] {
            updatedTransitions[currentID, default: []] += [(successorAction, targetID)]
        }
    }

    let newStates = successors.filter { !visited.contains(canonical($0.1)) }

    let next = newStates.reduce((rest, stateToID, idToState, updatedTransitions, visited, predecessors, nextID)) { accumulator, successor in
        var (queue, stateToIDMap, idToStateMap, transitionMap, visitedSet, predecessorMap, nextIdentifier) = accumulator
        let canonicalForm = canonical(successor.1)
        let targetID = stateToIDMap[canonicalForm] ?? StateGraph.StateID(nextIdentifier)
        transitionMap[currentID, default: []] += [(successor.0, targetID)]
        if stateToIDMap[canonicalForm] != nil {
            return (queue, stateToIDMap, idToStateMap, transitionMap, visitedSet, predecessorMap, nextIdentifier)
        }
        stateToIDMap[canonicalForm] = StateGraph.StateID(nextIdentifier)
        idToStateMap[StateGraph.StateID(nextIdentifier)] = successor.1
        predecessorMap[successor.1] = (current, successor.0)
        return (queue + [successor.1], stateToIDMap, idToStateMap, transitionMap, visitedSet.union([canonicalForm]), predecessorMap, nextIdentifier + 1)
    }

    return bfsLoop(queue: next.0, stateToID: next.1, idToState: next.2, visited: next.4, transitions: next.3, predecessors: next.5, nextID: next.6, stepCount: stepCount + 1, maxStates: maxStates, actions: actions, variableNames: variableNames, canonical: canonical, expand: expand, evaluate: evaluate, invariants: invariants, constraint: constraint, checkDeadlock: checkDeadlock, specificationName: specificationName)
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
