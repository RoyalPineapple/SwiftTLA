/// Explores every reachable state of a TLA+ specification (plain BFS).
///
/// Lifecycle self-proof lives in `TLASpec.bfsChecker` / `@TLAModel BFSChecker`
/// and composition APIs — not as a decorative controller inside this loop.
public struct ModelChecker {
    public let spec: TLASpec
    public let maxStates: Int

    public init(spec: TLASpec, maxStates: Int = 10_000) {
        self.spec = spec
        self.maxStates = maxStates
    }

    public func check() throws -> CheckResult { try explore().result }
    public func exploreGraph() throws -> StateGraph { try explore().graph }

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
        guard !initialStates.isEmpty else {
            return emptyExploration(substituted, variableNames: variableNames, result: .error("No initial states"))
        }

        guard try checkAssume(substituted, initial: initialStates[0]) else {
            return emptyExploration(substituted, variableNames: variableNames, result: .error("ASSUME failed"))
        }

        let seeds = initialStates.enumerated().map { (StateGraph.StateID($0.offset), $0.element) }
        return try bfs(
            seeds: seeds,
            variableNames: variableNames,
            expand: buildExpander(actions, variableNames: variableNames, constraint: substituted.constraint, runtimeFuncs: substituted.runtimeFuncs, recursiveFuncs: substituted.recursiveFuncs),
            evaluate: buildEvaluator(runtimeFuncs: substituted.runtimeFuncs, recursiveFuncs: substituted.recursiveFuncs),
            actions: actions,
            invariants: substituted.invariants,
            checkDeadlock: substituted.checkDeadlock,
            specificationName: substituted.name,
            maxStates: self.maxStates
        )
    }

    private func buildExpander(
        _ actions: [NamedAction],
        variableNames: [String],
        constraint: StateExpr? = nil,
        runtimeFuncs: [String: Evaluator.RuntimeFunc] = [:],
        recursiveFuncs: [RecursiveFunc] = []
    ) -> (State) throws -> [(String, State)] {
        { state in
            var result: [(String, State)] = []
            for action in actions {
                do {
                    let successors = try ActionEnumerator.enumerate(
                        action.body, from: state, varNames: variableNames
                    )
                    result.append(contentsOf: successors.map { (action.name, $0) })
                } catch {
                    throw CheckerEvalError.action(action.name, error)
                }
            }
            if let c = constraint {
                result = try result.filter {
                    try Evaluator.evaluateBool(c, in: $0.1, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs)
                }
            }
            return result
        }
    }

    private func buildEvaluator(runtimeFuncs: [String: Evaluator.RuntimeFunc] = [:], recursiveFuncs: [RecursiveFunc] = []) -> (StateExpr, State) throws -> Bool {
        { expression, state in try Evaluator.evaluateBool(expression, in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs) }
    }

    private func checkAssume(_ specification: TLASpec, initial: State) throws -> Bool {
        guard let assume = specification.assume else { return true }
        return try Evaluator.evaluateBool(assume, in: initial, runtimeFuncs: specification.runtimeFuncs, recursiveFuncs: specification.recursiveFuncs)
    }

    private func emptyExploration(
        _ specification: TLASpec,
        variableNames: [String],
        result: CheckResult
    ) -> Exploration {
        Exploration(
            result: result,
            graph: StateGraph(
                specName: specification.name,
                variableNames: variableNames,
                transitions: [:],
                states: [:]
            )
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
    seeds: [(StateGraph.StateID, State)],
    variableNames: [String],
    expand: (State) throws -> [(String, State)],
    evaluate: (StateExpr, State) throws -> Bool,
    actions: [NamedAction],
    invariants: [NamedInvariant],
    checkDeadlock: Bool,
    specificationName: String,
    maxStates: Int
) throws -> ModelChecker.Exploration {
    var queue = seeds.map(\.1)
    var stateToID = Dictionary(
        seeds.map { (canonicalKey($0.1), $0.0) },
        uniquingKeysWith: { existing, _ in existing }
    )
    var idToState = Dictionary(
        seeds.map { ($0.0, $0.1) },
        uniquingKeysWith: { existing, _ in existing }
    )
    var visited = Set(seeds.map { canonicalKey($0.1) })
    var transitions: [StateGraph.StateID: [StateGraph.Transition]] = [:]
    var predecessors: [State: (State, String)] = [:]
    var nextID = seeds.count
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
            return ModelChecker.Exploration(
                result: .depthExceeded(statesCount: processed, limit: maxStates),
                graph: graph()
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
            return ModelChecker.Exploration(
                result: .error(String(describing: error)),
                graph: graph()
            )
        }

        for invariant in invariants {
            let holds: Bool
            do {
                holds = try evaluate(invariant.body, enabled)
            } catch {
                return ModelChecker.Exploration(
                    result: .error("Invariant '\(invariant.name)': \(error)"),
                    graph: graph()
                )
            }
            if !holds {
                let trace = buildTrace(
                    to: current,
                    predecessors: predecessors,
                    initial: queue.isEmpty ? current : queue[0]
                )
                return ModelChecker.Exploration(
                    result: .invariantViolated(
                        invariant: invariant.name,
                        state: current,
                        trace: trace
                    ),
                    graph: graph()
                )
            }
        }

        let successors: [(String, State)]
        do {
            successors = try expand(current)
        } catch {
            return ModelChecker.Exploration(
                result: .error(String(describing: error)),
                graph: graph()
            )
        }

        if checkDeadlock && successors.isEmpty {
            return ModelChecker.Exploration(
                result: .deadlocked(state: current),
                graph: graph()
            )
        }

        for (successorAction, successorState) in successors {
            let key = canonicalKey(successorState)
            if let targetID = stateToID[key] {
                transitions[currentID, default: []] += [
                    StateGraph.Transition(action: successorAction, target: targetID)
                ]
            }
        }

        for successor in successors where !visited.contains(canonicalKey(successor.1)) {
            let key = canonicalKey(successor.1)
            let targetID = StateGraph.StateID(nextID)
            transitions[currentID, default: []] += [
                StateGraph.Transition(action: successor.0, target: targetID)
            ]
            stateToID[key] = targetID
            idToState[targetID] = successor.1
            predecessors[successor.1] = (current, successor.0)
            queue.append(successor.1)
            visited.insert(key)
            nextID += 1
        }
    }

    return ModelChecker.Exploration(
        result: .ok(statesCount: processed),
        graph: graph()
    )
}

/// Identity key — no silent symmetry (fragment v1).
private func canonicalKey(_ state: State) -> State { state }

private func enabledState(
    _ state: State,
    actions: [NamedAction],
    variableNames: [String]
) throws -> State {
    var result = state
    for action in actions where !action.name.isEmpty {
        do {
            let successors = try ActionEnumerator.enumerate(
                action.body, from: state, varNames: variableNames
            )
            result["_enabled_" + action.name] = .bool(!successors.isEmpty)
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
            let t = trace.enumerated().map {
                "  " + String($0.offset) + ". [" + $0.element.action + "] " + formatState($0.element.state)
            }
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
    "{" + state.sorted { $0.key < $1.key }.map {
        $0.key + " = " + String(describing: $0.value)
    }.joined(separator: ", ") + "}"
}
