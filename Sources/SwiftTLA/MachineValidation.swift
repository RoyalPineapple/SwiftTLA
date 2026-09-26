/// The generated machine is the execution authority for native validation.
/// This traversal retains only the seen-state index and the pending frontier;
/// callers persist evidence as events arrive.
package enum MachineValidationEvent<Machine: StateMachine> {
    case state(id: Int, snapshot: Machine.Snapshot, initial: Bool, predecessor: Int?, action: Machine.Action?)
    case edge(source: Int, action: Machine.Action, target: Int)
    case invariantFailure(property: Machine.Property, snapshot: Machine.Snapshot, predecessor: Int?, action: Machine.Action?)
    case deadlock(state: Int)
    case reachability(property: Machine.Property, snapshot: Machine.Snapshot, predecessor: Int?, action: Machine.Action?)
}

package struct MachineValidationSummary<Property: Hashable & Sendable>: Sendable {
    package enum Completion: Sendable {
        case exhausted
        case decisiveViolation
        case decisiveReachability
    }

    package let completion: Completion
    package let initialStates: Int
    package let states: Int
    package let edges: Int
    package let violatedInvariants: Set<Property>
    package let reachedProperties: Set<Property>
    package let deadlockFound: Bool
}

package enum MachineValidator {
    package static func run<Machine: StateMachine>(
        initialMachines: [Machine],
        maximumStates: Int,
        checking: ModelChecks<Machine.Property>,
        stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        emit: (MachineValidationEvent<Machine>) throws -> Void
    ) throws -> MachineValidationSummary<Machine.Property> {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard let first = initialMachines.first else { throw ExplorationError.noInitialStates }
        let supported = Set(Machine.invariantProperties).union(Machine.reachabilityProperties)
        if let unsupported = checking.properties.subtracting(supported)
            .map({ Machine.formalPropertyNames[$0] ?? String(reflecting: $0) }).sorted().first {
            throw ExplorationError.unsupportedValidationProperty(unsupported)
        }

        var context = CheckingContext(registers: try first.initialCheckingRegisters())
        var seen: [Machine.Snapshot: Int] = [:]
        var pending: [Machine?] = []
        var head = 0
        var initialCount = 0
        var edgeCount = 0
        var violated: Set<Machine.Property> = []
        var reached: Set<Machine.Property> = []
        var deadlockFound = false
        let reachability = Set(Machine.reachabilityProperties).intersection(checking.properties)

        func summary(_ completion: MachineValidationSummary<Machine.Property>.Completion)
            -> MachineValidationSummary<Machine.Property> {
            .init(completion: completion, initialStates: initialCount, states: seen.count,
                  edges: edgeCount, violatedInvariants: violated,
                  reachedProperties: reached, deadlockFound: deadlockFound)
        }

        func checkInvariants(_ machine: Machine, predecessor: Int?, action: Machine.Action?) throws -> Bool {
            let failures = try machine.violatedInvariants(checking: checking.properties)
            for property in failures {
                violated.insert(property)
                try emit(.invariantFailure(property: property, snapshot: machine.snapshot,
                                           predecessor: predecessor, action: action))
            }
            return !failures.isEmpty
        }

        func checkReachability(_ machine: Machine, predecessor: Int?, action: Machine.Action?) throws -> Bool {
            var found = false
            for property in try machine.matchedReachabilityProperties(checking: checking.properties) {
                guard reachability.contains(property) else {
                    throw ExplorationError.undeclaredReachabilityProperty(String(reflecting: property))
                }
                guard reached.insert(property).inserted else { continue }
                found = true
                try emit(.reachability(property: property, snapshot: machine.snapshot,
                                       predecessor: predecessor, action: action))
            }
            return found
        }

        func discover(_ machine: Machine, initial: Bool, predecessor: Int?, action: Machine.Action?) throws -> Int {
            let snapshot = machine.snapshot
            if let existing = seen[snapshot] { return existing }
            guard seen.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            let id = seen.count
            seen[snapshot] = id
            pending.append(machine)
            if initial { initialCount += 1 }
            try emit(.state(id: id, snapshot: snapshot, initial: initial,
                            predecessor: predecessor, action: action))
            return id
        }

        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: first) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            let reached = try checkReachability(machine, predecessor: nil, action: nil)
            let failed = try checkInvariants(machine, predecessor: nil, action: nil)
            if failed && stopOnViolation { return summary(.decisiveViolation) }
            if reached && stopOnReachability { return summary(.decisiveReachability) }
            guard try machine.satisfiesStateConstraint() else { continue }
            _ = try discover(machine, initial: true, predecessor: nil, action: nil)
        }
        guard initialCount > 0 else { throw ExplorationError.noInitialStates }

        while head < pending.count {
            try context.advanceBreadthFirstLevel()
            let layerEnd = pending.count
            while head < layerEnd {
                try Task.checkCancellation()
                let machine = pending[head]!
                let source = seen[machine.snapshot]!
                pending[head] = nil
                head += 1
                let successors = try machine.successors(checking: &context)
                if successors.isEmpty {
                    deadlockFound = true
                    try emit(.deadlock(state: source))
                    if checking.checkDeadlock && stopOnViolation { return summary(.decisiveViolation) }
                }
                for successor in successors {
                    guard successor.machine.hasSameConfiguration(as: first) else {
                        throw ExplorationError.configurationMismatch
                    }
                    // State predicates and the constraint are functions of a complete
                    // snapshot. A previously discovered target has already passed
                    // those checks; only its additional labeled edge is new.
                    if let target = seen[successor.machine.snapshot] {
                        edgeCount += 1
                        try emit(.edge(source: source, action: successor.action, target: target))
                        continue
                    }
                    let reached = try checkReachability(successor.machine, predecessor: source,
                                                        action: successor.action)
                    let failed = try checkInvariants(successor.machine, predecessor: source,
                                                     action: successor.action)
                    if failed && stopOnViolation { return summary(.decisiveViolation) }
                    if reached && stopOnReachability { return summary(.decisiveReachability) }
                    guard try successor.machine.satisfiesStateConstraint() else { continue }
                    let target = try discover(successor.machine, initial: false,
                                              predecessor: source, action: successor.action)
                    edgeCount += 1
                    try emit(.edge(source: source, action: successor.action, target: target))
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
