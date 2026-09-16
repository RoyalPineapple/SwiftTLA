/// Generated transition semantics shared by application execution and exploration.
public protocol StateMachine: Sendable {
    associatedtype Snapshot: Hashable, Sendable
    associatedtype Action: Hashable, Sendable
    associatedtype Property: Hashable, CaseIterable, Sendable

    /// Complete execution state, including compiler-owned control state.
    var snapshot: Snapshot { get }
    func hasSameConfiguration(as other: Self) -> Bool
    /// Explicit conversions used by independent validation and export.
    func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection
    func formalCall(for action: Action) throws -> FormalActionCall
    static var formalPropertyNames: [Property: String] { get }
    static var checksDeadlock: Bool { get }
    func assumptionsHold() throws -> Bool
    func satisfiesStateConstraint() throws -> Bool
    func fairnessConditions() throws -> [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool)]
    func temporalProperties() throws -> [Property: TemporalCondition<@Sendable (Snapshot) throws -> Bool>]
    func violatedInvariants() throws -> [Property]
    static var reachabilityProperties: [Property] { get }
    func matchedReachabilityProperties() throws -> [Property]
    func refinementFailures(in graph: inout ReachabilityGraph<Self>) throws -> [Property: RefinementFailure<Snapshot, Action>]
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
    case undeclaredReachabilityProperty(String)
}

public enum ReachabilityOutcome<Snapshot: Hashable & Sendable>: Equatable, Sendable {
    case reached(Snapshot)
    case unreachable
}

public enum SafetyViolation<Property: Hashable & Sendable>: Hashable, Sendable {
    case invariant(Property)
    case deadlock
}

/// A complete reachable graph with native safety and temporal results for one finite configuration.
public struct ReachabilityGraph<Machine: StateMachine>: Sendable {
    private let machine: Machine
    private let predecessors: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)]
    public let safetyViolations: [Machine.Snapshot: [SafetyViolation<Machine.Property>]]
    /// States with no executable successor, before constraint filtering or check selection.
    public let deadlockedStates: Set<Machine.Snapshot>
    public let reachabilityResults: [Machine.Property: ReachabilityOutcome<Machine.Snapshot>]
    package let reachabilityTargets: [Machine.Property: Set<Machine.Snapshot>]
    public private(set) var refinementFailures: [Machine.Property: RefinementFailure<Machine.Snapshot, Machine.Action>] = [:]
    public private(set) var temporalResults: [Machine.Property: TemporalAnalysis<Machine.Snapshot, Machine.Action?>] = [:]
    private var checker: LivenessChecker<Machine.Snapshot, Machine.Action, Int>?
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
        var violations: [Machine.Snapshot: [SafetyViolation<Machine.Property>]] = [:]
        var deadlockedStates: Set<Machine.Snapshot> = []
        var reachabilityWitnesses: [Machine.Property: Machine.Snapshot] = [:]
        let reachabilityProperties = Set(Machine.reachabilityProperties)
        var reachabilityTargets = Dictionary(uniqueKeysWithValues: reachabilityProperties.map { ($0, Set<Machine.Snapshot>()) })
        let initialRoots = Set(initialMachines.map(\.snapshot))
        func recordReachability(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            for property in try machine.matchedReachabilityProperties() {
                guard reachabilityProperties.contains(property) else {
                    throw ExplorationError.undeclaredReachabilityProperty(String(reflecting: property))
                }
                reachabilityTargets[property, default: []].insert(machine.snapshot)
                guard reachabilityWitnesses[property] == nil else { continue }
                reachabilityWitnesses[property] = machine.snapshot
                if !initialRoots.contains(machine.snapshot), predecessors[machine.snapshot] == nil {
                    predecessors[machine.snapshot] = predecessor
                }
            }
        }
        func recordBoundaryViolations(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            try recordReachability(machine, from: predecessor)
            let failures = try machine.violatedInvariants().map(SafetyViolation.invariant)
            guard !failures.isEmpty, violations[machine.snapshot] == nil else { return }
            violations[machine.snapshot] = failures
            if !initialRoots.contains(machine.snapshot), predecessors[machine.snapshot] == nil { predecessors[machine.snapshot] = predecessor }
        }
        func discover(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            guard transitions[machine.snapshot] == nil else { return }
            guard transitions.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            transitions[machine.snapshot] = []
            predecessors[machine.snapshot] = predecessor
            try recordReachability(machine)
            pending.append(machine)
        }
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            guard try machine.satisfiesStateConstraint() else {
                try recordBoundaryViolations(machine)
                continue
            }
            try discover(machine)
        }
        let initialStates = Set(transitions.keys)
        guard !initialStates.isEmpty else { throw ExplorationError.noInitialStates }
        self.initialStates = initialStates
        while let machine = pending.popFirst() {
            try Task.checkCancellation()
            let successors = try machine.successors()
            var failures = try machine.violatedInvariants().map(SafetyViolation.invariant)
            if successors.isEmpty {
                deadlockedStates.insert(machine.snapshot)
                if Machine.checksDeadlock { failures.append(.deadlock) }
            }
            if !failures.isEmpty { violations[machine.snapshot] = failures }
            let retained = try successors.filter { successor in
                guard try successor.machine.satisfiesStateConstraint() else {
                    try recordBoundaryViolations(successor.machine, from: (machine.snapshot, successor.action))
                    return false
                }
                return true
            }
            for successor in retained {
                try discover(successor.machine, from: (machine.snapshot, successor.action))
            }
            transitions[machine.snapshot] = retained.map { ($0.action, $0.machine.snapshot) }
        }
        self.transitions = transitions
        self.predecessors = predecessors
        safetyViolations = violations
        self.deadlockedStates = deadlockedStates
        self.reachabilityTargets = reachabilityTargets
        reachabilityResults = Dictionary(uniqueKeysWithValues: reachabilityProperties.map { property in
            (property, reachabilityWitnesses[property].map(ReachabilityOutcome.reached) ?? .unreachable)
        })
        if !properties.isEmpty {
            let checker = try temporalChecker()
            let fairness = try initialMachine.fairnessConditions()
            temporalResults = try properties.mapValues {
                try checker.analyze($0, initialStates: Array(initialStates), renderScope: { fairness[$0].name })
            }
        }
        refinementFailures = try initialMachine.refinementFailures(in: &self)
        checker = nil
    }

    /// A shortest native execution trace, including its initial state.
    public func trace(to target: Machine.Snapshot) throws -> [(action: Machine.Action?, state: Machine.Snapshot)] {
        guard transitions[target] != nil || safetyViolations[target] != nil || reachabilityResults.values.contains(.reached(target)) else { throw ExplorationError.traceTargetNotReachable }
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
        guard transitions[snapshot] != nil || safetyViolations[snapshot] != nil || reachabilityResults.values.contains(.reached(snapshot)) else { throw ExplorationError.traceTargetNotReachable }
        return try machine.formalProjection(of: snapshot)
    }

    package func formalCall(for action: Machine.Action) throws -> FormalActionCall {
        try machine.formalCall(for: action)
    }

    mutating func temporalChecker() throws -> LivenessChecker<Machine.Snapshot, Machine.Action, Int> {
        if let checker { return checker }
        let snapshots = Array(transitions.keys)
        let stateOrder = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map { ($0.element, $0.offset) })
        let actionNames = Dictionary(uniqueKeysWithValues: Set(transitions.values.flatMap { $0.map(\.action) }).map {
            ($0, String(describing: $0))
        })
        let fairness = try machine.fairnessConditions()
        let checker = LivenessChecker<Machine.Snapshot, Machine.Action, Int>(
            states: Set(snapshots),
            transitions: Dictionary(uniqueKeysWithValues: transitions.map { source, successors in
                (source, successors.map { successor in
                    GraphEdge(source: source, action: successor.action, target: successor.target)
                })
            }),
            fairness: fairness.indices.map { ($0, fairness[$0].isStrong) },
            matches: { action, scope in fairness[scope].matches(action) },
            actionOrder: { actionNames[$0]! < actionNames[$1]! },
            stateOrder: { stateOrder[$0]! < stateOrder[$1]! }
        )
        self.checker = checker
        return checker
    }
}
