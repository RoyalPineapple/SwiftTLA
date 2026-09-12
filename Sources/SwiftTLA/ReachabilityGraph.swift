/// Generated transition semantics shared by application execution and exploration.
public protocol StateMachine: Sendable {
    associatedtype Snapshot: Hashable, Sendable
    associatedtype Action: Hashable, Sendable

    /// Complete execution state, including compiler-owned control state.
    var snapshot: Snapshot { get }
    func successors() throws -> [(action: Action, machine: Self)]
}

public enum ExplorationError: Error, Equatable, Sendable {
    case invalidStateLimit(Int)
    case stateLimitExceeded(Int)
    case noInitialStates
}

/// A complete reachable graph for one model and finite configuration.
/// Constructing a graph does not establish its safety or temporal properties.
public struct ReachabilityGraph<Machine: StateMachine>: Sendable {
    public let initialStates: Set<Machine.Snapshot>
    public let transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]]

    public init(initialMachines: [Machine], maximumStates: Int) throws {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard !initialMachines.isEmpty else { throw ExplorationError.noInitialStates }
        var transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]] = [:]
        var pending: ArraySlice<Machine> = []
        func discover(_ machine: Machine) throws {
            guard transitions[machine.snapshot] == nil else { return }
            guard transitions.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            transitions[machine.snapshot] = []
            pending.append(machine)
        }
        for machine in initialMachines { try discover(machine) }
        initialStates = Set(transitions.keys)
        while let machine = pending.popFirst() {
            try Task.checkCancellation()
            let successors = try machine.successors()
            for successor in successors { try discover(successor.machine) }
            transitions[machine.snapshot] = successors.map { ($0.action, $0.machine.snapshot) }
        }
        self.transitions = transitions
    }
}
