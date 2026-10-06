/// Why a sampled behavior stopped without establishing any selected check.
public enum SimulationStopReason: Equatable, Sendable {
    case maximumDepth
    case deadEnd
}

/// A sampled behavior is never a proof that its unexplored branches satisfy a property.
public enum NativeSimulationResult<Machine: StateMachine>: Sendable {
    case counterexample(SafetyCounterexample<Machine>)
    case inconclusive(trace: [(action: Machine.Action?, state: Machine.Snapshot)], reason: SimulationStopReason)
}

/// Samples generated-machine transitions without deduplicating revisited states.
public enum MachineSimulator {
    public static func run<Machine: StateMachine, Generator: RandomNumberGenerator>(
        initialMachines: [Machine], maximumDepth: Int, traceCount: Int = 1,
        checking: ModelChecks<Machine.Property>,
        using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        guard traceCount > 0 else { throw ExplorationError.invalidSimulationTraceCount(traceCount) }
        guard maximumDepth > 0 else { throw ExplorationError.invalidSimulationDepth(maximumDepth) }
        guard let first = initialMachines.first else { throw ExplorationError.noInitialStates }
        if let unsupported = checking.properties.subtracting(Machine.invariantProperties)
            .map({ Machine.formalPropertyNames[$0] ?? String(reflecting: $0) }).sorted().first {
            throw ExplorationError.unsupportedValidationProperty(unsupported)
        }
        var initialContext = CheckingContext(registers: try first.initialCheckingRegisters())
        try initialContext.advanceLevel()
        var eligibleInitial: [Machine] = []
        for machine in initialMachines {
            guard machine.hasSameConfiguration(as: first) else { throw ExplorationError.configurationMismatch }
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            let failures = try machine.violatedInvariants(checking: checking.properties, atLevel: initialContext.level)
                .map(SafetyViolation.invariant)
            if !failures.isEmpty {
                return .counterexample(.init(violations: failures, trace: [(nil, machine.snapshot)], checking: checking))
            }
            if try machine.satisfiesStateConstraint() { eligibleInitial.append(machine) }
        }
        guard !eligibleInitial.isEmpty else { throw ExplorationError.noInitialStates }

        var result = try runTrace(initialMachines: eligibleInitial, first: first, maximumDepth: maximumDepth,
            checking: checking, using: &generator)
        for _ in 1..<traceCount {
            if case .counterexample = result { return result }
            result = try runTrace(initialMachines: eligibleInitial, first: first, maximumDepth: maximumDepth,
                checking: checking, using: &generator)
        }
        return result
    }

    private static func runTrace<Machine: StateMachine, Generator: RandomNumberGenerator>(
        initialMachines: [Machine], first: Machine, maximumDepth: Int, checking: ModelChecks<Machine.Property>,
        using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        var context = CheckingContext(registers: try first.initialCheckingRegisters())
        try context.advanceLevel()
        var machine = initialMachines[Int.random(in: 0..<initialMachines.count, using: &generator)]
        var trace: [(action: Machine.Action?, state: Machine.Snapshot)] = [(nil, machine.snapshot)]
        for _ in 0..<maximumDepth {
            try Task.checkCancellation()
            let (nextLevel, overflow) = context.level.addingReportingOverflow(1)
            guard !overflow else { throw ExplorationError.levelOverflow }
            var actions = try machine.actionCandidates()
            actions.shuffle(using: &generator)
            var selected: (action: Machine.Action, successors: [Machine])?
            for action in actions {
                var eligible: [Machine] = []
                var witness: SafetyCounterexample<Machine>?
                _ = try machine.visitSuccessors(for: action, checking: &context) { successor in
                    guard successor.hasSameConfiguration(as: first) else {
                        throw ExplorationError.configurationMismatch
                    }
                    let failures = try successor.violatedInvariants(checking: checking.properties, atLevel: nextLevel)
                        .map(SafetyViolation.invariant)
                    if !failures.isEmpty {
                        witness = .init(violations: failures,
                            trace: trace + [(action, successor.snapshot)], checking: checking)
                        return false
                    }
                    if try successor.satisfiesStateConstraint() { eligible.append(successor) }
                    return true
                }
                if let witness { return .counterexample(witness) }
                if !eligible.isEmpty {
                    selected = (action, eligible)
                    break
                }
            }
            guard let selected else {
                if checking.checkDeadlock {
                    return .counterexample(.init(violations: [.deadlock], trace: trace, checking: checking))
                }
                return .inconclusive(trace: trace, reason: .deadEnd)
            }
            machine = selected.successors[Int.random(in: 0..<selected.successors.count, using: &generator)]
            trace.append((selected.action, machine.snapshot))
            try context.advanceLevel()
        }
        return .inconclusive(trace: trace, reason: .maximumDepth)
    }
}
