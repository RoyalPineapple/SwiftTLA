import Foundation

package enum TemporalAnalysisStatus: Equatable, Sendable {
    case satisfied
    case violated
    case unavailable
}

package enum TemporalDiagnosticReason: String, Equatable, Sendable {
    case satisfied
    case violatingFairLasso = "violating-fair-lasso"
    case missingInitialStateIdentity = "missing-initial-state-identity"
    case invalidGraphTopology = "invalid-graph-topology"
    case incompleteExploration = "incomplete-exploration"
    case unknownAction = "unknown-action"
}

package struct FairLassoWitness: Equatable, Sendable {
    public let prefix: [StateGraph.StateID]
    public let cycle: [StateGraph.StateID]
    public let prefixActions: [String]
    public let cycleActions: [String]

    init(
        prefix: [StateGraph.StateID],
        cycle: [StateGraph.StateID],
        prefixActions: [String],
        cycleActions: [String]
    ) {
        self.prefix = prefix
        self.cycle = cycle
        self.prefixActions = prefixActions
        self.cycleActions = cycleActions
    }
}

package struct TemporalAnalysis: Equatable, Sendable {
    public let status: TemporalAnalysisStatus
    public let reason: TemporalDiagnosticReason
    public let witness: FairLassoWitness?
    public let propertyValues: [StateGraph.StateID: Bool]
    public let enabledActions: [String: [StateGraph.StateID: Bool]]
    public let fairComponents: [Set<StateGraph.StateID>]
    public let rejectedComponents: [Set<StateGraph.StateID>]

    public init(
        status: TemporalAnalysisStatus,
        reason: TemporalDiagnosticReason,
        witness: FairLassoWitness? = nil,
        propertyValues: [StateGraph.StateID: Bool] = [:],
        enabledActions: [String: [StateGraph.StateID: Bool]] = [:],
        fairComponents: [Set<StateGraph.StateID>] = [],
        rejectedComponents: [Set<StateGraph.StateID>] = []
    ) {
        self.status = status
        self.reason = reason
        self.witness = witness
        self.propertyValues = propertyValues
        self.enabledActions = enabledActions
        self.fairComponents = fairComponents
        self.rejectedComponents = rejectedComponents
    }
}

/// Bounded liveness checking over `[][Next]_vars` behaviors.
///
/// Every reachable state has an implicit stutter edge. Fairness uses only
/// explicit, state-changing named-action transitions.
package struct LivenessChecker<Action: Hashable & Sendable, Scope: Hashable & Sendable> {
    let states: Set<StateGraph.StateID>
    let transitions: [StateGraph.StateID: [GraphEdge<Action>]]
    let matches: (Action, Scope) -> Bool
    let actionOrder: (Action, Action) -> Bool

    func analyze(
        _ property: TemporalCondition<@Sendable (StateGraph.StateID) throws -> Bool>,
        fairness: [(scope: Scope, isStrong: Bool)],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true,
        renderScope: (Scope) throws -> String
    ) throws -> TemporalAnalysis {
        guard isComplete else {
            return .init(status: .unavailable, reason: .incompleteExploration)
        }
        guard !initialStateIDs.isEmpty, initialStateIDs.allSatisfy({ states.contains($0) }) else {
            return .init(status: .unavailable, reason: .missingInitialStateIdentity)
        }

        guard transitions.allSatisfy({ source, transitions in
            states.contains(source) && transitions.allSatisfy { states.contains($0.target) }
        }) else {
            return .init(status: .unavailable, reason: .invalidGraphTopology)
        }

        guard hasValidActions() else {
            return .init(status: .unavailable, reason: .unknownAction)
        }

        let predicate: @Sendable (StateGraph.StateID) throws -> Bool
        switch property {
        case .always(let value), .eventually(let value), .alwaysEventually(let value), .eventuallyAlways(let value):
            predicate = value
        case .leadsTo(_, let target): predicate = target
        }
        let values = try Dictionary(uniqueKeysWithValues: states.map { state in
            (state, try predicate(state))
        })
        let enabled = enabledness(for: fairness)
        let allStates = states
        let negative = Set(values.compactMap { $0.value ? nil : $0.key })
        let search: LassoSearch

        switch property {
        case .always:
            search = .init(cycleStates: allStates, prefixStates: negative)
        case .eventually:
            search = .init(cycleStates: negative, prefixContinuationStates: negative)
        case .alwaysEventually:
            search = .init(cycleStates: negative)
        case .eventuallyAlways:
            search = .init(cycleStates: allStates, cycleRequiredStates: negative)
        case .leadsTo(let trigger, _):
            let triggers = Set(try states.compactMap { state in
                try trigger(state) ? state : nil
            }).intersection(negative)
            search = .init(cycleStates: negative, prefixStates: triggers, prefixContinuationStates: negative)
        }

        let components = fairComponents(in: search.cycleStates, fairness: fairness, enabled: enabled)
        let witness = findWitness(
            components.fair,
            initialStates: initialStateIDs,
            prefixStates: search.prefixStates,
            prefixContinuationStates: search.prefixContinuationStates,
            cycleRequiredStates: search.cycleRequiredStates,
            fairness: fairness,
            enabled: enabled
        )
        return .init(
            status: witness == nil ? .satisfied : .violated,
            reason: witness == nil ? .satisfied : .violatingFairLasso,
            witness: witness,
            propertyValues: values,
            enabledActions: try renderedEnabledness(enabled, renderScope: renderScope),
            fairComponents: components.fair,
            rejectedComponents: components.rejected
        )
    }

    public func computeSCCs() -> [Set<StateGraph.StateID>] {
        stronglyConnectedComponents(in: states)
    }

    public func terminalSCCs(from sccs: [Set<StateGraph.StateID>]) -> [Set<StateGraph.StateID>] {
        let nodeToSCC = Dictionary(uniqueKeysWithValues: sccs.enumerated().flatMap { index, component in
            component.map { ($0, index) }
        })
        return sccs.filter { component in
            !component.contains { state in
                explicitEdges(from: state).contains { edge in nodeToSCC[edge.target] != nodeToSCC[state] }
            }
        }
    }

    private func renderedEnabledness(
        _ enabled: [Scope: [StateGraph.StateID: Bool]],
        renderScope: (Scope) throws -> String
    ) throws -> [String: [StateGraph.StateID: Bool]] {
        var rendered: [String: [StateGraph.StateID: Bool]] = [:]
        for entry in enabled {
            rendered[try renderScope(entry.key)] = entry.value
        }
        return rendered
    }

    private func hasValidActions() -> Bool {
        transitions.values.allSatisfy { $0.allSatisfy { $0.action != nil } }
    }

    private func matches(_ edge: GraphEdge<Action>, _ scope: Scope) -> Bool {
        guard let action = edge.action else { return false }
        return matches(action, scope)
    }

    private func enabledness(for fairness: [(scope: Scope, isStrong: Bool)]) -> [Scope: [StateGraph.StateID: Bool]] {
        Dictionary(
            uniqueKeysWithValues: Set(fairness.map(\.scope)).map { scope in
                let states = Dictionary(uniqueKeysWithValues: self.states.map { state in
                    (state, explicitEdges(from: state).contains { edge in
                        matches(edge, scope) && (edge.target == state) == false
                    })
                })
                return (scope, states)
            }
        )
    }

    private func fairComponents(
        in states: Set<StateGraph.StateID>,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [StateGraph.StateID: Bool]]
    ) -> (fair: [Set<StateGraph.StateID>], rejected: [Set<StateGraph.StateID>]) {
        var fair: [Set<StateGraph.StateID>] = []
        var rejected: [Set<StateGraph.StateID>] = []

        func prune(_ candidates: Set<StateGraph.StateID>) {
            for component in stronglyConnectedComponents(in: candidates) where !component.isEmpty {
                if let action = fairness.compactMap({ condition -> Scope? in
                    guard condition.isStrong else { return nil }
                    return isFair(condition, in: component, enabled: enabled) ? nil : condition.scope
                }).first {
                    rejected.append(component)
                    let reduced = component.filter { enabled[action]?[$0] != true }
                    if !reduced.isEmpty { prune(Set(reduced)) }
                    continue
                }
                if fairness.contains(where: { !isFair($0, in: component, enabled: enabled) }) {
                    rejected.append(component)
                } else {
                    fair.append(component)
                }
            }
        }

        prune(states)
        return (fair, rejected)
    }

    private func isFair(
        _ condition: (scope: Scope, isStrong: Bool),
        in component: Set<StateGraph.StateID>,
        enabled: [Scope: [StateGraph.StateID: Bool]]
    ) -> Bool {
        let taken = component.contains { state in
            explicitEdges(from: state).contains { edge in
                matches(edge, condition.scope) && (edge.target == state) == false && component.contains(edge.target)
            }
        }
        if taken { return true }
        let enabledStates = component.filter { enabled[condition.scope]?[$0] == true }
        return condition.isStrong ? enabledStates.isEmpty : enabledStates.count < component.count
    }

}

extension LivenessChecker {
    private func findWitness(
        _ components: [Set<StateGraph.StateID>],
        initialStates: [StateGraph.StateID],
        prefixStates: Set<StateGraph.StateID>?,
        prefixContinuationStates: Set<StateGraph.StateID>?,
        cycleRequiredStates: Set<StateGraph.StateID>?,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [StateGraph.StateID: Bool]]
    ) -> FairLassoWitness? {
        var witnesses: [FairLassoWitness] = []
        for component in components {
            let requiredCycle = cycleRequiredStates?.intersection(component) ?? []
            if cycleRequiredStates != nil, requiredCycle.isEmpty { continue }
            for cycleStart in component.sorted(by: stateOrder) {
                guard let cycle = makeCycle(
                    in: component,
                    root: cycleStart,
                    requiredStates: requiredCycle,
                    fairness: fairness,
                    enabled: enabled
                ) else { continue }
                for initial in initialStates.sorted(by: stateOrder) {
                    if prefixStates == nil {
                        if let prefix = shortestPath(from: initial, to: cycleStart, in: prefixContinuationStates) {
                            witnesses.append(.init(
                                prefix: prefix.0,
                                cycle: cycle.0,
                                prefixActions: prefix.1.map(\.renderedAction),
                                cycleActions: cycle.1.map(\.renderedAction)
                            ))
                        }
                    } else if let prefixStates {
                        for required in prefixStates.sorted(by: stateOrder) {
                            guard let first = shortestPath(from: initial, to: required, in: nil),
                                  let second = shortestPath(from: required, to: cycleStart, in: prefixContinuationStates) else { continue }
                            witnesses.append(.init(
                                prefix: first.0 + second.0.dropFirst(),
                                cycle: cycle.0,
                                prefixActions: (first.1 + second.1).map(\.renderedAction),
                                cycleActions: cycle.1.map(\.renderedAction)
                            ))
                        }
                    }
                }
            }
        }
        return witnesses.min(by: witnessOrder)
    }

    private func makeCycle(
        in component: Set<StateGraph.StateID>,
        root: StateGraph.StateID,
        requiredStates: Set<StateGraph.StateID>,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [StateGraph.StateID: Bool]]
    ) -> ([StateGraph.StateID], [GraphEdge<Action>])? {
        let scopes = Set(fairness.map(\.scope))
        func advance(
            _ configuration: CycleSearchConfiguration<Scope>,
            state: StateGraph.StateID,
            edge: GraphEdge<Action>?
        ) -> CycleSearchConfiguration<Scope> {
            let taken = edge.flatMap { edge -> Set<Scope>? in
                guard (edge.target == edge.source) == false else { return [] }
                return Set(scopes.filter { matches(edge, $0) })
            } ?? []
            let disabled = Set(scopes.filter { (enabled[$0]?[state] == true) == false })
            let present = Set(scopes.filter { enabled[$0]?[state] == true })
            return CycleSearchConfiguration<Scope>(
                state: state,
                visitedRequiredState: configuration.visitedRequiredState || requiredStates.contains(state),
                takenActions: configuration.takenActions.union(taken),
                disabledActions: configuration.disabledActions.union(disabled),
                enabledActions: configuration.enabledActions.union(present)
            )
        }
        func isFair(_ configuration: CycleSearchConfiguration<Scope>) -> Bool {
            guard requiredStates.isEmpty || configuration.visitedRequiredState else { return false }
            return fairness.allSatisfy { condition in
                return condition.isStrong
                    ? configuration.takenActions.contains(condition.scope) || configuration.enabledActions.contains(condition.scope) == false
                    : configuration.takenActions.contains(condition.scope) || configuration.disabledActions.contains(condition.scope)
            }
        }

        let initial = advance(.initial(at: root), state: root, edge: nil)
        var frontier: [CycleSearchConfiguration<Scope>: CycleSearchPath<Action>] = [
            initial: .init(states: [root], actions: [])
        ]
        var seen: [CycleSearchConfiguration<Scope>: CycleSearchPath<Action>] = frontier

        while !frontier.isEmpty {
            var next: [CycleSearchConfiguration<Scope>: CycleSearchPath<Action>] = [:]
            var completed: [CycleSearchPath<Action>] = []
            for (configuration, path) in frontier {
                for edge in edges(from: configuration.state).sorted(by: edgeOrder) where component.contains(edge.target) {
                    let nextConfiguration = advance(configuration, state: edge.target, edge: edge)
                    let nextPath = CycleSearchPath<Action>(
                        states: path.states + [edge.target],
                        actions: path.actions + [edge]
                    )
                    if nextConfiguration.state == root, isFair(nextConfiguration) {
                        completed.append(nextPath)
                        continue
                    }
                    guard let previous = seen[nextConfiguration] else {
                        seen[nextConfiguration] = nextPath
                        if let pending = next[nextConfiguration], cyclePathOrder(nextPath, pending) {
                            next[nextConfiguration] = nextPath
                        } else if next[nextConfiguration] == nil {
                            next[nextConfiguration] = nextPath
                        }
                        continue
                    }
                    if nextPath.actions.count == previous.actions.count, cyclePathOrder(nextPath, previous) {
                        seen[nextConfiguration] = nextPath
                        next[nextConfiguration] = nextPath
                    }
                }
            }
            if let shortest = completed.min(by: cyclePathOrder) {
                return (shortest.states, shortest.actions)
            }
            frontier = next
        }
        return nil
    }

    private func shortestPath(
        from source: StateGraph.StateID,
        to destination: StateGraph.StateID,
        in allowed: Set<StateGraph.StateID>?
    ) -> ([StateGraph.StateID], [GraphEdge<Action>])? {
        guard allowed?.contains(source) != false, allowed?.contains(destination) != false else { return nil }
        if source == destination { return ([source], []) }
        var queue = [source]
        var head = 0
        var predecessors: [StateGraph.StateID: (StateGraph.StateID, GraphEdge<Action>)] = [:]
        var seen: Set<StateGraph.StateID> = [source]
        while head < queue.count {
            let state = queue[head]; head += 1
            for edge in edges(from: state).sorted(by: edgeOrder) where allowed?.contains(edge.target) != false && !seen.contains(edge.target) {
                seen.insert(edge.target); predecessors[edge.target] = (state, edge)
                if edge.target == destination {
                    var states = [destination]; var actions: [GraphEdge<Action>] = []; var current = destination
                    while let predecessor = predecessors[current] {
                        actions.append(predecessor.1); states.append(predecessor.0); current = predecessor.0
                    }
                    return (states.reversed(), actions.reversed())
                }
                queue.append(edge.target)
            }
        }
        return nil
    }

    private func stronglyConnectedComponents(in allowed: Set<StateGraph.StateID>) -> [Set<StateGraph.StateID>] {
        var index = 0; var indices: [StateGraph.StateID: Int] = [:]
        var stack: [StateGraph.StateID] = []; var onStack: Set<StateGraph.StateID> = []; var components: [Set<StateGraph.StateID>] = []
        func visit(_ state: StateGraph.StateID) -> Int {
            let stateIndex = index
            var lowlink = stateIndex
            indices[state] = stateIndex; index += 1; stack.append(state); onStack.insert(state)
            for edge in edges(from: state).sorted(by: edgeOrder) where allowed.contains(edge.target) {
                if let targetIndex = indices[edge.target] {
                    if onStack.contains(edge.target) { lowlink = min(lowlink, targetIndex) }
                } else {
                    lowlink = min(lowlink, visit(edge.target))
                }
            }
            if lowlink == stateIndex {
                var component: Set<StateGraph.StateID> = []
                while let node = stack.popLast() { onStack.remove(node); component.insert(node); if node == state { break } }
                components.append(component)
            }
            return lowlink
        }
        for state in allowed.sorted(by: stateOrder) where indices[state] == nil { _ = visit(state) }
        return components
    }

    private func explicitEdges(from state: StateGraph.StateID) -> [GraphEdge<Action>] {
        transitions[state] ?? []
    }

    private func edges(from state: StateGraph.StateID) -> [GraphEdge<Action>] {
        explicitEdges(from: state) + [.init(source: state, action: nil, renderedAction: "[stutter]", target: state)]
    }
}

private struct LassoSearch {
    let cycleStates: Set<StateGraph.StateID>
    // nil imposes no visit requirement; an empty set makes the requirement impossible.
    let prefixStates: Set<StateGraph.StateID>?
    let prefixContinuationStates: Set<StateGraph.StateID>?
    let cycleRequiredStates: Set<StateGraph.StateID>?

    init(
        cycleStates: Set<StateGraph.StateID>,
        prefixStates: Set<StateGraph.StateID>? = nil,
        prefixContinuationStates: Set<StateGraph.StateID>? = nil,
        cycleRequiredStates: Set<StateGraph.StateID>? = nil
    ) {
        self.cycleStates = cycleStates
        self.prefixStates = prefixStates
        self.prefixContinuationStates = prefixContinuationStates
        self.cycleRequiredStates = cycleRequiredStates
    }
}

package struct GraphEdge<Action: Hashable & Sendable>: Hashable, Sendable {
    let source: StateGraph.StateID
    let action: Action?
    let renderedAction: String
    let target: StateGraph.StateID
}

private struct CycleSearchConfiguration<Scope: Hashable & Sendable>: Hashable {
    let state: StateGraph.StateID
    let visitedRequiredState: Bool
    let takenActions: Set<Scope>
    let disabledActions: Set<Scope>
    let enabledActions: Set<Scope>

    static func initial(at state: StateGraph.StateID) -> CycleSearchConfiguration {
        .init(
            state: state,
            visitedRequiredState: false,
            takenActions: [],
            disabledActions: [],
            enabledActions: []
        )
    }
}

private struct CycleSearchPath<Action: Hashable & Sendable>: Hashable {
    let states: [StateGraph.StateID]
    let actions: [GraphEdge<Action>]
}

private func stateOrder(_ lhs: StateGraph.StateID, _ rhs: StateGraph.StateID) -> Bool { lhs.id < rhs.id }
extension LivenessChecker {
    private func edgeOrder(_ lhs: GraphEdge<Action>, _ rhs: GraphEdge<Action>) -> Bool {
        if graphActionOrder(lhs.action, rhs.action) { return true }
        if graphActionOrder(rhs.action, lhs.action) { return false }
        if lhs.target.id != rhs.target.id { return lhs.target.id < rhs.target.id }
        return false
    }

    private func graphActionOrder(_ lhs: Action?, _ rhs: Action?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            return actionOrder(lhs, rhs)
        }
    }
    private func cyclePathOrder(_ lhs: CycleSearchPath<Action>, _ rhs: CycleSearchPath<Action>) -> Bool {
        let leftStates = lhs.states.map(\.id)
        let rightStates = rhs.states.map(\.id)
        if leftStates != rightStates { return leftStates.lexicographicallyPrecedes(rightStates) }
        for (left, right) in zip(lhs.actions, rhs.actions) {
            if graphActionOrder(left.action, right.action) { return true }
            if graphActionOrder(right.action, left.action) { return false }
        }
        return false
    }
}
private func witnessOrder(_ lhs: FairLassoWitness, _ rhs: FairLassoWitness) -> Bool {
    if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count < rhs.prefix.count }
    if lhs.cycleActions.count != rhs.cycleActions.count { return lhs.cycleActions.count < rhs.cycleActions.count }
    let left = lhs.prefix.map(\.id) + lhs.cycle.map(\.id)
    let right = rhs.prefix.map(\.id) + rhs.cycle.map(\.id)
    if left != right { return left.lexicographicallyPrecedes(right) }
    let leftActions = lhs.prefixActions + lhs.cycleActions
    let rightActions = rhs.prefixActions + rhs.cycleActions
    return leftActions.lexicographicallyPrecedes(rightActions)
}
