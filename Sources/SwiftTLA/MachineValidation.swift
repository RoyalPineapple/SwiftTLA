import Dispatch

/// Hashes select candidate identities; only complete identity equality identifies a state.
private struct SeenIdentities<Identity: Hashable> {
    private static var pageSize: Int { 16_384 }

    private struct Entry {
        let hash: Int
        let id: Int
    }

    private var entries = Array(repeating: Entry(hash: 0, id: -1), count: 16_384)
    private var pages: [[Identity]] = []
    private(set) var count = 0

    func id(for identity: Identity, hash: Int) -> Int? {
        let mask = entries.count - 1
        var slot = hash & mask
        while true {
            let entry = entries[slot]
            if entry.id < 0 { return nil }
            if entry.hash == hash && pages[entry.id / Self.pageSize][entry.id % Self.pageSize] == identity {
                return entry.id
            }
            slot = (slot + 1) & mask
        }
    }

    mutating func insert(_ identity: Identity, hash: Int) -> Int {
        if count >= entries.count - entries.count / 4 { grow() }
        let id = count
        if pages.isEmpty || pages[pages.count - 1].count == Self.pageSize {
            var page: [Identity] = []
            page.reserveCapacity(Self.pageSize)
            pages.append(page)
        }
        pages[pages.count - 1].append(identity)
        count += 1
        place(hash: hash, id: id)
        return id
    }

    private mutating func grow() {
        let previous = entries
        entries = Array(repeating: Entry(hash: 0, id: -1), count: previous.count * 2)
        for entry in previous where entry.id >= 0 { place(hash: entry.hash, id: entry.id) }
    }

    private mutating func place(hash: Int, id: Int) {
        let mask = entries.count - 1
        var slot = hash & mask
        while entries[slot].id >= 0 { slot = (slot + 1) & mask }
        entries[slot] = Entry(hash: hash, id: id)
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
        try runWithIdentity(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, identity: { machine, _ in machine.snapshot }, usesView: false, emit: emit)
    }

    /// The identity is a typed state function. Equal identities share one exploration node;
    /// the completed result is then a view graph, not a full-state reachability graph.
    /// Events still carry complete representative snapshots.
    public static func run<Machine: StateMachine, Identity: Hashable & Sendable>(
        initialMachines: [Machine],
        maximumStates: Int,
        checking: ModelChecks<Machine.Property>,
        stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        identity: (Machine) throws -> Identity,
        emit: (MachineValidationEvent<Machine>) throws -> Void
    ) throws -> MachineValidationSummary<Machine.Property> {
        try runWithIdentity(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, identity: { machine, _ in try identity(machine) },
            usesView: true, emit: emit)
    }

    /// The checking level is the BFS depth exposed by TLCGet("level"): initial
    /// states have level one, and a successor has its source level plus one.
    public static func run<Machine: StateMachine, Identity: Hashable & Sendable>(
        initialMachines: [Machine],
        maximumStates: Int,
        checking: ModelChecks<Machine.Property>,
        stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        identity: (Machine, Int) throws -> Identity,
        emit: (MachineValidationEvent<Machine>) throws -> Void
    ) throws -> MachineValidationSummary<Machine.Property> {
        try runWithIdentity(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, identity: identity, usesView: true, emit: emit)
    }

    private static func runWithIdentity<Machine: StateMachine, Identity: Hashable & Sendable>(
        initialMachines: [Machine],
        maximumStates: Int,
        checking: ModelChecks<Machine.Property>,
        stopOnViolation: Bool,
        stopOnReachability: Bool,
        identity: (Machine, Int) throws -> Identity,
        usesView: Bool,
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
        var seen = SeenIdentities<Identity>()
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

        func stateID(_ value: Identity) -> (Int, Int?) {
            let started = DispatchTime.now().uptimeNanoseconds
            let hash = value.hashValue
            let hashed = DispatchTime.now().uptimeNanoseconds
            let result = seen.id(for: value, hash: hash)
            let finished = DispatchTime.now().uptimeNanoseconds
            seenHashNanoseconds += hashed - started
            seenProbeNanoseconds += finished - hashed
            return (hash, result)
        }

        func checkInvariants(_ machine: Machine, atLevel level: Int, predecessor: Int?, action: Machine.Action?) throws -> Bool {
            let started = DispatchTime.now().uptimeNanoseconds
            let failures = try machine.violatedInvariants(checking: checking.properties, atLevel: level)
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

        func insertDiscovered(_ machine: Machine, snapshot: Machine.Snapshot, identity value: Identity, hash: Int,
            initial: Bool, predecessor: Int?, action: Machine.Action?) throws -> Int {
            guard seen.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            let insertStarted = DispatchTime.now().uptimeNanoseconds
            let id = seen.insert(value, hash: hash)
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
            if usesView {
                let admitted = try constraintHolds(machine)
                let snapshot = machine.snapshot
                let value = admitted ? try identity(machine, 1) : nil
                let lookup = value.map(stateID)
                if !admitted || lookup?.1 == nil {
                    let reached = try checkReachability(machine, predecessor: nil, action: nil)
                    let failed = try checkInvariants(machine, atLevel: 1, predecessor: nil, action: nil)
                    if failed && stopOnViolation { return summary(.decisiveViolation) }
                    if reached && stopOnReachability { return summary(.decisiveReachability) }
                }
                if admitted, let value, let (hash, existing) = lookup, existing == nil {
                    _ = try insertDiscovered(machine, snapshot: snapshot, identity: value, hash: hash,
                        initial: true, predecessor: nil, action: nil)
                }
                continue
            }
            let reached = try checkReachability(machine, predecessor: nil, action: nil)
            let failed = try checkInvariants(machine, atLevel: 1, predecessor: nil, action: nil)
            if failed && stopOnViolation { return summary(.decisiveViolation) }
            if reached && stopOnReachability { return summary(.decisiveReachability) }
            guard try constraintHolds(machine) else { continue }
            let snapshot = machine.snapshot
            let value = try identity(machine, 1)
            let (hash, existing) = stateID(value)
            if existing == nil {
                _ = try insertDiscovered(machine, snapshot: snapshot, identity: value, hash: hash,
                    initial: true, predecessor: nil, action: nil)
            }
        }
        guard initialCount > 0 else { throw ExplorationError.noInitialStates }

        while head < pending.count {
            try context.advanceLevel()
            let (successorLevel, overflow) = context.level.addingReportingOverflow(1)
            guard !overflow else { throw ExplorationError.levelOverflow }
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
                func inspect(_ action: Machine.Action, _ successor: Machine, permitted: Bool) throws -> Bool {
                    let processingStartedAt = DispatchTime.now().uptimeNanoseconds
                    defer {
                        processingNanoseconds += DispatchTime.now().uptimeNanoseconds - processingStartedAt
                    }
                    guard sameConfiguration(successor) else {
                        throw ExplorationError.configurationMismatch
                    }
                    if !permitted {
                        let reached = try checkReachability(successor, predecessor: source, action: action)
                        let failed = try checkInvariants(successor, atLevel: successorLevel,
                            predecessor: source, action: action)
                        if failed && stopOnViolation { decision = .decisiveViolation; return false }
                        if reached && stopOnReachability { decision = .decisiveReachability; return false }
                        return true
                    }
                    // A view can merge different complete states. Check the constraint
                    // before looking up an identity, and still check properties at the
                    // excluded boundary; an excluded successor adds no graph edge.
                    if usesView {
                        if try !constraintHolds(successor) {
                            let reached = try checkReachability(successor, predecessor: source, action: action)
                            let failed = try checkInvariants(successor, atLevel: successorLevel,
                                predecessor: source, action: action)
                            if failed && stopOnViolation { decision = .decisiveViolation; return false }
                            if reached && stopOnReachability { decision = .decisiveReachability; return false }
                            return true
                        }
                    }
                    let snapshot = successor.snapshot
                    let value = try identity(successor, successorLevel)
                    let (hash, existing) = stateID(value)
                    if let target = existing {
                        edgeCount += 1
                        try emitEvent(.edge(source: source, action: action, target: target))
                        return true
                    }
                    let reached = try checkReachability(successor, predecessor: source, action: action)
                    let failed = try checkInvariants(successor, atLevel: successorLevel, predecessor: source, action: action)
                    if failed && stopOnViolation {
                        decision = .decisiveViolation
                        return false
                    }
                    if reached && stopOnReachability {
                        decision = .decisiveReachability
                        return false
                    }
                    if !usesView {
                        if try !constraintHolds(successor) { return true }
                    }
                    let target = try insertDiscovered(successor, snapshot: snapshot, identity: value, hash: hash,
                        initial: false, predecessor: source, action: action)
                    edgeCount += 1
                    try emitEvent(.edge(source: source, action: action, target: target))
                    return true
                }
                let hasSuccessor: Bool
                if Machine.hasActionConstraint {
                    let candidates = try machine.successors(checking: &context)
                    hasSuccessor = !candidates.isEmpty
                    for (action, successor) in candidates {
                        guard sameConfiguration(successor) else { throw ExplorationError.configurationMismatch }
                        let constraintStartedAt = DispatchTime.now().uptimeNanoseconds
                        let permitted = try machine.satisfiesActionConstraint(to: successor, checking: &context)
                        let constraintDuration = DispatchTime.now().uptimeNanoseconds - constraintStartedAt
                        constraintNanoseconds += constraintDuration
                        processingNanoseconds += constraintDuration
                        if try !inspect(action, successor, permitted: permitted) { break }
                    }
                } else {
                    hasSuccessor = try machine.visitSuccessors(checking: &context) { action, successor in
                        try inspect(action, successor, permitted: true)
                    }
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
