public typealias MachineFairnessCondition<State, Action> = (
    name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool,
    changes: (@Sendable (State, State) throws -> Bool)?
)

/// Generated transition semantics shared by application execution and exploration.
public protocol StateMachine: Sendable {
    associatedtype Snapshot: Hashable, Sendable
    associatedtype Action: Hashable, Sendable
    associatedtype Property: Hashable, CaseIterable, Sendable
    associatedtype CheckingRegisters: Sendable

    /// Complete execution state, including compiler-owned control state.
    var snapshot: Snapshot { get }
    func hasSameConfiguration(as other: Self) -> Bool
    /// Explicit conversions used by independent validation and export.
    func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection
    func formalCall(for action: Action) throws -> FormalActionCall
    static var formalPropertyNames: [Property: String] { get }
    static var propertyDisplayNames: [Property: String] { get }
    static var checksDeadlock: Bool { get }
    func assumptionsHold() throws -> Bool
    func satisfiesStateConstraint() throws -> Bool
    /// A nil change predicate selects equality of the complete snapshot.
    func fairnessConditions() throws -> [MachineFairnessCondition<Snapshot, Action>]
    func temporalProperties(checking: Set<Property>) throws -> [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>]
    /// `level` is the behavior length: 1 for an initial state, then one per transition.
    func violatedInvariants(checking: Set<Property>, atLevel level: Int) throws -> [Property]
    static var invariantProperties: [Property] { get }
    static var reachabilityProperties: [Property] { get }
    static var refinementProperties: [Property] { get }
    func matchedReachabilityProperties(checking: Set<Property>) throws -> [Property]
    func refinementFailures(in graph: inout ReachabilityGraph<Self>, checking: Set<Property>) throws -> [Property: RefinementFailure<Snapshot, Action>]
    func validationRefinementFailures(in graph: inout MachineValidationGraph<Self>, checking: Set<Property>) throws -> [Property: RefinementFailure<Snapshot, Action>]
    func successors() throws -> [(action: Action, machine: Self)]
    /// Grounded action invocations, including disabled ones, in generated order.
    func actionCandidates() throws -> [Action]
    func initialCheckingRegisters() throws -> CheckingRegisters
    /// Streams generated candidates of one action; false stops after that candidate.
    func visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>,
                         _ visit: (Self) throws -> Bool) throws -> Bool
    func successors(checking context: inout CheckingContext<CheckingRegisters>) throws -> [(action: Action, machine: Self)]
    /// Visits generated transitions in order. Returning false stops after that transition.
    /// The result reports whether any transition was enabled.
    func visitSuccessors(
        checking context: inout CheckingContext<CheckingRegisters>,
        _ visit: (Action, Self) throws -> Bool
    ) throws -> Bool
}

/// A generated machine whose immutable model parameters are represented by a
/// typed configuration. Cross-model composition uses these compiled outputs;
/// it never rebuilds the referenced model from its source specification.
public struct GeneratedModelFieldIdentity: Hashable, Sendable {
    public let swiftName: String
    public let formalName: String

    public init(swiftName: String, formalName: String) {
        self.swiftName = swiftName
        self.formalName = formalName
    }
}

public protocol GeneratedModelFields: Sendable {
    static var fieldIdentities: [PartialKeyPath<Self>: GeneratedModelFieldIdentity] { get }
}

public protocol ConfiguredGeneratedModel: StateMachine {
    associatedtype Configuration: Hashable & GeneratedModelFields
    associatedtype State: Hashable & GeneratedModelFields
    var state: State { get }
    static func initialMachines(configuration: Configuration) throws -> [Self]
    static func makeMachine(_ initial: State, configuration: Configuration) throws -> Self
    static func render(configuration: Configuration) throws -> RenderedSpecification
}

extension StateMachine {
    public func visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>,
                                _ visit: (Self) throws -> Bool) throws -> Bool {
        throw ExplorationError.unsupportedActionSampling
    }
}

public enum ExplorationError: Error, Equatable, Sendable {
    case invalidStateLimit(Int)
    case invalidSimulationDepth(Int)
    case invalidSimulationTraceCount(Int)
    case simulationNotConfigured
    case stateLimitExceeded(Int)
    case levelOverflow
    case noInitialStates
    case assumptionViolated
    case configurationMismatch
    case traceTargetNotReachable
    case unsupportedRefinement(String)
    case undeclaredReachabilityProperty(String)
    case unsupportedValidationProperty(String)
    case viewRequiresStreamingValidation
    case unsupportedActionSampling
}

public enum ReachabilityOutcome<Snapshot: Hashable & Sendable>: Equatable, Sendable {
    case reached(Snapshot)
    case unreachable
}

public enum SafetyViolation<Property: Hashable & Sendable>: Hashable, Sendable {
    case invariant(Property)
    case deadlock
}

/// A decisive safety result. Other selected properties have no established verdict.
public struct SafetyCounterexample<Machine: StateMachine>: Sendable {
    public let violations: [SafetyViolation<Machine.Property>]
    public let trace: [(action: Machine.Action?, state: Machine.Snapshot)]
    public let checking: ModelChecks<Machine.Property>

    public var unevaluatedProperties: Set<Machine.Property> {
        checking.properties.subtracting(violations.compactMap {
            if case .invariant(let property) = $0 { return property }
            return nil
        })
    }
}

public enum NativeCheckResult<Machine: StateMachine>: Sendable {
    case counterexample(SafetyCounterexample<Machine>)
    case exhausted(ReachabilityGraph<Machine>)
}

private struct NativeCheckStopped<Machine: StateMachine>: Error {
    let counterexample: SafetyCounterexample<Machine>
}

private struct NativeReachabilityFound<Machine: StateMachine>: Error {
    let trace: [(action: Machine.Action?, state: Machine.Snapshot)]
}

/// A complete reachable graph with native safety and temporal results for one finite configuration.
public struct ReachabilityGraph<Machine: StateMachine>: Sendable {
    private let machine: Machine
    private let predecessors: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)]
    private let initialOrder: [Machine.Snapshot]
    public let safetyViolations: [Machine.Snapshot: [SafetyViolation<Machine.Property>]]
    /// States with no executable successor, before constraint filtering or check selection.
    public let deadlockedStates: Set<Machine.Snapshot>
    public let reachabilityResults: [Machine.Property: ReachabilityOutcome<Machine.Snapshot>]
    package let reachabilityTargets: [Machine.Property: Set<Machine.Snapshot>]
    public private(set) var refinementFailures: [Machine.Property: RefinementFailure<Machine.Snapshot, Machine.Action>] = [:]
    public private(set) var temporalResults: [Machine.Property: TemporalAnalysis<Machine.Snapshot, Machine.Action?>] = [:]
    private var checker: LivenessChecker<Machine.Snapshot, Machine.Action, Int>?
    private let selectedFairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?
    public let initialStates: Set<Machine.Snapshot>
    public let transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]]
    public let checking: ModelChecks<Machine.Property>
    public let behavior: ModelBehavior

    public init(initialMachines: [Machine], maximumStates: Int, checking: ModelChecks<Machine.Property>? = nil,
        behavior: ModelBehavior = .specification) throws {
        try self.init(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, behavior: behavior, fairness: nil)
    }

    package init(initialMachines: [Machine], maximumStates: Int, checking: ModelChecks<Machine.Property>?,
        behavior: ModelBehavior, fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?) throws {
        try self.init(initialMachines: initialMachines, maximumStates: maximumStates, checking: checking,
            behavior: behavior, fairness: fairness, stopOnViolation: false)
    }

    /// Checks generated transitions in breadth-first order and stops at a safety violation.
    public static func check(initialMachines: [Machine], maximumStates: Int,
        checking: ModelChecks<Machine.Property>? = nil, behavior: ModelBehavior = .specification) throws -> NativeCheckResult<Machine> {
        try check(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, behavior: behavior, fairness: nil)
    }

    package static func check(initialMachines: [Machine], maximumStates: Int,
        checking: ModelChecks<Machine.Property>?, behavior: ModelBehavior,
        fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?) throws -> NativeCheckResult<Machine> {
        do {
            return .exhausted(try Self(initialMachines: initialMachines, maximumStates: maximumStates,
                                      checking: checking, behavior: behavior, fairness: fairness, stopOnViolation: true))
        } catch let stopped as NativeCheckStopped<Machine> {
            return .counterexample(stopped.counterexample)
        }
    }

    package static func reachabilityWitness(initialMachines: [Machine], property: Machine.Property,
        maximumStates: Int) throws -> [(action: Machine.Action?, state: Machine.Snapshot)]? {
        guard Machine.reachabilityProperties.contains(property) else {
            throw ExplorationError.undeclaredReachabilityProperty(String(reflecting: property))
        }
        do {
            _ = try Self(initialMachines: initialMachines, maximumStates: maximumStates,
                checking: .init(properties: [property], checkDeadlock: false), behavior: .initialAndNext,
                fairness: nil, stopOnViolation: false, stopOnReachability: property)
            return nil
        } catch let found as NativeReachabilityFound<Machine> {
            return found.trace
        }
    }

    private init(initialMachines: [Machine], maximumStates: Int, checking: ModelChecks<Machine.Property>?,
        behavior: ModelBehavior, fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]?,
        stopOnViolation: Bool, stopOnReachability: Machine.Property? = nil) throws {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard let initialMachine = initialMachines.first else { throw ExplorationError.noInitialStates }
        var context = CheckingContext(registers: try initialMachine.initialCheckingRegisters())
        let checking = checking ?? ModelChecks(properties: Set(Machine.Property.allCases), checkDeadlock: Machine.checksDeadlock)
        self.checking = checking
        self.behavior = behavior
        selectedFairness = fairness
        let properties = try initialMachine.temporalProperties(checking: checking.properties)
        machine = initialMachine
        var transitions: [Machine.Snapshot: [(action: Machine.Action, target: Machine.Snapshot)]] = [:]
        var pending: [Machine] = []
        var currentLayer: [Machine] = []
        var predecessors: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)] = [:]
        var violations: [Machine.Snapshot: [SafetyViolation<Machine.Property>]] = [:]
        var deadlockedStates: Set<Machine.Snapshot> = []
        var reachabilityWitnesses: [Machine.Property: Machine.Snapshot] = [:]
        let reachabilityProperties = Set(Machine.reachabilityProperties).intersection(checking.properties)
        var reachabilityTargets = Dictionary(uniqueKeysWithValues: reachabilityProperties.map { ($0, Set<Machine.Snapshot>()) })
        let initialRoots = Set(initialMachines.map(\.snapshot))
        let retainPredecessors = stopOnViolation || stopOnReachability != nil
        func path(to snapshot: Machine.Snapshot,
                  from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil)
            -> [(action: Machine.Action?, state: Machine.Snapshot)] {
            var path: [(action: Machine.Action?, state: Machine.Snapshot)] = []
            var current = snapshot
            if !initialRoots.contains(snapshot), predecessors[snapshot] == nil, let predecessor {
                path.append((predecessor.action, current))
                current = predecessor.source
            }
            while let previous = predecessors[current] {
                path.append((previous.action, current))
                current = previous.source
            }
            path.append((nil, current))
            return path.reversed()
        }
        func stop(_ snapshot: Machine.Snapshot, failures: [SafetyViolation<Machine.Property>],
                  from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard stopOnViolation, !failures.isEmpty else { return }
            throw NativeCheckStopped(counterexample: SafetyCounterexample<Machine>(
                violations: failures, trace: path(to: snapshot, from: predecessor), checking: checking))
        }
        func checkDiscoveredState(_ machine: Machine, atLevel level: Int,
                                  from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            if let property = stopOnReachability,
               try machine.matchedReachabilityProperties(checking: [property]).contains(property) {
                throw NativeReachabilityFound<Machine>(trace: path(to: machine.snapshot, from: predecessor))
            }
            guard stopOnViolation else { return }
            try stop(machine.snapshot,
                     failures: machine.violatedInvariants(checking: checking.properties, atLevel: level).map(SafetyViolation.invariant),
                     from: predecessor)
        }
        func recordReachability(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            for property in try machine.matchedReachabilityProperties(checking: checking.properties) {
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
        func recordBoundaryViolations(_ machine: Machine, atLevel level: Int, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            try recordReachability(machine, from: predecessor)
            let failures = try machine.violatedInvariants(checking: checking.properties, atLevel: level).map(SafetyViolation.invariant)
            guard !failures.isEmpty, violations[machine.snapshot] == nil else { return }
            violations[machine.snapshot] = failures
            if !initialRoots.contains(machine.snapshot), predecessors[machine.snapshot] == nil { predecessors[machine.snapshot] = predecessor }
        }
        func discover(_ machine: Machine, from predecessor: (source: Machine.Snapshot, action: Machine.Action)? = nil) throws -> Machine.Snapshot {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            let snapshot = machine.snapshot
            if let index = transitions.index(forKey: snapshot) {
                return transitions.keys[index]
            }
            guard transitions.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            transitions[snapshot] = []
            if retainPredecessors { predecessors[snapshot] = predecessor }
            try recordReachability(machine)
            pending.append(machine)
            return snapshot
        }
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: initialMachine) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            try checkDiscoveredState(machine, atLevel: 1)
            guard try machine.satisfiesStateConstraint() else {
                try recordBoundaryViolations(machine, atLevel: 1)
                continue
            }
            _ = try discover(machine)
        }
        let initialStates = Set(transitions.keys)
        guard !initialStates.isEmpty else { throw ExplorationError.noInitialStates }
        self.initialStates = initialStates
        initialOrder = initialMachines.map(\.snapshot).filter(initialStates.contains)
        while !currentLayer.isEmpty || !pending.isEmpty {
            if currentLayer.isEmpty {
                try context.advanceLevel()
                swap(&currentLayer, &pending)
                currentLayer.reverse()
            }
            let machine = currentLayer.removeLast()
            try Task.checkCancellation()
            let successors = try machine.successors(checking: &context)
            var failures = try machine.violatedInvariants(checking: checking.properties, atLevel: context.level).map(SafetyViolation.invariant)
            if successors.isEmpty {
                deadlockedStates.insert(machine.snapshot)
                if checking.checkDeadlock { failures.append(.deadlock) }
            }
            if !failures.isEmpty { violations[machine.snapshot] = failures }
            try stop(machine.snapshot, failures: failures)
            let (successorLevel, overflow) = context.level.addingReportingOverflow(1)
            guard !overflow else { throw ExplorationError.levelOverflow }
            let retained = try successors.filter { successor in
                try checkDiscoveredState(successor.machine, atLevel: successorLevel, from: (machine.snapshot, successor.action))
                guard try successor.machine.satisfiesStateConstraint() else {
                    try recordBoundaryViolations(successor.machine, atLevel: successorLevel, from: (machine.snapshot, successor.action))
                    return false
                }
                return true
            }
            let edges = try retained.map { successor in
                (action: successor.action,
                 target: try discover(successor.machine, from: (machine.snapshot, successor.action)))
            }
            transitions[machine.snapshot] = edges
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
            let fairness = behavior == .specification ? try (selectedFairness ?? initialMachine.fairnessConditions()) : []
            temporalResults = try properties.mapValues {
                try checker.analyze($0, initialStates: Array(initialStates), renderScope: { fairness[$0].name })
            }
        }
        refinementFailures = try initialMachine.refinementFailures(in: &self, checking: checking.properties)
        checker = nil
    }

    /// A shortest native execution trace, including its initial state.
    public func trace(to target: Machine.Snapshot) throws -> [(action: Machine.Action?, state: Machine.Snapshot)] {
        guard transitions.index(forKey: target) != nil || safetyViolations.index(forKey: target) != nil || reachabilityResults.values.contains(.reached(target)) else { throw ExplorationError.traceTargetNotReachable }
        let inGraph = transitions.index(forKey: target) != nil
        let root = inGraph ? target : predecessors[target]?.source
        guard let root else { return [(nil, target)] }
        var queue = initialOrder
        var visited = Set(queue)
        var paths: [Machine.Snapshot: (source: Machine.Snapshot, action: Machine.Action)] = [:]
        var index = 0
        while !visited.contains(root), index < queue.count {
            let source = queue[index]
            index += 1
            for edge in transitions[source] ?? [] where visited.insert(edge.target).inserted {
                paths[edge.target] = (source, edge.action)
                if edge.target == root { break }
                queue.append(edge.target)
            }
        }
        guard visited.contains(root) else { throw ExplorationError.traceTargetNotReachable }
        var path: [(action: Machine.Action?, state: Machine.Snapshot)] = []
        var current = root
        while let previous = paths[current] {
            path.append((previous.action, current))
            current = previous.source
        }
        path.append((nil, current))
        path.reverse()
        if !inGraph, let boundary = predecessors[target] {
            path.append((boundary.action, target))
        }
        return path
    }
}

extension ReachabilityGraph {
    package func formalProjection(of snapshot: Machine.Snapshot) throws -> TLAStateProjection {
        guard transitions.index(forKey: snapshot) != nil || safetyViolations.index(forKey: snapshot) != nil || reachabilityResults.values.contains(.reached(snapshot)) else { throw ExplorationError.traceTargetNotReachable }
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
        let fairness = behavior == .specification ? try (selectedFairness ?? machine.fairnessConditions()) : []
        let progress: [[Machine.Snapshot: Set<Machine.Snapshot>]?] = try fairness.map { condition in
            guard let changes = condition.changes else { return nil }
            return try Dictionary(uniqueKeysWithValues: transitions.map { source, successors in
                (source, Set(try successors.filter {
                    try condition.matches($0.action) && changes(source, $0.target)
                }.map(\.target)))
            })
        }
        let checker = LivenessChecker<Machine.Snapshot, Machine.Action, Int>(
            states: Set(snapshots),
            transitions: Dictionary(uniqueKeysWithValues: transitions.map { source, successors in
                (source, successors.map { successor in
                    GraphEdge(source: source, action: successor.action, target: successor.target)
                })
            }),
            fairness: fairness.indices.map { ($0, fairness[$0].isStrong) },
            matches: { action, scope in fairness[scope].matches(action) },
            changes: { source, target, scope in
                guard let projected = progress[scope] else { return source != target }
                return projected[source]?.contains(target) == true
            },
            actionOrder: { actionNames[$0]! < actionNames[$1]! },
            stateOrder: { stateOrder[$0]! < stateOrder[$1]! }
        )
        self.checker = checker
        return checker
    }
}
