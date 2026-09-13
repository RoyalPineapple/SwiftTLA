/// A concrete state or edge that does not satisfy its declared abstraction.
public enum RefinementFailure<State: Hashable & Sendable, Action: Hashable & Sendable>: Equatable, Sendable {
    case initialState(State)
    case transition(source: State, action: Action, target: State)
}

extension ReachabilityGraph {
    /// Checks the supplied native abstraction, allowing abstract stuttering.
    public func refinementFailure<Abstract: StateMachine>(
        named name: String,
        initialMachines: [Abstract],
        mapping: (Machine.Snapshot) throws -> Abstract
    ) throws -> RefinementFailure<Machine.Snapshot, Machine.Action>? {
        guard let initial = initialMachines.first else { throw ExplorationError.noInitialStates }
        guard initial.fairnessConditions().isEmpty else { throw ExplorationError.unsupportedRefinement(name) }
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
        var successors: [Abstract.Snapshot: Set<Abstract.Snapshot>] = [:]
        for (source, edges) in transitions {
            try Task.checkCancellation()
            let abstract = mapped[source]!
            for edge in edges {
                let target = mapped[edge.target]!.snapshot
                if target == abstract.snapshot { continue }
                if successors[abstract.snapshot] == nil {
                    successors[abstract.snapshot] = Set(try abstract.successors().map { $0.machine.snapshot })
                }
                if !successors[abstract.snapshot]!.contains(target) {
                    return .transition(source: source, action: edge.action, target: edge.target)
                }
            }
        }
        return nil
    }
}
