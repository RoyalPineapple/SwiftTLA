public struct LivenessChecker {
    public let graph: StateGraph
    public let spec: TLASpec

    public init(graph: StateGraph, spec: TLASpec) {
        self.graph = graph
        self.spec = spec
    }

    public func check() throws -> [LivenessViolation] {
        guard !spec.temporalProperties.isEmpty else { return [] }

        let sccs = computeSCCs()
        let terminal = sccs.filter { scc in
            scc.allSatisfy { stateID in
                (graph.transitions[stateID] ?? []).allSatisfy { scc.contains($0.target) }
            }
        }

        let fair = fairTerminalSCCs(terminal)

        var violations: [LivenessViolation] = []
        for prop in spec.temporalProperties {
            for scc in fair {
                if let violation = try checkProperty(prop, in: scc) {
                    let enriched = LivenessViolation(
                        property: violation.property,
                        sccStates: violation.sccStates,
                        description: violation.description,
                        prefixPath: buildPrefix(to: scc),
                        cyclePath: buildCycle(in: scc)
                    )
                    violations.append(enriched)
                }
            }
        }

        return violations
    }

    private func checkProperty(
        _ prop: NamedTemporal,
        in scc: Set<StateGraph.StateID>
    ) throws -> LivenessViolation? {
        let states = scc.map { graph.states[$0]! }

        switch prop.expr {
        case .alwaysEventually(let p):
            let hasP = try states.contains { try Evaluator.evaluateBool(p, in: $0) }
            if !hasP {
                return LivenessViolation(property: prop.name, sccStates: Array(states), description: "No state in terminal SCC satisfies \(p)")
            }

        case .eventuallyAlways(let p):
            let allP = try states.allSatisfy { try Evaluator.evaluateBool(p, in: $0) }
            if !allP {
                return LivenessViolation(property: prop.name, sccStates: Array(states), description: "Not all states in terminal SCC satisfy \(p)")
            }

        case .leadsTo(let p, let q):
            for state in states {
                if try Evaluator.evaluateBool(p, in: state) {
                    let qExists = states.contains { s in (try? Evaluator.evaluateBool(q, in: s)) ?? false }
                    if !qExists {
                        return LivenessViolation(property: prop.name, sccStates: Array(states), description: "State satisfies \(p) but SCC never satisfies \(q)")
                    }
                }
            }

        case .always(let p):
            let allP = try states.allSatisfy { try Evaluator.evaluateBool(p, in: $0) }
            if !allP {
                return LivenessViolation(property: prop.name, sccStates: Array(states), description: "Always(\(p)) violated in terminal SCC")
            }

        case .eventually(let p):
            let hasP = try states.contains { try Evaluator.evaluateBool(p, in: $0) }
            if !hasP {
                return LivenessViolation(property: prop.name, sccStates: Array(states), description: "Eventually(\(p)) violated — no state in terminal SCC satisfies it")
            }
        }

        return nil
    }

    private func isActionEnabled(actionName: String, in state: [String: TLAValue]) -> Bool {
        guard let action = spec.actions.first(where: { $0.name == actionName }),
              let nextStates = try? ActionEnumerator.enumerate(action.body, from: state, varNames: graph.variableNames)
        else { return false }
        return !nextStates.isEmpty
    }

    private func fairTerminalSCCs(_ terminalSCCs: [Set<StateGraph.StateID>]) -> [Set<StateGraph.StateID>] {
        guard !spec.fairness.isEmpty else { return terminalSCCs }

        return terminalSCCs.filter { scc in
            let sccStates = scc.map { graph.states[$0]! }

            for condition in spec.fairness {
                switch condition {
                case .weakFairness(let actionName):
                    let alwaysEnabled = sccStates.allSatisfy { isActionEnabled(actionName: actionName, in: $0) }
                    if alwaysEnabled {
                        let hasTransition = scc.contains { stateID in
                            (graph.transitions[stateID] ?? []).contains { $0.action == actionName }
                        }
                        if !hasTransition { return false }
                    }
                case .strongFairness(let actionName):
                    let infinitelyOftenEnabled = sccStates.contains { isActionEnabled(actionName: actionName, in: $0) }
                    if infinitelyOftenEnabled {
                        let hasTransition = scc.contains { stateID in
                            (graph.transitions[stateID] ?? []).contains { $0.action == actionName }
                        }
                        if !hasTransition { return false }
                    }
                }
            }

            return true
        }
    }

    private func computeSCCs() -> [Set<StateGraph.StateID>] {
        let allIDs = Set(graph.states.keys)
        var index = 0
        var stack: [StateGraph.StateID] = []
        var onStack = Set<StateGraph.StateID>()
        var indices = [StateGraph.StateID: Int]()
        var lowlink = [StateGraph.StateID: Int]()
        var sccs: [Set<StateGraph.StateID>] = []

        func strongConnect(_ v: StateGraph.StateID) {
            indices[v] = index
            lowlink[v] = index
            index += 1
            stack.append(v)
            onStack.insert(v)

            for (_, w) in graph.transitions[v] ?? [] {
                if indices[w] == nil {
                    strongConnect(w)
                    lowlink[v] = min(lowlink[v]!, lowlink[w]!)
                } else if onStack.contains(w) {
                    lowlink[v] = min(lowlink[v]!, indices[w]!)
                }
            }

            if lowlink[v] == indices[v] {
                var scc = Set<StateGraph.StateID>()
                while true {
                    let w = stack.removeLast()
                    onStack.remove(w)
                    scc.insert(w)
                    if w == v { break }
                }
                sccs.append(scc)
            }
        }

        for id in allIDs {
            if indices[id] == nil {
                strongConnect(id)
            }
        }

        return sccs
    }
}

public struct LivenessViolation: CustomStringConvertible {
    public let property: String
    public let sccStates: [[String: TLAValue]]
    public let description: String
    public let prefixPath: [[String: TLAValue]]
    public let cyclePath: [[String: TLAValue]]

    public init(property: String, sccStates: [[String: TLAValue]], description: String, prefixPath: [[String: TLAValue]] = [], cyclePath: [[String: TLAValue]] = []) {
        self.property = property
        self.sccStates = sccStates
        self.description = description
        self.prefixPath = prefixPath
        self.cyclePath = cyclePath
    }
}

extension LivenessChecker {
    private func buildPrefix(to scc: Set<StateGraph.StateID>) -> [[String: TLAValue]] {
        guard let target = scc.first else { return [] }
        var visited: Set<StateGraph.StateID> = [target]
        var queue: [(StateGraph.StateID, [StateGraph.StateID])] = [(target, [target])]

        while !queue.isEmpty {
            let (current, currentPath) = queue.removeFirst()
            if current.id == 0 { return currentPath.reversed().map { graph.states[$0]! } }
            for (otherID, transitions) in graph.transitions {
                if transitions.contains(where: { $0.target == current }), !visited.contains(otherID) {
                    visited.insert(otherID)
                    queue.append((otherID, currentPath + [otherID]))
                }
            }
        }
        return []
    }

    private func buildCycle(in scc: Set<StateGraph.StateID>) -> [[String: TLAValue]] {
        guard let start = scc.first, let firstState = graph.states[start] else { return [] }
        var cycle: [[String: TLAValue]] = [firstState]
        var visited: Set<StateGraph.StateID> = [start]
        var current = start
        for _ in 0..<min(10, scc.count) {
            guard let transitions = graph.transitions[current] else { break }
            if let next = transitions.first(where: { scc.contains($0.target) && !visited.contains($0.target) }) {
                visited.insert(next.target)
                cycle.append(graph.states[next.target]!)
                current = next.target
            } else if transitions.contains(where: { $0.target == start }) {
                cycle.append(firstState)
                break
            } else { break }
        }
        return cycle
    }
}
