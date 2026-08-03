public struct ModelChecker {
    public let spec: TLASpec
    public let maxStates: Int

    public init(spec: TLASpec, maxStates: Int = 10_000) {
        self.spec = spec
        self.maxStates = maxStates
    }

    public func check() throws -> CheckResult {
        let result = try exploreWithGraph().result
        return result
    }

    public func exploreGraph() throws -> StateGraph {
        return try exploreWithGraph().graph
    }

    private func exploreWithGraph() throws -> (result: CheckResult, graph: StateGraph) {
        let spec = substituteConstants(self.spec)
        let varNames = spec.variables.map(\.name)
        let initial = Dictionary(uniqueKeysWithValues: spec.variables.map { ($0.name, $0.initial) })

        let symmetrySets: [SymmetrySet] = spec.variables.compactMap { v in
            if case .set(let s) = v.initial { return SymmetrySet(variableName: v.name, values: s) }
            return nil
        }
        func canonical(_ s: [String: TLAValue]) -> [String: TLAValue] {
            symmetrySets.reduce(s) { $1.canonicalize($0) }
        }

        let actions = spec.actions.isEmpty
            ? [NamedAction(name: "", body: .guard_(.value(.bool(false))))]
            : spec.actions

        let initCanonical = canonical(initial)
        var stateToID: [[String: TLAValue]: StateGraph.StateID] = [initCanonical: StateGraph.StateID(0)]
        var idToState: [StateGraph.StateID: [String: TLAValue]] = [StateGraph.StateID(0): initial]
        var transitions: [StateGraph.StateID: [(action: String, target: StateGraph.StateID)]] = [:]
        var nextID = 1

        var visited: Set<[String: TLAValue]> = [initCanonical]
        var queue: [[String: TLAValue]] = [initial]
        var predecessors: [[String: TLAValue]: ([String: TLAValue], String)] = [:]
        var head = 0

        let expand = { (state: [String: TLAValue]) -> [(state: [String: TLAValue], action: String)] in
            actions.flatMap { act in
                guard let nextStates = try? ActionEnumerator.enumerate(act.body, from: state, varNames: varNames)
                else { return [(state: [String: TLAValue], action: String)]() }
                return nextStates.map { ($0, act.name) }
            }
        }

        for stepCount in 0... {
            guard stepCount < maxStates else {
                let graph = StateGraph(
                    specName: spec.name,
                    variableNames: varNames,
                    transitions: transitions,
                    states: idToState
                )
                return (.depthExceeded(statesCount: stepCount, limit: maxStates), graph)
            }
            guard head < queue.count else {
                let graph = StateGraph(
                    specName: spec.name,
                    variableNames: varNames,
                    transitions: transitions,
                    states: idToState
                )
                return (.ok(statesCount: stepCount), graph)
            }
            let current = queue[head]
            head += 1
            let currentID = stateToID[canonical(current)]!

            var stateWithEnabled = current
            for act in spec.actions where !act.name.isEmpty {
                let enabled = (try? ActionEnumerator.enumerate(act.body, from: current, varNames: varNames))?.isEmpty == false
                stateWithEnabled["_enabled_\(act.name)"] = .bool(enabled)
            }

            for inv in spec.invariants {
                guard try Evaluator.evaluateBool(inv.body, in: stateWithEnabled) else {
                    let graph = StateGraph(
                        specName: spec.name,
                        variableNames: varNames,
                        transitions: transitions,
                        states: idToState
                    )
                    return (.invariantViolated(
                        invariant: inv.name,
                        state: current,
                        trace: buildTrace(to: current, predecessors: predecessors, initial: initial)
                    ), graph)
                }
            }

            var outgoing: [(action: String, target: StateGraph.StateID)] = []
            for (successor, action) in expand(current) {
                let canonicalSuccessor = canonical(successor)
                let targetID: StateGraph.StateID
                if let existing = stateToID[canonicalSuccessor] {
                    targetID = existing
                } else {
                    targetID = StateGraph.StateID(nextID)
                    stateToID[canonicalSuccessor] = targetID
                    idToState[targetID] = successor
                    nextID += 1
                }
                outgoing.append((action, targetID))

                if !visited.contains(canonicalSuccessor) {
                    visited.insert(canonicalSuccessor)
                    predecessors[successor] = (current, action)
                    queue.append(successor)
                }
            }
            transitions[currentID] = outgoing
        }
        fatalError("unreachable")
    }

    private func buildTrace(
        to final: [String: TLAValue],
        predecessors: [[String: TLAValue]: ([String: TLAValue], String)],
        initial: [String: TLAValue]
    ) -> [TraceStep] {
        var steps: [TraceStep] = []
        var current = final
        while let (prev, action) = predecessors[current] {
            steps.insert(TraceStep(state: current, action: action), at: 0)
            current = prev
        }
        steps.insert(TraceStep(state: initial, action: "init"), at: 0)
        return steps
    }
}

public enum CheckResult: CustomStringConvertible {
    case ok(statesCount: Int)
    case invariantViolated(invariant: String, state: [String: TLAValue], trace: [TraceStep])
    case depthExceeded(statesCount: Int, limit: Int)
    case error(String)

    public var description: String {
        switch self {
        case .ok(let count):
            return "OK — explored \(count) state(s)"

        case .invariantViolated(let inv, _, let trace):
            var msg = "INVARIANT VIOLATED: \(inv)\n"
            msg += "Counterexample trace:\n"
            for (i, step) in trace.enumerated() {
                msg += "  \(i). [\(step.action)] \(formatState(step.state))\n"
            }
            return msg

        case .depthExceeded(let count, let limit):
            return "DEPTH EXCEEDED — explored \(count) state(s) before hitting limit of \(limit)"

        case .error(let msg):
            return "ERROR: \(msg)"
        }
    }
}

public struct TraceStep: CustomStringConvertible {
    public let state: [String: TLAValue]
    public let action: String
    public var description: String { "[\(action)] \(formatState(state))" }
}

private func formatState(_ state: [String: TLAValue]) -> String {
    let entries = state.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }
    return "{\(entries.joined(separator: ", "))}"
}
