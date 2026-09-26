/// A concrete state or edge that does not satisfy its declared abstraction.
public enum RefinementFailure<State: Hashable & Sendable, Action: Hashable & Sendable>: Equatable, Sendable {
    case initialState(State)
    case fairness(scope: String, witness: FairLassoWitness<State, Action?>)
    case transition(source: State, action: Action, target: State)
}

extension ReachabilityGraph {
    /// Checks the supplied native abstraction, allowing abstract stuttering.
    public mutating func refinementFailure<Abstract: StateMachine>(
        initialMachines: [Abstract],
        mapping: (Machine.Snapshot) throws -> Abstract
    ) throws -> RefinementFailure<Machine.Snapshot, Machine.Action>? {
        guard let initial = initialMachines.first else { throw ExplorationError.noInitialStates }
        let fairness = try initial.fairnessConditions()
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: initial) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
        }
        let abstractInitialStates = Set(initialMachines.map(\.snapshot))
        let mapped = try Dictionary(uniqueKeysWithValues: transitions.keys.map { state in
            let machine = try mapping(state)
            guard machine.hasSameConfiguration(as: initial) else { throw ExplorationError.configurationMismatch }
            return (state, machine)
        })
        for state in initialStates where !abstractInitialStates.contains(mapped[state]!.snapshot) {
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
            // Enabledness includes all abstract successors, even targets absent from the concrete graph.
            for abstract in mapped.values { _ = try abstractSuccessors(abstract) }
            let projections = mapped.mapValues(\.snapshot)
            let checker = try temporalChecker()
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
}
