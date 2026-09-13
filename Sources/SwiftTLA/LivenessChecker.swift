import Foundation

public enum TemporalAnalysisStatus: Equatable, Sendable {
    case satisfied
    case violated
    case unavailable
}

public enum TemporalDiagnosticReason: String, Equatable, Sendable {
    case satisfied
    case violatingFairLasso = "violating-fair-lasso"
    case missingInitialStateIdentity = "missing-initial-state-identity"
    case invalidGraphTopology = "invalid-graph-topology"
    case incompleteExploration = "incomplete-exploration"
    case unknownAction = "unknown-action"
}

public struct FairLassoWitness<State: Hashable & Sendable, Action: Equatable & Sendable>: Equatable, Sendable {
    public let prefix: [State]
    public let cycle: [State]
    public let prefixActions: [Action]
    public let cycleActions: [Action]

    init(
        prefix: [State],
        cycle: [State],
        prefixActions: [Action],
        cycleActions: [Action]
    ) {
        self.prefix = prefix
        self.cycle = cycle
        self.prefixActions = prefixActions
        self.cycleActions = cycleActions
    }
}

public struct TemporalAnalysis<State: Hashable & Sendable, Action: Equatable & Sendable>: Equatable, Sendable {
    public let status: TemporalAnalysisStatus
    public let reason: TemporalDiagnosticReason
    public let witness: FairLassoWitness<State, Action>?
    public let enabledActions: [String: [State: Bool]]
    public let fairComponents: [Set<State>]
    public let rejectedComponents: [Set<State>]

    public init(
        status: TemporalAnalysisStatus,
        reason: TemporalDiagnosticReason,
        witness: FairLassoWitness<State, Action>? = nil,
        enabledActions: [String: [State: Bool]] = [:],
        fairComponents: [Set<State>] = [],
        rejectedComponents: [Set<State>] = []
    ) {
        self.status = status
        self.reason = reason
        self.witness = witness
        self.enabledActions = enabledActions
        self.fairComponents = fairComponents
        self.rejectedComponents = rejectedComponents
    }

    func map<NewState: Hashable & Sendable, NewAction: Equatable & Sendable>(
        state: (State) throws -> NewState,
        action: (Action) throws -> NewAction
    ) rethrows -> TemporalAnalysis<NewState, NewAction> {
        func values(_ source: [State: Bool]) throws -> [NewState: Bool] {
            try Dictionary(uniqueKeysWithValues: source.map { (try state($0.key), $0.value) })
        }
        return try .init(
            status: status, reason: reason,
            witness: witness.map { trace in
                try .init(prefix: trace.prefix.map(state), cycle: trace.cycle.map(state),
                    prefixActions: trace.prefixActions.map(action), cycleActions: trace.cycleActions.map(action))
            },
            enabledActions: enabledActions.mapValues(values),
            fairComponents: fairComponents.map { try Set($0.map(state)) },
            rejectedComponents: rejectedComponents.map { try Set($0.map(state)) }
        )
    }

}

/// Bounded liveness checking over `[][Next]_vars` behaviors.
///
/// Every reachable state has an implicit stutter edge. Fairness uses only
/// explicit, state-changing named-action transitions.
package struct LivenessChecker<State: Hashable & Sendable, Action: Hashable & Sendable, Scope: Hashable & Sendable> {
    let states: Set<State>
    let transitions: [State: [GraphEdge<State, Action>]]
    let matches: (Action, Scope) -> Bool
    let actionOrder: (Action, Action) -> Bool
    let stateOrder: (State, State) -> Bool
    private let fairness: [(scope: Scope, isStrong: Bool)]
    private let enabled: [Scope: [State: Bool]]

    init(
        states: Set<State>,
        transitions: [State: [GraphEdge<State, Action>]],
        fairness: [(scope: Scope, isStrong: Bool)],
        matches: @escaping (Action, Scope) -> Bool,
        actionOrder: @escaping (Action, Action) -> Bool,
        stateOrder: @escaping (State, State) -> Bool
    ) {
        self.states = states
        self.transitions = transitions
        self.fairness = fairness
        self.matches = matches
        self.actionOrder = actionOrder
        self.stateOrder = stateOrder
        enabled = Dictionary(uniqueKeysWithValues: Set(fairness.map(\.scope)).map { scope in
            let values = Dictionary(uniqueKeysWithValues: states.map { state in
                let isEnabled = (transitions[state] ?? []).contains { edge in
                    guard let action = edge.action else { return false }
                    return matches(action, scope) && edge.target != state
                }
                return (state, isEnabled)
            })
            return (scope, values)
        })
    }

    func analyze(
        _ property: TemporalCondition<@Sendable (State) throws -> Bool>,
        initialStates: [State],
        isComplete: Bool = true,
        renderScope: (Scope) throws -> String
    ) throws -> TemporalAnalysis<State, Action?> {
        guard isComplete else {
            return .init(status: .unavailable, reason: .incompleteExploration)
        }
        guard !initialStates.isEmpty, initialStates.allSatisfy({ states.contains($0) }) else {
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

        let predicate: @Sendable (State) throws -> Bool
        switch property {
        case .always(let value), .eventually(let value), .alwaysEventually(let value), .eventuallyAlways(let value):
            predicate = value
        case .leadsTo(_, let target): predicate = target
        }
        let negative = try states.filter { try !predicate($0) }
        let allStates = states
        let search: LassoSearch<State>

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
            initialStates: initialStates,
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
            enabledActions: try renderedEnabledness(enabled, renderScope: renderScope),
            fairComponents: components.fair,
            rejectedComponents: components.rejected
        )
    }

    public func computeSCCs() -> [Set<State>] {
        stronglyConnectedComponents(in: states)
    }

    public func terminalSCCs(from sccs: [Set<State>]) -> [Set<State>] {
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
        _ enabled: [Scope: [State: Bool]],
        renderScope: (Scope) throws -> String
    ) throws -> [String: [State: Bool]] {
        var rendered: [String: [State: Bool]] = [:]
        for entry in enabled {
            rendered[try renderScope(entry.key)] = entry.value
        }
        return rendered
    }

    private func hasValidActions() -> Bool {
        transitions.values.allSatisfy { $0.allSatisfy { $0.action != nil } }
    }

    private func matches(_ edge: GraphEdge<State, Action>, _ scope: Scope) -> Bool {
        guard let action = edge.action else { return false }
        return matches(action, scope)
    }

    private func fairComponents(
        in states: Set<State>,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [State: Bool]]
    ) -> (fair: [Set<State>], rejected: [Set<State>]) {
        var fair: [Set<State>] = []
        var rejected: [Set<State>] = []

        func prune(_ candidates: Set<State>) {
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
        in component: Set<State>,
        enabled: [Scope: [State: Bool]]
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
        _ components: [Set<State>],
        initialStates: [State],
        prefixStates: Set<State>?,
        prefixContinuationStates: Set<State>?,
        cycleRequiredStates: Set<State>?,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [State: Bool]]
    ) -> FairLassoWitness<State, Action?>? {
        var bestWitness: FairLassoWitness<State, Action?>?
        func consider(_ candidate: FairLassoWitness<State, Action?>) {
            if let bestWitness, !witnessOrder(candidate, bestWitness) { return }
            bestWitness = candidate
        }
        let orderedInitialStates = initialStates.sorted(by: stateOrder)
        let requiredPrefixStates = prefixStates.map { $0.sorted(by: stateOrder) }
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
                for initial in orderedInitialStates {
                    if requiredPrefixStates == nil {
                        if let prefix = shortestPath(from: initial, to: cycleStart, in: prefixContinuationStates) {
                            consider(.init(
                                prefix: prefix.0,
                                cycle: cycle.0,
                                prefixActions: prefix.1.map(\.action),
                                cycleActions: cycle.1.map(\.action)
                            ))
                        }
                    } else if let requiredPrefixStates {
                        for required in requiredPrefixStates {
                            guard let first = shortestPath(from: initial, to: required, in: nil),
                                  let second = shortestPath(from: required, to: cycleStart, in: prefixContinuationStates) else { continue }
                            consider(.init(
                                prefix: first.0 + second.0.dropFirst(),
                                cycle: cycle.0,
                                prefixActions: (first.1 + second.1).map(\.action),
                                cycleActions: cycle.1.map(\.action)
                            ))
                        }
                    }
                }
            }
        }
        return bestWitness
    }

    private func makeCycle(
        in component: Set<State>,
        root: State,
        requiredStates: Set<State>,
        fairness: [(scope: Scope, isStrong: Bool)],
        enabled: [Scope: [State: Bool]]
    ) -> ([State], [GraphEdge<State, Action>])? {
        let scopes = Set(fairness.map(\.scope))
        func advance(
            _ configuration: CycleSearchConfiguration<State, Scope>,
            state: State,
            edge: GraphEdge<State, Action>?
        ) -> CycleSearchConfiguration<State, Scope> {
            let taken = edge.flatMap { edge -> Set<Scope>? in
                guard (edge.target == edge.source) == false else { return [] }
                return Set(scopes.filter { matches(edge, $0) })
            } ?? []
            let disabled = Set(scopes.filter { (enabled[$0]?[state] == true) == false })
            let present = Set(scopes.filter { enabled[$0]?[state] == true })
            return CycleSearchConfiguration<State, Scope>(
                state: state,
                visitedRequiredState: configuration.visitedRequiredState || requiredStates.contains(state),
                takenActions: configuration.takenActions.union(taken),
                disabledActions: configuration.disabledActions.union(disabled),
                enabledActions: configuration.enabledActions.union(present)
            )
        }
        func isFair(_ configuration: CycleSearchConfiguration<State, Scope>) -> Bool {
            guard requiredStates.isEmpty || configuration.visitedRequiredState else { return false }
            return fairness.allSatisfy { condition in
                return condition.isStrong
                    ? configuration.takenActions.contains(condition.scope) || configuration.enabledActions.contains(condition.scope) == false
                    : configuration.takenActions.contains(condition.scope) || configuration.disabledActions.contains(condition.scope)
            }
        }

        let initial = advance(.initial(at: root), state: root, edge: nil)
        var frontier: [CycleSearchConfiguration<State, Scope>: CycleSearchPath<State, Action>] = [
            initial: .init(states: [root], actions: [])
        ]
        var seen: [CycleSearchConfiguration<State, Scope>: CycleSearchPath<State, Action>] = frontier

        while !frontier.isEmpty {
            var next: [CycleSearchConfiguration<State, Scope>: CycleSearchPath<State, Action>] = [:]
            var completed: [CycleSearchPath<State, Action>] = []
            for (configuration, path) in frontier {
                for edge in edges(from: configuration.state).sorted(by: edgeOrder) where component.contains(edge.target) {
                    let nextConfiguration = advance(configuration, state: edge.target, edge: edge)
                    let nextPath = CycleSearchPath<State, Action>(
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
        from source: State,
        to destination: State,
        in allowed: Set<State>?
    ) -> ([State], [GraphEdge<State, Action>])? {
        guard allowed?.contains(source) != false, allowed?.contains(destination) != false else { return nil }
        if source == destination { return ([source], []) }
        var queue = [source]
        var head = 0
        var predecessors: [State: (State, GraphEdge<State, Action>)] = [:]
        var seen: Set<State> = [source]
        while head < queue.count {
            let state = queue[head]; head += 1
            for edge in edges(from: state).sorted(by: edgeOrder) where allowed?.contains(edge.target) != false && !seen.contains(edge.target) {
                seen.insert(edge.target); predecessors[edge.target] = (state, edge)
                if edge.target == destination {
                    var states = [destination]; var actions: [GraphEdge<State, Action>] = []; var current = destination
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

    private func stronglyConnectedComponents(in allowed: Set<State>) -> [Set<State>] {
        var index = 0; var indices: [State: Int] = [:]
        var stack: [State] = []; var onStack: Set<State> = []; var components: [Set<State>] = []
        func visit(_ state: State) -> Int {
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
                var component: Set<State> = []
                while let node = stack.popLast() { onStack.remove(node); component.insert(node); if node == state { break } }
                components.append(component)
            }
            return lowlink
        }
        for state in allowed.sorted(by: stateOrder) where indices[state] == nil { _ = visit(state) }
        return components
    }

    private func explicitEdges(from state: State) -> [GraphEdge<State, Action>] {
        transitions[state] ?? []
    }

    private func edges(from state: State) -> [GraphEdge<State, Action>] {
        explicitEdges(from: state) + [.init(source: state, action: nil, target: state)]
    }
}

private struct LassoSearch<State: Hashable & Sendable> {
    let cycleStates: Set<State>
    // nil imposes no visit requirement; an empty set makes the requirement impossible.
    let prefixStates: Set<State>?
    let prefixContinuationStates: Set<State>?
    let cycleRequiredStates: Set<State>?

    init(
        cycleStates: Set<State>,
        prefixStates: Set<State>? = nil,
        prefixContinuationStates: Set<State>? = nil,
        cycleRequiredStates: Set<State>? = nil
    ) {
        self.cycleStates = cycleStates
        self.prefixStates = prefixStates
        self.prefixContinuationStates = prefixContinuationStates
        self.cycleRequiredStates = cycleRequiredStates
    }
}

package struct GraphEdge<State: Hashable & Sendable, Action: Hashable & Sendable>: Hashable, Sendable {
    let source: State
    let action: Action?
    let target: State
}

private struct CycleSearchConfiguration<State: Hashable & Sendable, Scope: Hashable & Sendable>: Hashable {
    let state: State
    let visitedRequiredState: Bool
    let takenActions: Set<Scope>
    let disabledActions: Set<Scope>
    let enabledActions: Set<Scope>

    static func initial(at state: State) -> CycleSearchConfiguration {
        .init(
            state: state,
            visitedRequiredState: false,
            takenActions: [],
            disabledActions: [],
            enabledActions: []
        )
    }
}

private struct CycleSearchPath<State: Hashable & Sendable, Action: Hashable & Sendable>: Hashable {
    let states: [State]
    let actions: [GraphEdge<State, Action>]
}

extension LivenessChecker {
    private func edgeOrder(_ lhs: GraphEdge<State, Action>, _ rhs: GraphEdge<State, Action>) -> Bool {
        if graphActionOrder(lhs.action, rhs.action) { return true }
        if graphActionOrder(rhs.action, lhs.action) { return false }
        return stateOrder(lhs.target, rhs.target)
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
    private func cyclePathOrder(_ lhs: CycleSearchPath<State, Action>, _ rhs: CycleSearchPath<State, Action>) -> Bool {
        let leftStates = lhs.states
        let rightStates = rhs.states
        if leftStates != rightStates { return leftStates.lexicographicallyPrecedes(rightStates, by: stateOrder) }
        for (left, right) in zip(lhs.actions, rhs.actions) {
            if graphActionOrder(left.action, right.action) { return true }
            if graphActionOrder(right.action, left.action) { return false }
        }
        return false
    }
}
extension LivenessChecker {
    private func witnessOrder(_ lhs: FairLassoWitness<State, Action?>, _ rhs: FairLassoWitness<State, Action?>) -> Bool {
        if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count < rhs.prefix.count }
        if lhs.cycleActions.count != rhs.cycleActions.count { return lhs.cycleActions.count < rhs.cycleActions.count }
        let left = lhs.prefix + lhs.cycle
        let right = rhs.prefix + rhs.cycle
        if left != right { return left.lexicographicallyPrecedes(right, by: stateOrder) }
        let leftActions = lhs.prefixActions + lhs.cycleActions
        let rightActions = rhs.prefixActions + rhs.cycleActions
        return leftActions.lexicographicallyPrecedes(rightActions, by: graphActionOrder)
    }
}
