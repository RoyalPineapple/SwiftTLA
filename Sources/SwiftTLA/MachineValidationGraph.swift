private struct IndexedMachineEdge<Action: Hashable & Sendable>: Sendable {
    let action: Action
    let target: Int
}

/// Retains complete state values once and compact local IDs for graph topology.
package struct MachineValidationGraphCapture<Machine: StateMachine> {
    fileprivate private(set) var snapshots: [Machine.Snapshot] = []
    fileprivate private(set) var initialIDs: [Int] = []
    fileprivate private(set) var edges: [IndexedMachineEdge<Machine.Action>] = []
    fileprivate private(set) var offsets: [Int] = [0]

    package init() {}

    package mutating func observe(_ event: MachineValidationEvent<Machine>) throws {
        switch event {
        case .state(let id, let snapshot, let initial, _, _):
            guard id == snapshots.count else { throw ExplorationError.configurationMismatch }
            snapshots.append(snapshot)
            if initial { initialIDs.append(id) }
        case .edge(let source, let action, let target):
            guard snapshots.indices.contains(source), snapshots.indices.contains(target),
                  source >= offsets.count - 1 else {
                throw ExplorationError.configurationMismatch
            }
            while offsets.count <= source { offsets.append(edges.count) }
            edges.append(.init(action: action, target: target))
        default: break
        }
    }
}

/// A generated-machine graph retained only for checks that need graph topology.
/// Safety-only validation uses MachineValidator's streaming traversal instead.
public struct MachineValidationGraph<Machine: StateMachine>: Sendable {
    private let machine: Machine
    private let snapshots: [Machine.Snapshot]
    private let initialIDs: [Int]
    private let edges: [IndexedMachineEdge<Machine.Action>]
    private let offsets: [Int]
    public let behavior: ModelBehavior
    private let selectedFairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?
    private let selectedEnabledness: [Int: [Machine.Snapshot: Bool]]?

    public var initialStates: Set<Machine.Snapshot> {
        Set(initialIDs.map { snapshots[$0] })
    }

    /// Snapshot-labeled view for callers; native analysis retains compact IDs.
    public var transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]] {
        Dictionary(uniqueKeysWithValues: snapshots.indices.map { source in
            (snapshots[source], (offsets[source]..<offsets[source + 1]).map { index in
                (edges[index].action, snapshots[edges[index].target])
            })
        })
    }

    public init(initialMachines: [Machine], maximumStates: Int,
        behavior: ModelBehavior = .specification) throws {
        try self.init(initialMachines: initialMachines, maximumStates: maximumStates,
            behavior: behavior, fairness: nil)
    }

    package init(initialMachines: [Machine], maximumStates: Int, behavior: ModelBehavior,
        fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?) throws {
        guard let machine = initialMachines.first else { throw ExplorationError.noInitialStates }
        var capture = MachineValidationGraphCapture<Machine>()
        let summary = try MachineValidator.run(
            initialMachines: initialMachines, maximumStates: maximumStates,
            checking: .init(properties: [], checkDeadlock: false),
            stopOnViolation: false
        ) { event in
            try capture.observe(event)
        }
        guard case .exhausted = summary.completion else {
            throw ExplorationError.configurationMismatch
        }
        try self.init(machine: machine, capture: capture, behavior: behavior, fairness: fairness)
    }

    package init(machine: Machine, initialStates: Set<Machine.Snapshot>,
        transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]],
        behavior: ModelBehavior,
        fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?,
        enabledness: [Int: [Machine.Snapshot: Bool]]? = nil) throws {
        if let enabledness {
            guard let fairness,
                  Set(enabledness.keys) == Set(fairness.indices),
                  enabledness.values.allSatisfy({ Set($0.keys) == Set(transitions.keys) }) else {
                throw ExplorationError.configurationMismatch
            }
        }
        let states = Array(transitions.keys)
        let ids = Dictionary(uniqueKeysWithValues: states.enumerated().map { ($0.element, $0.offset) })
        guard initialStates.allSatisfy({ ids[$0] != nil }),
              transitions.values.allSatisfy({ $0.allSatisfy { ids[$0.target] != nil } }) else {
            throw ExplorationError.configurationMismatch
        }
        var capture = MachineValidationGraphCapture<Machine>()
        for (id, state) in states.enumerated() {
            try capture.observe(.state(id: id, snapshot: state,
                initial: initialStates.contains(state), predecessor: nil, action: nil))
        }
        for (source, state) in states.enumerated() {
            for edge in transitions[state]! {
                try capture.observe(.edge(source: source, action: edge.action, target: ids[edge.target]!))
            }
        }
        try self.init(machine: machine, capture: capture, behavior: behavior,
            fairness: fairness, enabledness: enabledness)
    }

    package init(machine: Machine, capture: MachineValidationGraphCapture<Machine>,
        behavior: ModelBehavior,
        fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?,
        enabledness: [Int: [Machine.Snapshot: Bool]]? = nil) throws {
        guard !capture.initialIDs.isEmpty else { throw ExplorationError.noInitialStates }
        self.machine = machine
        snapshots = capture.snapshots
        initialIDs = capture.initialIDs
        edges = capture.edges
        var completedOffsets = capture.offsets
        while completedOffsets.count <= capture.snapshots.count {
            completedOffsets.append(capture.edges.count)
        }
        offsets = completedOffsets
        self.behavior = behavior
        selectedFairness = fairness
        selectedEnabledness = enabledness
    }

    public func temporalResults(checking: Set<Machine.Property>)
        throws -> [Machine.Property: TemporalAnalysis<Machine.Snapshot, Machine.Action?>] {
        let properties = try machine.temporalProperties(checking: checking)
        guard !properties.isEmpty else { return [:] }
        let fairness = behavior == .specification ? try (selectedFairness ?? machine.fairnessConditions()) : []
        let checker = try livenessChecker(fairness: fairness)
        let snapshots = snapshots
        return try properties.mapValues { condition in
            let indexed = condition.map { predicate -> @Sendable (Int, Int) throws -> Bool in
                { source, target in try predicate(snapshots[source], snapshots[target]) }
            }
            return try checker.analyze(indexed, initialStates: initialIDs,
                renderScope: { fairness[$0].name }).map(state: { snapshots[$0] }, action: { $0 })
        }
    }

    /// Checks a native abstraction with stuttering, including its fairness.
    public func refinementFailure<Abstract: StateMachine>(
        initialMachines: [Abstract], abstractBehavior: ModelBehavior = .specification,
        mapping: (Machine.Snapshot) throws -> Abstract
    ) throws -> RefinementFailure<Machine.Snapshot, Machine.Action>? {
        guard let initial = initialMachines.first else { throw ExplorationError.noInitialStates }
        let fairness = abstractBehavior == .specification ? try initial.fairnessConditions() : []
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: initial) else {
                throw ExplorationError.configurationMismatch
            }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
        }
        let abstractInitial = Set(initialMachines.map(\.snapshot))
        let mapped = try snapshots.map { state in
            let value = try mapping(state)
            guard value.hasSameConfiguration(as: initial) else {
                throw ExplorationError.configurationMismatch
            }
            return value
        }
        for id in initialIDs where !abstractInitial.contains(mapped[id].snapshot) {
            return .initialState(snapshots[id])
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
        for source in snapshots.indices {
            try Task.checkCancellation()
            let abstract = mapped[source]
            for index in offsets[source]..<offsets[source + 1] {
                let edge = edges[index]
                let target = mapped[edge.target].snapshot
                if target == abstract.snapshot { continue }
                if try abstractSuccessors(abstract)[target] == nil {
                    return .transition(source: snapshots[source], action: edge.action,
                        target: snapshots[edge.target])
                }
            }
        }
        if !fairness.isEmpty {
            for abstract in mapped { _ = try abstractSuccessors(abstract) }
            let projections = mapped.map(\.snapshot)
            let concreteFairness = behavior == .specification ? try (selectedFairness ?? machine.fairnessConditions()) : []
            let checker = try livenessChecker(fairness: concreteFairness)
            for condition in fairness {
                try Task.checkCancellation()
                let taken = try Dictionary(uniqueKeysWithValues: successors.map { source, edges in
                    (source, Set(try edges.compactMap { target, actions in
                        try actions.contains(where: condition.matches)
                            && (condition.changes?(source, target) ?? (source != target)) ? target : nil
                    }))
                })
                let enabled = Set(projections.indices.compactMap { id in
                    taken[projections[id]]?.isEmpty == false ? id : nil
                })
                if let witness = checker.fairnessViolation(initialStates: initialIDs,
                    isStrong: condition.isStrong, enabledStates: enabled,
                    takesAction: { source, target in
                        taken[projections[source]]?.contains(projections[target]) == true
                    }) {
                    return .fairness(scope: condition.name,
                        witness: .init(prefix: witness.prefix.map { snapshots[$0] },
                            cycle: witness.cycle.map { snapshots[$0] },
                            prefixActions: witness.prefixActions,
                            cycleActions: witness.cycleActions))
                }
            }
        }
        return nil
    }

    private func livenessChecker(
        fairness: [(name: String, isStrong: Bool,
            matches: @Sendable (Machine.Action) -> Bool,
            changes: (@Sendable (Machine.Snapshot, Machine.Snapshot) throws -> Bool)?)]
    ) throws -> LivenessChecker<Int, Machine.Action, Int> {
        let snapshots = snapshots
        let actions = Dictionary(uniqueKeysWithValues: Set(edges.map(\.action)).map {
            ($0, String(describing: $0))
        })
        let progress: [[Int: Set<Int>]?] = try fairness.map { condition in
            guard let changes = condition.changes else { return nil }
            return try Dictionary(uniqueKeysWithValues: snapshots.indices.map { source in
                (source, Set(try (offsets[source]..<offsets[source + 1]).compactMap { index in
                    let edge = edges[index]
                    return try condition.matches(edge.action)
                        && changes(snapshots[source], snapshots[edge.target]) ? edge.target : nil
                }))
            })
        }
        let indexedEnabledness = selectedEnabledness.map { selected in
            let ids = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map { ($0.element, $0.offset) })
            return selected.mapValues { values in
                Dictionary(uniqueKeysWithValues: values.map { (ids[$0.key]!, $0.value) })
            }
        }
        return LivenessChecker<Int, Machine.Action, Int>(
            states: Set(snapshots.indices),
            transitions: Dictionary(uniqueKeysWithValues: snapshots.indices.map { source in
                (source, (offsets[source]..<offsets[source + 1]).map { index in
                    GraphEdge(source: source, action: edges[index].action, target: edges[index].target)
                })
            }),
            fairness: fairness.indices.map { ($0, fairness[$0].isStrong) },
            matches: { action, scope in fairness[scope].matches(action) },
            changes: { source, target, scope in
                guard let projected = progress[scope] else { return snapshots[source] != snapshots[target] }
                return projected[source]?.contains(target) == true
            },
            actionOrder: { actions[$0]! < actions[$1]! },
            stateOrder: { $0 < $1 },
            enabledness: indexedEnabledness)
    }
}
