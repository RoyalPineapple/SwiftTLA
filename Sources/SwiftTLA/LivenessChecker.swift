import Foundation

/// Liveness checking on the explored StateGraph.
/// Computes SCCs via Tarjan's algorithm, filters unfair terminal SCCs,
/// and verifies temporal properties (always, eventually, leads-to).
public struct LivenessChecker {
    public let graph: StateGraph

    public init(graph: StateGraph) { self.graph = graph }

    // MARK: - SCC decomposition (Tarjan's algorithm)

    public func computeSCCs() -> [Set<StateGraph.StateID>] {
        var indices: [StateGraph.StateID: Int] = [:]
        var lowlinks: [StateGraph.StateID: Int] = [:]
        var onStack: Set<StateGraph.StateID> = []
        var stack: [StateGraph.StateID] = []
        var sccs: [Set<StateGraph.StateID>] = []
        var currentIndex: Int = 0

        func strongConnect(_ v: StateGraph.StateID) {
            indices[v] = currentIndex; lowlinks[v] = currentIndex
            currentIndex += 1; stack.append(v); onStack.insert(v)
            let successors = graph.transitions[v]?.map(\.target) ?? []
            for w in successors {
                if indices[w] == nil { strongConnect(w); lowlinks[v] = min(lowlinks[v]!, lowlinks[w]!) } else if onStack.contains(w) { lowlinks[v] = min(lowlinks[v]!, indices[w]!) }
            }
            if lowlinks[v] == indices[v] {
                var scc = Set<StateGraph.StateID>()
                while let w = stack.popLast() { onStack.remove(w); scc.insert(w); if w == v { break } }
                sccs.append(scc)
            }
        }

        for node in graph.states.keys where indices[node] == nil { strongConnect(node) }
        return sccs
    }

    // MARK: - Terminal SCC detection

    public func terminalSCCs(from sccs: [Set<StateGraph.StateID>]) -> [Set<StateGraph.StateID>] {
        let nodeToSCC: [StateGraph.StateID: Int] = Dictionary(uniqueKeysWithValues:
            sccs.enumerated().flatMap { idx, scc in scc.map { ($0, idx) } })
        return sccs.enumerated().compactMap { idx, scc in
            let hasExternalEdge = scc.contains { node in
                let targets = graph.transitions[node]?.map(\.target) ?? []
                return targets.contains { nodeToSCC[$0] != idx }
            }
            return hasExternalEdge ? nil : scc
        }
    }

    // MARK: - Fairness filtering

    public func fairTerminalSCCs(_ terminalSCCs: [Set<StateGraph.StateID>],
                                  fairness: [FairnessCondition],
                                  actions: [NamedAction]) -> [Set<StateGraph.StateID>] {
        let actionNames = Set(actions.map(\.name))
        return terminalSCCs.filter { scc in
            fairness.allSatisfy { condition in
                switch condition {
                case .weakFairness(let name):
                    guard actionNames.contains(name) else { return true }
                    // A is taken if any S transition within the SCC has action name
                    let takenInSCC = scc.contains { state in
                        guard let successors = graph.transitions[state] else { return false }
                        return successors.contains { $0.action == name && scc.contains($0.target) }
                    }
                    // A is disabled somewhere if some state has no outgoing S labeled name
                    let disabledSomewhere = scc.contains { state in
                        guard let successors = graph.transitions[state] else { return true }
                        return !successors.contains { $0.action == name }
                    }
                    return takenInSCC || disabledSomewhere
                case .strongFairness(let name):
                    guard actionNames.contains(name) else { return true }
                    let takenInSCC = scc.contains { state in
                        guard let successors = graph.transitions[state] else { return false }
                        return successors.contains { $0.action == name && scc.contains($0.target) }
                    }
                    // SF(A): fair if A is taken within S OR A is disabled everywhere
                    let disabledEverywhere = scc.allSatisfy { state in
                        guard let successors = graph.transitions[state] else { return true }
                        return !successors.contains { $0.action == name }
                    }
                    return takenInSCC || disabledEverywhere
                }
            }
        }
    }

    // MARK: - Temporal property checking

    public enum TemporalResult: Equatable {
        case satisfied
        case violated(String, trace: [StateGraph.StateID])
    }

    public func checkAlways(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        // []P holds in all reachable states of fair terminal SCCs
        for scc in fairSCCs {
            for state in scc {
                guard let stateValues = graph.states[state] else { continue }
                let holds = try predicate.evaluateBool(in: stateValues)
                if !holds { return .violated("[]P: predicate failed in state \(state)", trace: [state]) }
            }
        }
        return .satisfied
    }

    public func checkEventually(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        // <>P: every fair terminal SCC must contain a state where P holds
        for scc in fairSCCs {
            let hasSatisfying = try scc.contains { state in
                guard let values = graph.states[state] else { return false }
                return try predicate.evaluateBool(in: values)
            }
            if !hasSatisfying {
                let first = scc.first!
                return .violated("<>P: no state in SCC satisfies predicate", trace: [first])
            }
        }
        return .satisfied
    }

    public func checkLeadsTo(_ from: StateExpr, _ to: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        // from ~> to: in every fair terminal SCC, if 'from' holds anywhere, 'to' must hold somewhere.
        // Since all states in an SCC are mutually reachable, 'to' holding anywhere ensures
        // every path from a 'from'-state eventually reaches a 'to'-state.
        for scc in fairSCCs {
            let hasFrom = try scc.contains { state in
                guard let values = graph.states[state] else { return false }
                return try from.evaluateBool(in: values)
            }
            if hasFrom {
                let hasTo = try scc.contains { state in
                    guard let values = graph.states[state] else { return false }
                    return try to.evaluateBool(in: values)
                }
                if !hasTo {
                    return .violated("~>: 'from' holds but 'to' never reached in SCC", trace: [scc.first!])
                }
            }
        }
        return .satisfied
    }

    public func checkAlwaysEventually(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        // []<>P: every fair terminal SCC must contain at least one state where P holds.
        // Since SCCs are strongly connected, if P holds once you can reach it from any path.
        return try checkEventually(predicate, fairSCCs: fairSCCs)
    }

    public func checkEventuallyAlways(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        // <>[]P: all fair terminal SCCs must consist entirely of states where P holds.
        for scc in fairSCCs {
            for state in scc {
                guard let values = graph.states[state] else { continue }
                let holds = try predicate.evaluateBool(in: values)
                if !holds {
                    return .violated("<>[]P: state \(state) in fair terminal SCC does not satisfy predicate", trace: [state])
                }
            }
        }
        return .satisfied
    }

    public func checkAll(_ properties: [NamedTemporal], fairness: [FairnessCondition],
                          actions: [NamedAction]) throws -> [TemporalResult] {
        let allSCCs = computeSCCs()
        let terminals = terminalSCCs(from: allSCCs)
        let fairs = fairTerminalSCCs(terminals, fairness: fairness, actions: actions)
        return try properties.map { prop in
            switch prop.expr {
            case .always(let p):          return try checkAlways(p, fairSCCs: fairs)
            case .eventually(let p):      return try checkEventually(p, fairSCCs: fairs)
            case .leadsTo(let a, let b):  return try checkLeadsTo(a, b, fairSCCs: fairs)
            case .alwaysEventually(let p): return try checkAlwaysEventually(p, fairSCCs: fairs)
            case .eventuallyAlways(let p): return try checkEventuallyAlways(p, fairSCCs: fairs)
            }
        }
    }
}
