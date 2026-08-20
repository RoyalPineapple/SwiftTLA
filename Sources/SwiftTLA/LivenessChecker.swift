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
    case incompleteExploration = "incomplete-exploration"
    case unknownAction = "unknown-action"
    case evaluationFailed = "evaluation-failed"
}

public struct FairLassoWitness: Equatable, Sendable {
    public let prefix: [StateGraph.StateID]
    public let cycle: [StateGraph.StateID]
    public let prefixActions: [String]
    public let cycleActions: [String]

    public init(
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

public struct TemporalAnalysisResult: Equatable, Sendable {
    public let status: TemporalAnalysisStatus
    public let reason: TemporalDiagnosticReason
    public let diagnostic: String?
    public let witness: FairLassoWitness?
    public let propertyValues: [StateGraph.StateID: Bool]
    public let enabledActions: [String: [StateGraph.StateID: Bool]]
    public let fairComponents: [Set<StateGraph.StateID>]
    public let rejectedComponents: [Set<StateGraph.StateID>]

    public init(
        status: TemporalAnalysisStatus,
        reason: TemporalDiagnosticReason,
        diagnostic: String? = nil,
        witness: FairLassoWitness? = nil,
        propertyValues: [StateGraph.StateID: Bool] = [:],
        enabledActions: [String: [StateGraph.StateID: Bool]] = [:],
        fairComponents: [Set<StateGraph.StateID>] = [],
        rejectedComponents: [Set<StateGraph.StateID>] = []
    ) {
        self.status = status
        self.reason = reason
        self.diagnostic = diagnostic
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
public struct LivenessChecker {
    public let graph: StateGraph
    private let compilation: CompiledSpecification?

    public init(compilation: CompiledSpecification, graph: StateGraph) {
        self.graph = graph
        self.compilation = compilation
    }

    init(graph: StateGraph) {
        self.graph = graph
        compilation = nil
    }

    public func analyze(
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true
    ) -> [TemporalAnalysisResult] {
        guard let compilation else { return [] }
        return compilation.model.temporalProperties.map {
            analyze(
                $0.expression,
                fairness: compilation.spec.fairness,
                actions: compilation.spec.actions,
                initialStateIDs: initialStateIDs,
                isComplete: isComplete,
                compilation: compilation
            )
        }
    }

    private func analyze(
        _ property: CompiledTemporalExpr,
        fairness: [FairnessCondition],
        actions: [NamedAction],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool,
        compilation: CompiledSpecification
    ) -> TemporalAnalysisResult {
        let form: TemporalForm
        let predicate: CompiledStateExpr
        let trigger: CompiledStateExpr?
        switch property {
        case .always(let value): form = .always; predicate = value; trigger = nil
        case .eventually(let value): form = .eventually; predicate = value; trigger = nil
        case .alwaysEventually(let value): form = .alwaysEventually; predicate = value; trigger = nil
        case .eventuallyAlways(let value): form = .eventuallyAlways; predicate = value; trigger = nil
        case .leadsTo(let from, let to): form = .leadsTo; predicate = to; trigger = from
        }
        return analyze(
            form: form,
            fairness: fairness,
            actions: actions,
            initialStateIDs: initialStateIDs,
            isComplete: isComplete,
            predicate: { state in
                guard let projection = graph.states[state] else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch,
                        stage: .validation,
                        path: "liveness.graph.state",
                        expected: "a state projection",
                        actual: "no projection",
                        nextSafeAction: "Explore the compiled model again before checking liveness."
                    )
                }
                return try predicateHolds(predicate, in: projection, compilation: compilation)
            },
            trigger: trigger.map { trigger in
                { state in
                    guard let projection = graph.states[state] else { return false }
                    return try predicateHolds(trigger, in: projection, compilation: compilation)
                        && !predicateHolds(predicate, in: projection, compilation: compilation)
                }
            }
        )
    }

    public enum TemporalResult: Equatable {
        case satisfied
        case violated(String, trace: [StateGraph.StateID])
        case unavailable(String)
    }

    public func computeSCCs() -> [Set<StateGraph.StateID>] {
        stronglyConnectedComponents(in: Set(graph.states.keys))
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

    func fairTerminalSCCs(
        _ terminalSCCs: [Set<StateGraph.StateID>],
        fairness: [FairnessCondition],
        actions: [NamedAction]
    ) -> [Set<StateGraph.StateID>] {
        let enabled = enabledness(for: actions)
        return terminalSCCs.filter { component in
            fairness.allSatisfy { isFair($0, in: component, enabled: enabled) }
        }
    }

    func checkAlways(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        for component in fairSCCs {
            for state in component {
                guard let projection = graph.states[state] else { continue }
                if try !predicate.evaluateBool(in: projection.formalValues) {
                    return .violated("[]P: predicate failed in state \(state)", trace: [state])
                }
            }
        }
        return .satisfied
    }

    func checkEventually(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        for component in fairSCCs {
            let holds = try component.contains { state in
                try predicate.evaluateBool(in: graph.states[state]?.formalValues ?? [:])
            }
            if !holds, let first = component.sorted(by: stateOrder).first {
                return .violated("<>P: no state in SCC satisfies predicate", trace: [first])
            }
        }
        return .satisfied
    }

    func checkLeadsTo(_ from: StateExpr, _ to: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        for component in fairSCCs {
            let hasFrom = try component.contains { try from.evaluateBool(in: graph.states[$0]?.formalValues ?? [:]) }
            let hasTo = try component.contains { try to.evaluateBool(in: graph.states[$0]?.formalValues ?? [:]) }
            if hasFrom, !hasTo, let first = component.sorted(by: stateOrder).first {
                return .violated("~>: 'from' holds but 'to' never reached in SCC", trace: [first])
            }
        }
        return .satisfied
    }

    func checkAlwaysEventually(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        try checkEventually(predicate, fairSCCs: fairSCCs)
    }

    func checkEventuallyAlways(_ predicate: StateExpr, fairSCCs: [Set<StateGraph.StateID>]) throws -> TemporalResult {
        try checkAlways(predicate, fairSCCs: fairSCCs)
    }

    func checkAll(
        _ properties: [NamedTemporal],
        fairness: [FairnessCondition],
        actions: [NamedAction]
    ) throws -> [TemporalResult] {
        let initialStates = graph.states.keys.sorted(by: stateOrder)
        return properties.map { property in
            let result = analyze(property.expr, fairness: fairness, actions: actions, initialStateIDs: initialStates)
            switch result.status {
            case .satisfied: return .satisfied
            case .violated:
                return .violated("\(property.expr): fair lasso", trace: result.witness?.prefix ?? [])
            case .unavailable: return .unavailable(result.reason.rawValue)
            }
        }
    }

    func analyze(
        _ property: TemporalExpr,
        fairness: [FairnessCondition],
        actions: [NamedAction],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true
    ) -> TemporalAnalysisResult {
        let form: TemporalForm
        let predicate: StateExpr
        let trigger: StateExpr?
        switch property {
        case .always(let value): form = .always; predicate = value; trigger = nil
        case .eventually(let value): form = .eventually; predicate = value; trigger = nil
        case .alwaysEventually(let value): form = .alwaysEventually; predicate = value; trigger = nil
        case .eventuallyAlways(let value): form = .eventuallyAlways; predicate = value; trigger = nil
        case .leadsTo(let from, let to): form = .leadsTo; predicate = to; trigger = from
        }
        return analyze(
            form: form,
            fairness: fairness,
            actions: actions,
            initialStateIDs: initialStateIDs,
            isComplete: isComplete,
            predicate: { state in
                guard let projection = graph.states[state] else { return false }
                return try predicate.evaluateBool(in: projection.formalValues)
            },
            trigger: trigger.map { trigger in
                { state in
                    guard let projection = graph.states[state] else { return false }
                    return try trigger.evaluateBool(in: projection.formalValues)
                        && !predicate.evaluateBool(in: projection.formalValues)
                }
            }
        )
    }

    private enum TemporalForm {
        case always
        case eventually
        case alwaysEventually
        case eventuallyAlways
        case leadsTo
    }

    private func analyze(
        form: TemporalForm,
        fairness: [FairnessCondition],
        actions: [NamedAction],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool,
        predicate: (StateGraph.StateID) throws -> Bool,
        trigger: ((StateGraph.StateID) throws -> Bool)?
    ) -> TemporalAnalysisResult {
        guard isComplete else {
            return .init(status: .unavailable, reason: .incompleteExploration)
        }
        guard !initialStateIDs.isEmpty, initialStateIDs.allSatisfy({ graph.states[$0] != nil }) else {
            return .init(status: .unavailable, reason: .missingInitialStateIdentity)
        }

        let names = Set(actions.map(\.name))
        let referencedNames = Set(fairness.map(\.actionIdentity))
        let knownIdentities = names.union(Set(actions.flatMap { action in
            actionInvocations(action).map { $0.invocation.description }
        }))
        guard referencedNames.isSubset(of: knownIdentities), graphHasOnlyKnownActions(knownIdentities) else {
            return .init(status: .unavailable, reason: .unknownAction)
        }

        let values: [StateGraph.StateID: Bool]
        do {
            values = try Dictionary(uniqueKeysWithValues: graph.states.keys.map { state in
                (state, try predicate(state))
            })
        } catch {
            return .init(status: .unavailable, reason: .evaluationFailed, diagnostic: String(describing: error))
        }
        let enabled = enabledness(for: actions)
        let allStates = Set(graph.states.keys)
        let negative = Set(values.compactMap { $0.value ? nil : $0.key })
        let search: LassoSearch

        switch form {
        case .always:
            search = .init(cycleStates: allStates, prefixStates: negative, cycleRequiredStates: [])
        case .eventually:
            search = .init(cycleStates: negative, prefixStates: [], prefixContinuationStates: negative, cycleRequiredStates: [])
        case .alwaysEventually:
            search = .init(cycleStates: negative, prefixStates: [], cycleRequiredStates: [])
        case .eventuallyAlways:
            search = .init(cycleStates: allStates, prefixStates: [], cycleRequiredStates: negative)
        case .leadsTo:
            guard let trigger else {
                return .init(status: .unavailable, reason: .evaluationFailed, diagnostic: "Missing leads-to trigger")
            }
            let triggers: Set<StateGraph.StateID>
            do {
                triggers = Set(try graph.states.keys.compactMap { state in
                    try trigger(state) ? state : nil
                })
            } catch {
                return .init(status: .unavailable, reason: .evaluationFailed, diagnostic: String(describing: error))
            }
            search = .init(cycleStates: negative, prefixStates: triggers, prefixContinuationStates: negative, cycleRequiredStates: [])
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
            enabledActions: enabled,
            fairComponents: components.fair,
            rejectedComponents: components.rejected
        )
    }

    private func predicateHolds(
        _ predicate: CompiledStateExpr,
        in projection: TLAStateProjection,
        compilation: CompiledSpecification
    ) throws -> Bool {
        let state = try FormalState(projection: projection, compilation: compilation)
        return try CompiledRuntime(compilation: compilation).predicateHolds(predicate, in: state)
    }

    private func graphHasOnlyKnownActions(_ names: Set<String>) -> Bool {
        graph.transitions.values.allSatisfy { transitions in
            transitions.allSatisfy { names.contains($0.action) }
        }
    }

    private func enabledness(for actions: [NamedAction]) -> [String: [StateGraph.StateID: Bool]] {
        Dictionary(
            uniqueKeysWithValues: actions.flatMap { action in
                actionInvocations(action).map { variant in
                    let identity = variant.invocation.description
                    let states = Dictionary(uniqueKeysWithValues: graph.states.keys.map { state in
                        (state, explicitEdges(from: state).contains { $0.action == identity && $0.target != state })
                    })
                    return (identity, states)
                }
            }
        )
    }

    private func fairComponents(
        in states: Set<StateGraph.StateID>,
        fairness: [FairnessCondition],
        enabled: [String: [StateGraph.StateID: Bool]]
    ) -> (fair: [Set<StateGraph.StateID>], rejected: [Set<StateGraph.StateID>]) {
        var fair: [Set<StateGraph.StateID>] = []
        var rejected: [Set<StateGraph.StateID>] = []

        func prune(_ candidates: Set<StateGraph.StateID>) {
            for component in stronglyConnectedComponents(in: candidates) where !component.isEmpty {
                if let action = fairness.compactMap({ condition -> String? in
                    guard condition.isStrong else { return nil }
                    return isFair(condition, in: component, enabled: enabled) ? nil : condition.actionIdentity
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
        _ condition: FairnessCondition,
        in component: Set<StateGraph.StateID>,
        enabled: [String: [StateGraph.StateID: Bool]]
    ) -> Bool {
        let name = condition.actionIdentity
        let isStrong = condition.isStrong
        let taken = component.contains { state in
            explicitEdges(from: state).contains { $0.action == name && $0.target != state && component.contains($0.target) }
        }
        if taken { return true }
        let enabledStates = component.filter { enabled[name]?[$0] == true }
        return isStrong ? enabledStates.isEmpty : enabledStates.count < component.count
    }

}

extension LivenessChecker {
    private func findWitness(
        _ components: [Set<StateGraph.StateID>],
        initialStates: [StateGraph.StateID],
        prefixStates: Set<StateGraph.StateID>,
        prefixContinuationStates: Set<StateGraph.StateID>?,
        cycleRequiredStates: Set<StateGraph.StateID>,
        fairness: [FairnessCondition],
        enabled: [String: [StateGraph.StateID: Bool]]
    ) -> FairLassoWitness? {
        var witnesses: [FairLassoWitness] = []
        for component in components {
            let requiredCycle = cycleRequiredStates.intersection(component)
            if !cycleRequiredStates.isEmpty, requiredCycle.isEmpty { continue }
            for cycleStart in component.sorted(by: stateOrder) {
                guard let cycle = makeCycle(
                    in: component,
                    root: cycleStart,
                    requiredStates: requiredCycle,
                    fairness: fairness,
                    enabled: enabled
                ) else { continue }
                for initial in initialStates.sorted(by: stateOrder) {
                if prefixStates.isEmpty {
                    if let prefix = shortestPath(from: initial, to: cycleStart, in: prefixContinuationStates) {
                            witnesses.append(.init(prefix: prefix.0, cycle: cycle.0, prefixActions: prefix.1, cycleActions: cycle.1))
                        }
                    } else {
                        for required in prefixStates.sorted(by: stateOrder) {
                            guard let first = shortestPath(from: initial, to: required, in: nil),
                                  let second = shortestPath(from: required, to: cycleStart, in: prefixContinuationStates) else { continue }
                            witnesses.append(.init(
                                prefix: first.0 + second.0.dropFirst(),
                                cycle: cycle.0,
                                prefixActions: first.1 + second.1,
                                cycleActions: cycle.1
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
        fairness: [FairnessCondition],
        enabled: [String: [StateGraph.StateID: Bool]]
    ) -> ([StateGraph.StateID], [String])? {
        let actionNames = Set(fairness.map(\.actionIdentity))
        func advance(
            _ configuration: CycleSearchConfiguration,
            state: StateGraph.StateID,
            edge: GraphEdge?
        ) -> CycleSearchConfiguration {
            let action = edge?.action
            let taken = edge != nil && edge?.target != edge?.source ? Set(action.map { [$0] } ?? []).intersection(actionNames) : []
            let disabled = Set(actionNames.filter { enabled[$0]?[state] != true })
            let present = Set(actionNames.filter { enabled[$0]?[state] == true })
            return CycleSearchConfiguration(
                state: state,
                visitedRequiredState: configuration.visitedRequiredState || requiredStates.contains(state),
                takenActions: configuration.takenActions.union(taken),
                disabledActions: configuration.disabledActions.union(disabled),
                enabledActions: configuration.enabledActions.union(present)
            )
        }
        func isFair(_ configuration: CycleSearchConfiguration) -> Bool {
            guard requiredStates.isEmpty || configuration.visitedRequiredState else { return false }
            return fairness.allSatisfy { condition in
                let name = condition.actionIdentity
                return condition.isStrong
                    ? configuration.takenActions.contains(name) || !configuration.enabledActions.contains(name)
                    : configuration.takenActions.contains(name) || configuration.disabledActions.contains(name)
            }
        }

        let initial = advance(.initial(at: root), state: root, edge: nil)
        var frontier: [CycleSearchConfiguration: CycleSearchPath] = [
            initial: .init(states: [root], actions: [])
        ]
        var seen: [CycleSearchConfiguration: CycleSearchPath] = frontier

        while !frontier.isEmpty {
            var next: [CycleSearchConfiguration: CycleSearchPath] = [:]
            var completed: [CycleSearchPath] = []
            for (configuration, path) in frontier {
                for edge in edges(from: configuration.state).sorted(by: edgeOrder) where component.contains(edge.target) {
                    let nextConfiguration = advance(configuration, state: edge.target, edge: edge)
                    let nextPath = CycleSearchPath(
                        states: path.states + [edge.target],
                        actions: path.actions + [edge.action]
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
    ) -> ([StateGraph.StateID], [String])? {
        guard allowed?.contains(source) != false, allowed?.contains(destination) != false else { return nil }
        if source == destination { return ([source], []) }
        var queue = [source]
        var head = 0
        var predecessors: [StateGraph.StateID: (StateGraph.StateID, String)] = [:]
        var seen: Set<StateGraph.StateID> = [source]
        while head < queue.count {
            let state = queue[head]; head += 1
            for edge in edges(from: state).sorted(by: edgeOrder) where allowed?.contains(edge.target) != false && !seen.contains(edge.target) {
                seen.insert(edge.target); predecessors[edge.target] = (state, edge.action)
                if edge.target == destination {
                    var states = [destination]; var actions: [String] = []; var current = destination
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
        var index = 0; var indices: [StateGraph.StateID: Int] = [:]; var lowlinks: [StateGraph.StateID: Int] = [:]
        var stack: [StateGraph.StateID] = []; var onStack: Set<StateGraph.StateID> = []; var result: [Set<StateGraph.StateID>] = []
        func visit(_ state: StateGraph.StateID) {
            indices[state] = index; lowlinks[state] = index; index += 1; stack.append(state); onStack.insert(state)
            for edge in edges(from: state).sorted(by: edgeOrder) where allowed.contains(edge.target) {
                if indices[edge.target] == nil {
                    visit(edge.target)
                    lowlinks[state] = min(lowlinks[state]!, lowlinks[edge.target]!)
                } else if onStack.contains(edge.target) {
                    lowlinks[state] = min(lowlinks[state]!, indices[edge.target]!)
                }
            }
            if lowlinks[state] == indices[state] {
                var component: Set<StateGraph.StateID> = []
                while let node = stack.popLast() { onStack.remove(node); component.insert(node); if node == state { break } }
                result.append(component)
            }
        }
        for state in allowed.sorted(by: stateOrder) where indices[state] == nil { visit(state) }
        return result
    }

    private func explicitEdges(from state: StateGraph.StateID) -> [GraphEdge] {
        (graph.transitions[state] ?? []).map { .init(source: state, action: $0.action, target: $0.target, isStutter: false) }
    }

    private func edges(from state: StateGraph.StateID) -> [GraphEdge] {
        explicitEdges(from: state) + [.init(source: state, action: "[stutter]", target: state, isStutter: true)]
    }
}

private struct LassoSearch {
    let cycleStates: Set<StateGraph.StateID>
    let prefixStates: Set<StateGraph.StateID>
    let prefixContinuationStates: Set<StateGraph.StateID>?
    let cycleRequiredStates: Set<StateGraph.StateID>

    init(
        cycleStates: Set<StateGraph.StateID>,
        prefixStates: Set<StateGraph.StateID>,
        prefixContinuationStates: Set<StateGraph.StateID>? = nil,
        cycleRequiredStates: Set<StateGraph.StateID>
    ) {
        self.cycleStates = cycleStates
        self.prefixStates = prefixStates
        self.prefixContinuationStates = prefixContinuationStates
        self.cycleRequiredStates = cycleRequiredStates
    }
}

private struct GraphEdge: Hashable {
    let source: StateGraph.StateID
    let action: String
    let target: StateGraph.StateID
    let isStutter: Bool
}

private struct CycleSearchConfiguration: Hashable {
    let state: StateGraph.StateID
    let visitedRequiredState: Bool
    let takenActions: Set<String>
    let disabledActions: Set<String>
    let enabledActions: Set<String>

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

private struct CycleSearchPath: Hashable {
    let states: [StateGraph.StateID]
    let actions: [String]
}

private func stateOrder(_ lhs: StateGraph.StateID, _ rhs: StateGraph.StateID) -> Bool { lhs.id < rhs.id }
private func edgeOrder(_ lhs: GraphEdge, _ rhs: GraphEdge) -> Bool {
    if lhs.action != rhs.action { return lhs.action < rhs.action }
    if lhs.target.id != rhs.target.id { return lhs.target.id < rhs.target.id }
    return lhs.isStutter && !rhs.isStutter
}
private func cyclePathOrder(_ lhs: CycleSearchPath, _ rhs: CycleSearchPath) -> Bool {
    let leftStates = lhs.states.map(\.id)
    let rightStates = rhs.states.map(\.id)
    if leftStates != rightStates { return leftStates.lexicographicallyPrecedes(rightStates) }
    return lhs.actions.lexicographicallyPrecedes(rhs.actions)
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
