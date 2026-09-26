/// A generated-machine graph retained only for checks that need graph topology.
/// Safety-only validation uses MachineValidator's streaming traversal instead.
public struct MachineValidationGraph<Machine: StateMachine>: Sendable {
    private let machine: Machine
    public let initialStates: Set<Machine.Snapshot>
    public let transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]]
    public let behavior: ModelBehavior

    public init(initialMachines: [Machine], maximumStates: Int,
        behavior: ModelBehavior = .specification) throws {
        guard let machine = initialMachines.first else { throw ExplorationError.noInitialStates }
        self.machine = machine
        self.behavior = behavior
        var snapshots: [Machine.Snapshot] = []
        var initialIDs: [Int] = []
        var edges: [(source: Int, action: Machine.Action, target: Int)] = []
        let summary = try MachineValidator.run(
            initialMachines: initialMachines, maximumStates: maximumStates,
            checking: .init(properties: [], checkDeadlock: false),
            stopOnViolation: false
        ) { event in
            switch event {
            case .state(let id, let snapshot, let initial, _, _):
                guard id == snapshots.count else { throw ExplorationError.configurationMismatch }
                snapshots.append(snapshot)
                if initial { initialIDs.append(id) }
            case .edge(let source, let action, let target):
                edges.append((source, action, target))
            default: break
            }
        }
        guard case .exhausted = summary.completion else {
            throw ExplorationError.configurationMismatch
        }
        initialStates = Set(initialIDs.map { snapshots[$0] })
        var adjacency = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0, [(action: Machine.Action, target: Machine.Snapshot)]())
        })
        for edge in edges {
            adjacency[snapshots[edge.source], default: []].append(
                (edge.action, snapshots[edge.target]))
        }
        transitions = adjacency
    }

    package func temporalResults(checking: Set<Machine.Property>)
        throws -> [Machine.Property: TemporalAnalysis<Machine.Snapshot, Machine.Action?>] {
        let properties = try machine.temporalProperties(checking: checking)
        guard !properties.isEmpty else { return [:] }
        let fairness = behavior == .specification ? try machine.fairnessConditions() : []
        let checker = try livenessChecker(fairness: fairness)
        return try properties.mapValues {
            try checker.analyze($0, initialStates: Array(initialStates),
                renderScope: { fairness[$0].name })
        }
    }

    /// Checks a native abstraction with stuttering, including its fairness.
    public func refinementFailure<Abstract: StateMachine>(
        initialMachines: [Abstract], mapping: (Machine.Snapshot) throws -> Abstract
    ) throws -> RefinementFailure<Machine.Snapshot, Machine.Action>? {
        guard let initial = initialMachines.first else { throw ExplorationError.noInitialStates }
        let fairness = try initial.fairnessConditions()
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: initial) else {
                throw ExplorationError.configurationMismatch
            }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
        }
        let abstractInitial = Set(initialMachines.map(\.snapshot))
        let mapped = try Dictionary(uniqueKeysWithValues: transitions.keys.map { state in
            let value = try mapping(state)
            guard value.hasSameConfiguration(as: initial) else {
                throw ExplorationError.configurationMismatch
            }
            return (state, value)
        })
        for state in initialStates where !abstractInitial.contains(mapped[state]!.snapshot) {
            return .initialState(state)
        }
        var successors: [Abstract.Snapshot: [Abstract.Snapshot: Set<Abstract.Action>]] = [:]
        func abstractSuccessors(_ machine: Abstract) throws -> [Abstract.Snapshot: Set<Abstract.Action>] {
            if let known = successors[machine.snapshot] { return known }
            let result = try machine.successors().reduce(into: [Abstract.Snapshot: Set<Abstract.Action>]()) {
                $0[$1.machine.snapshot, default: []].insert($1.action)
            }
            successors[machine.snapshot] = result
            return result
        }
        for (source, edges) in transitions {
            try Task.checkCancellation()
            let abstract = mapped[source]!
            for edge in edges {
                let target = mapped[edge.target]!.snapshot
                if target == abstract.snapshot { continue }
                if try abstractSuccessors(abstract)[target] == nil {
                    return .transition(source: source, action: edge.action, target: edge.target)
                }
            }
        }
        if !fairness.isEmpty {
            for abstract in mapped.values { _ = try abstractSuccessors(abstract) }
            let projections = mapped.mapValues(\.snapshot)
            let concreteFairness = behavior == .specification ? try machine.fairnessConditions() : []
            let checker = try livenessChecker(fairness: concreteFairness)
            for condition in fairness {
                try Task.checkCancellation()
                let taken = try Dictionary(uniqueKeysWithValues: successors.map { source, edges in
                    (source, Set(try edges.compactMap { target, actions in
                        try actions.contains(where: condition.matches)
                            && (condition.changes?(source, target) ?? (source != target)) ? target : nil
                    }))
                })
                let enabled = Set(projections.compactMap { state, abstract in
                    taken[abstract]?.isEmpty == false ? state : nil
                })
                if let witness = checker.fairnessViolation(initialStates: Array(initialStates),
                    isStrong: condition.isStrong, enabledStates: enabled,
                    takesAction: { source, target in
                        let from = projections[source]!
                        let to = projections[target]!
                        return taken[from]?.contains(to) == true
                    }) {
                    return .fairness(scope: condition.name, witness: witness)
                }
            }
        }
        return nil
    }

    private func livenessChecker(
        fairness: [(name: String, isStrong: Bool,
            matches: @Sendable (Machine.Action) -> Bool,
            changes: (@Sendable (Machine.Snapshot, Machine.Snapshot) throws -> Bool)?)]
    ) throws -> LivenessChecker<Machine.Snapshot, Machine.Action, Int> {
        let snapshots = Array(transitions.keys)
        let order = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map { ($0.element, $0.offset) })
        let actions = Dictionary(uniqueKeysWithValues: Set(transitions.values.flatMap {
            $0.map(\.action)
        }).map { ($0, String(describing: $0)) })
        let progress: [[Machine.Snapshot: Set<Machine.Snapshot>]?] = try fairness.map { condition in
            guard let changes = condition.changes else { return nil }
            return try Dictionary(uniqueKeysWithValues: transitions.map { source, edges in
                (source, Set(try edges.filter {
                    try condition.matches($0.action) && changes(source, $0.target)
                }.map(\.target)))
            })
        }
        return LivenessChecker<Machine.Snapshot, Machine.Action, Int>(
            states: Set(snapshots),
            transitions: Dictionary(uniqueKeysWithValues: transitions.map { source, edges in
                (source, edges.map { GraphEdge(source: source, action: $0.action, target: $0.target) })
            }),
            fairness: fairness.indices.map { ($0, fairness[$0].isStrong) },
            matches: { action, scope in fairness[scope].matches(action) },
            changes: { source, target, scope in
                guard let projected = progress[scope] else { return source != target }
                return projected[source]?.contains(target) == true
            },
            actionOrder: { actions[$0]! < actions[$1]! },
            stateOrder: { order[$0]! < order[$1]! })
    }
}
