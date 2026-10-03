import Dispatch

/// Hashes select candidate snapshots; only complete snapshot equality identifies a state.
private struct SeenSnapshots<Snapshot: Hashable> {
    private static var pageSize: Int { 16_384 }

    private var firstByHash: [Int: Int] = [:]
    private var collisions: [Int: [Int]] = [:]
    // Fixed pages keep a growing state index from copying every retained snapshot.
    private var pages: [[Snapshot]] = []
    private(set) var count = 0

    func id(for snapshot: Snapshot, hash: Int) -> Int? {
        guard let first = firstByHash[hash] else { return nil }
        if value(at: first) == snapshot { return first }
        for id in collisions[hash] ?? [] where value(at: id) == snapshot { return id }
        return nil
    }

    mutating func insert(_ snapshot: Snapshot, hash: Int) -> Int {
        let id = count
        if pages.isEmpty || pages[pages.count - 1].count == Self.pageSize {
            var page: [Snapshot] = []
            page.reserveCapacity(Self.pageSize)
            pages.append(page)
        }
        pages[pages.count - 1].append(snapshot)
        count += 1
        if firstByHash[hash] == nil {
            firstByHash[hash] = id
        } else {
            collisions[hash, default: []].append(id)
        }
        return id
    }

    private func value(at id: Int) -> Snapshot {
        pages[id / Self.pageSize][id % Self.pageSize]
    }
}

/// The generated machine is the execution authority for native validation.
/// This traversal retains only the seen-state index and the pending frontier;
/// callers persist evidence as events arrive.
public enum MachineValidationEvent<Machine: StateMachine>: Sendable {
    case state(id: Int, snapshot: Machine.Snapshot, initial: Bool, predecessor: Int?, action: Machine.Action?)
    case edge(source: Int, action: Machine.Action, target: Int)
    case invariantFailure(property: Machine.Property, snapshot: Machine.Snapshot, predecessor: Int?, action: Machine.Action?)
    case deadlock(state: Int)
    case reachability(property: Machine.Property, snapshot: Machine.Snapshot, predecessor: Int?, action: Machine.Action?)
}

public struct MachineValidationSummary<Property: Hashable & Sendable>: Sendable {
    public enum Completion: Sendable {
        case exhausted
        case decisiveViolation
        case decisiveReachability
    }

    public let completion: Completion
    public let initialStates: Int
    public let states: Int
    public let edges: Int
    public let violatedInvariants: Set<Property>
    public let reachedProperties: Set<Property>
    public let deadlockFound: Bool
    public let timing: MachineValidationTiming
}

public struct MachineValidationTiming: Sendable {
    public let elapsedNanoseconds: UInt64
    public let successorNanoseconds: UInt64
    public let invariantNanoseconds: UInt64
    public let reachabilityNanoseconds: UInt64
    public let constraintNanoseconds: UInt64
    public let seenLookupNanoseconds: UInt64
    public let seenHashNanoseconds: UInt64
    public let seenProbeNanoseconds: UInt64
    public let seenInsertNanoseconds: UInt64
    public let configurationNanoseconds: UInt64
    public let eventNanoseconds: UInt64
    public let successorCalls: Int
}

/// Checks generated Swift transitions without retaining a graph or invoking TLC.
/// A decisive result contains only the explored prefix; only `exhausted`
/// establishes that all states and edges were visited within the limit.
public enum MachineValidator {
    public static func run<Machine: StateMachine>(
        initialMachines: [Machine],
        maximumStates: Int,
        checking: ModelChecks<Machine.Property>,
        stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        emit: (MachineValidationEvent<Machine>) throws -> Void
    ) throws -> MachineValidationSummary<Machine.Property> {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard let first = initialMachines.first else { throw ExplorationError.noInitialStates }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let supported = Set(Machine.invariantProperties).union(Machine.reachabilityProperties)
        if let unsupported = checking.properties.subtracting(supported)
            .map({ Machine.formalPropertyNames[$0] ?? String(reflecting: $0) }).sorted().first {
            throw ExplorationError.unsupportedValidationProperty(unsupported)
        }

        var context = CheckingContext(registers: try first.initialCheckingRegisters())
        var seen = SeenSnapshots<Machine.Snapshot>()
        var pending: [(id: Int, machine: Machine?)] = []
        var head = 0
        var initialCount = 0
        var edgeCount = 0
        var violated: Set<Machine.Property> = []
        var reached: Set<Machine.Property> = []
        var deadlockFound = false
        var successorNanoseconds: UInt64 = 0
        var invariantNanoseconds: UInt64 = 0
        var reachabilityNanoseconds: UInt64 = 0
        var constraintNanoseconds: UInt64 = 0
        var seenHashNanoseconds: UInt64 = 0
        var seenProbeNanoseconds: UInt64 = 0
        var seenInsertNanoseconds: UInt64 = 0
        var configurationNanoseconds: UInt64 = 0
        var eventNanoseconds: UInt64 = 0
        var successorCalls = 0
        let reachability = Set(Machine.reachabilityProperties).intersection(checking.properties)

        func summary(_ completion: MachineValidationSummary<Machine.Property>.Completion)
            -> MachineValidationSummary<Machine.Property> {
            .init(completion: completion, initialStates: initialCount, states: seen.count,
                  edges: edgeCount, violatedInvariants: violated,
                  reachedProperties: reached, deadlockFound: deadlockFound,
                  timing: .init(
                    elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - startedAt,
                    successorNanoseconds: successorNanoseconds,
                    invariantNanoseconds: invariantNanoseconds,
                    reachabilityNanoseconds: reachabilityNanoseconds,
                    constraintNanoseconds: constraintNanoseconds,
                    seenLookupNanoseconds: seenHashNanoseconds + seenProbeNanoseconds,
                    seenHashNanoseconds: seenHashNanoseconds,
                    seenProbeNanoseconds: seenProbeNanoseconds,
                    seenInsertNanoseconds: seenInsertNanoseconds,
                    configurationNanoseconds: configurationNanoseconds,
                    eventNanoseconds: eventNanoseconds,
                    successorCalls: successorCalls))
        }

        func emitEvent(_ event: MachineValidationEvent<Machine>) throws {
            let started = DispatchTime.now().uptimeNanoseconds
            try emit(event)
            eventNanoseconds += DispatchTime.now().uptimeNanoseconds - started
        }

        func constraintHolds(_ machine: Machine) throws -> Bool {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = try machine.satisfiesStateConstraint()
            constraintNanoseconds += DispatchTime.now().uptimeNanoseconds - started
            return result
        }

        func sameConfiguration(_ machine: Machine) -> Bool {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = machine.hasSameConfiguration(as: first)
            configurationNanoseconds += DispatchTime.now().uptimeNanoseconds - started
            return result
        }

        func stateID(_ snapshot: Machine.Snapshot) -> (Int, Int?) {
            let started = DispatchTime.now().uptimeNanoseconds
            let hash = snapshot.hashValue
            let hashed = DispatchTime.now().uptimeNanoseconds
            let result = seen.id(for: snapshot, hash: hash)
            let finished = DispatchTime.now().uptimeNanoseconds
            seenHashNanoseconds += hashed - started
            seenProbeNanoseconds += finished - hashed
            return (hash, result)
        }

        func checkInvariants(_ machine: Machine, predecessor: Int?, action: Machine.Action?) throws -> Bool {
            let started = DispatchTime.now().uptimeNanoseconds
            let failures = try machine.violatedInvariants(checking: checking.properties)
            invariantNanoseconds += DispatchTime.now().uptimeNanoseconds - started
            for property in failures {
                violated.insert(property)
                try emitEvent(.invariantFailure(property: property, snapshot: machine.snapshot,
                                           predecessor: predecessor, action: action))
            }
            return !failures.isEmpty
        }

        func checkReachability(_ machine: Machine, predecessor: Int?, action: Machine.Action?) throws -> Bool {
            var found = false
            let started = DispatchTime.now().uptimeNanoseconds
            let matches = try machine.matchedReachabilityProperties(checking: checking.properties)
            reachabilityNanoseconds += DispatchTime.now().uptimeNanoseconds - started
            for property in matches {
                guard reachability.contains(property) else {
                    throw ExplorationError.undeclaredReachabilityProperty(String(reflecting: property))
                }
                guard reached.insert(property).inserted else { continue }
                found = true
                try emitEvent(.reachability(property: property, snapshot: machine.snapshot,
                                       predecessor: predecessor, action: action))
            }
            return found
        }

        func insertDiscovered(_ machine: Machine, snapshot: Machine.Snapshot, hash: Int,
            initial: Bool, predecessor: Int?, action: Machine.Action?) throws -> Int {
            guard seen.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            let insertStarted = DispatchTime.now().uptimeNanoseconds
            let id = seen.insert(snapshot, hash: hash)
            seenInsertNanoseconds += DispatchTime.now().uptimeNanoseconds - insertStarted
            pending.append((id, machine))
            if initial { initialCount += 1 }
            try emitEvent(.state(id: id, snapshot: snapshot, initial: initial,
                            predecessor: predecessor, action: action))
            return id
        }

        for machine in initialMachines {
            guard sameConfiguration(machine) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            let reached = try checkReachability(machine, predecessor: nil, action: nil)
            let failed = try checkInvariants(machine, predecessor: nil, action: nil)
            if failed && stopOnViolation { return summary(.decisiveViolation) }
            if reached && stopOnReachability { return summary(.decisiveReachability) }
            guard try constraintHolds(machine) else { continue }
            let snapshot = machine.snapshot
            let (hash, existing) = stateID(snapshot)
            if existing == nil {
                _ = try insertDiscovered(machine, snapshot: snapshot, hash: hash,
                    initial: true, predecessor: nil, action: nil)
            }
        }
        guard initialCount > 0 else { throw ExplorationError.noInitialStates }

        while head < pending.count {
            try context.advanceBreadthFirstLevel()
            let layerEnd = pending.count
            while head < layerEnd {
                try Task.checkCancellation()
                let source = pending[head].id
                let machine = pending[head].machine!
                pending[head].machine = nil
                head += 1
                let successorStartedAt = DispatchTime.now().uptimeNanoseconds
                var processingNanoseconds: UInt64 = 0
                var decision: MachineValidationSummary<Machine.Property>.Completion?
                let hasSuccessor = try machine.visitSuccessors(checking: &context) { action, successor in
                    let processingStartedAt = DispatchTime.now().uptimeNanoseconds
                    defer {
                        processingNanoseconds += DispatchTime.now().uptimeNanoseconds - processingStartedAt
                    }
                    guard sameConfiguration(successor) else {
                        throw ExplorationError.configurationMismatch
                    }
                    // State predicates and the constraint are functions of a complete
                    // snapshot. A previously discovered target has already passed
                    // those checks; only its additional labeled edge is new.
                    let snapshot = successor.snapshot
                    let (hash, existing) = stateID(snapshot)
                    if let target = existing {
                        edgeCount += 1
                        try emitEvent(.edge(source: source, action: action, target: target))
                        return true
                    }
                    let reached = try checkReachability(successor, predecessor: source, action: action)
                    let failed = try checkInvariants(successor, predecessor: source, action: action)
                    if failed && stopOnViolation {
                        decision = .decisiveViolation
                        return false
                    }
                    if reached && stopOnReachability {
                        decision = .decisiveReachability
                        return false
                    }
                    guard try constraintHolds(successor) else { return true }
                    let target = try insertDiscovered(successor, snapshot: snapshot, hash: hash,
                        initial: false, predecessor: source, action: action)
                    edgeCount += 1
                    try emitEvent(.edge(source: source, action: action, target: target))
                    return true
                }
                successorNanoseconds += DispatchTime.now().uptimeNanoseconds - successorStartedAt - processingNanoseconds
                successorCalls += 1
                if let decision { return summary(decision) }
                if !hasSuccessor {
                    deadlockFound = true
                    try emitEvent(.deadlock(state: source))
                    if checking.checkDeadlock && stopOnViolation { return summary(.decisiveViolation) }
                }
            }
            // The frontier has no reason to retain machines already expanded.
            if head >= 65_536 && head * 2 >= pending.count {
                pending.removeFirst(head)
                head = 0
            }
        }
        return summary(.exhausted)
    }
}
