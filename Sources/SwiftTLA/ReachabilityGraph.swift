/// Generated transition semantics shared by application execution and exploration.
public protocol StateMachine: Sendable {
    associatedtype Snapshot: Hashable, Sendable
    associatedtype Action: Hashable, Sendable

    /// Complete execution state, including compiler-owned control state.
    var snapshot: Snapshot { get }
    func hasSameConfiguration(as other: Self) -> Bool
    /// Explicit conversions used by independent validation and export.
    func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection
    func formalCall(for action: Action) throws -> FormalActionCall
    static var checksDeadlock: Bool { get }
    func assumptionsHold() throws -> Bool
    func fairnessConditions() -> [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool)]
    func temporalProperties() throws -> [String: TemporalCondition<@Sendable (Snapshot) throws -> Bool>]
    func violatedInvariants() throws -> [String]
    func refinementFailures(in graph: ReachabilityGraph<Self>) throws -> [String: RefinementFailure<Snapshot, Action>]
    func successors() throws -> [(action: Action, machine: Self)]
}

public enum ExplorationError: Error, Equatable, Sendable {
    case invalidStateLimit(Int)
    case stateLimitExceeded(Int)
    case noInitialStates
    case assumptionViolated
    case configurationMismatch
    case traceTargetNotReachable
    case unsupportedRefinement(String)
}

public enum SafetyViolation: Hashable, Sendable {
    case invariant(String)
    case deadlock
}

/// A complete reachable graph with native safety and temporal results for one finite configuration.
public struct ReachabilityGraph<Machine: StateMachine>: Sendable {
    private let machine: Machine
    private let predecessors: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)]
    public let safetyViolations: [Machine.Snapshot: [SafetyViolation]]
    public private(set) var refinementFailures: [String: RefinementFailure<Machine.Snapshot, Machine.Action>] = [:]
    public let temporalResults: [String: TemporalAnalysis<Machine.Snapshot, Machine.Action?>]
    public let initialStates: Set<Machine.Snapshot>
    public let transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]]

    public init(initialMachines: [Machine], maximumStates: Int) throws {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard let initialMachine = initialMachines.first else { throw ExplorationError.noInitialStates }
        let properties = try initialMachine.temporalProperties()
        machine = initialMachine
        var transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]] = [:]
        var pending: ArraySlice<Machine> = []
        var predecessors: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)] = [:]
        func discover(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            guard transitions[machine.snapshot] == nil else { return }
            guard transitions.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            transitions[machine.snapshot] = []
            predecessors[machine.snapshot] = predecessor
            pending.append(machine)
        }
        for machine in initialMachines {
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            try discover(machine)
        }
        let initialStates = Set(transitions.keys)
        self.initialStates = initialStates
        var violations: [Machine.Snapshot: [SafetyViolation]] = [:]
        while let machine = pending.popFirst() {
            try Task.checkCancellation()
            let successors = try machine.successors()
            var failures = try machine.violatedInvariants().map(SafetyViolation.invariant)
            if Machine.checksDeadlock, successors.isEmpty {
                failures.append(.deadlock)
            }
            if !failures.isEmpty { violations[machine.snapshot] = failures }
            for successor in successors {
                try discover(successor.machine, from: (machine.snapshot, successor.action))
            }
            transitions[machine.snapshot] = successors.map { ($0.action, $0.machine.snapshot) }
        }
        self.transitions = transitions
        self.predecessors = predecessors
        safetyViolations = violations
        temporalResults = try Self.analyzeTemporalProperties(
            machine: initialMachine, properties: properties, transitions: transitions, initialStates: initialStates
        )
        refinementFailures = try initialMachine.refinementFailures(in: self)
    }

    /// A shortest native execution trace, including its initial state.
    public func trace(to target: Machine.Snapshot) throws -> [(action: Machine.Action?, state: Machine.Snapshot)] {
        guard transitions[target] != nil else { throw ExplorationError.traceTargetNotReachable }
        var path: [(action: Machine.Action?, state: Machine.Snapshot)] = []
        var current = target
        while let previous = predecessors[current] {
            path.append((previous.action, current))
            current = previous.source
        }
        path.append((nil, current))
        return path.reversed()
    }
}

extension ReachabilityGraph {
    package func formalProjection(of snapshot: Machine.Snapshot) throws -> TLAStateProjection {
        guard transitions[snapshot] != nil else { throw ExplorationError.traceTargetNotReachable }
        return try machine.formalProjection(of: snapshot)
    }

    package func formalCall(for action: Machine.Action) throws -> FormalActionCall {
        try machine.formalCall(for: action)
    }

    private static func analyzeTemporalProperties(
        machine: Machine,
        properties: [String: TemporalCondition<@Sendable (Machine.Snapshot) throws -> Bool>],
        transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]],
        initialStates: Set<Machine.Snapshot>
    ) throws -> [String: TemporalAnalysis<Machine.Snapshot, Machine.Action?>] {
        guard !properties.isEmpty else { return [:] }
        let snapshots = Array(transitions.keys)
        let identities = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element, StateGraph.StateID($0.offset))
        })
        let actionNames = Dictionary(uniqueKeysWithValues: Set(transitions.values.flatMap { $0.map(\.action) }).map {
            ($0, String(describing: $0))
        })
        let fairness = machine.fairnessConditions()
        let checker = LivenessChecker<Machine.Action, Int>(
            states: Set(identities.values),
            transitions: Dictionary(uniqueKeysWithValues: transitions.map { source, successors in
                let sourceID = identities[source]!
                return (sourceID, successors.map { successor in
                    GraphEdge(source: sourceID, action: successor.action,
                        target: identities[successor.target]!)
                })
            }),
            fairness: fairness.indices.map { ($0, fairness[$0].isStrong) },
            matches: { action, scope in fairness[scope].matches(action) },
            actionOrder: { actionNames[$0]! < actionNames[$1]! }
        )
        return try properties.mapValues { property in
            let predicates = property.map { predicate -> @Sendable (StateGraph.StateID) throws -> Bool in
                { try predicate(snapshots[$0.id]) }
            }
            return try checker.analyze(
                predicates,
                initialStateIDs: initialStates.map { identities[$0]! },
                renderScope: { fairness[$0].name }
            ).map(state: { snapshots[$0.id] }, action: { $0 })
        }
    }
}
