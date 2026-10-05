/// Why a sampled behavior stopped without establishing any selected check.
public enum SimulationStopReason: Equatable, Sendable {
    case maximumDepth
    case deadEnd
    case stateConstraint
}

/// A sampled behavior is never a proof that its unexplored branches satisfy a property.
public enum NativeSimulationResult<Machine: StateMachine>: Sendable {
    case counterexample(SafetyCounterexample<Machine>)
    case inconclusive(trace: [(action: Machine.Action?, state: Machine.Snapshot)], reason: SimulationStopReason)
}

/// Samples generated-machine transitions without deduplicating revisited states.
public enum MachineSimulator {
    public static func run<Machine: StateMachine, Generator: RandomNumberGenerator>(
        initialMachines: [Machine], maximumDepth: Int, checking: ModelChecks<Machine.Property>,
        using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        guard maximumDepth > 0 else { throw ExplorationError.invalidSimulationDepth(maximumDepth) }
        guard let first = initialMachines.first else { throw ExplorationError.noInitialStates }
        if let unsupported = checking.properties.subtracting(Machine.invariantProperties)
            .map({ Machine.formalPropertyNames[$0] ?? String(reflecting: $0) }).sorted().first {
            throw ExplorationError.unsupportedValidationProperty(unsupported)
        }
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: first) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
        }

        var machine = initialMachines[Int.random(in: 0..<initialMachines.count, using: &generator)]
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        var trace: [(action: Machine.Action?, state: Machine.Snapshot)] = [(nil, machine.snapshot)]
        try context.advanceLevel()
        while true {
            try Task.checkCancellation()
            let failures = try machine.violatedInvariants(checking: checking.properties, atLevel: context.level)
                .map(SafetyViolation.invariant)
            if !failures.isEmpty {
                return .counterexample(.init(violations: failures, trace: trace, checking: checking))
            }
            guard try machine.satisfiesStateConstraint() else {
                return .inconclusive(trace: trace, reason: .stateConstraint)
            }
            guard trace.count < maximumDepth else {
                return .inconclusive(trace: trace, reason: .maximumDepth)
            }
            let successors = try machine.successors(checking: &context)
            guard !successors.isEmpty else {
                if checking.checkDeadlock {
                    return .counterexample(.init(violations: [.deadlock], trace: trace, checking: checking))
                }
                return .inconclusive(trace: trace, reason: .deadEnd)
            }
            let successor = successors[Int.random(in: 0..<successors.count, using: &generator)]
            guard successor.machine.hasSameConfiguration(as: first) else {
                throw ExplorationError.configurationMismatch
            }
            machine = successor.machine
            trace.append((successor.action, machine.snapshot))
            try context.advanceLevel()
        }
    }
}
