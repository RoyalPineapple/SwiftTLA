package enum FiniteExplorationConfigurationError: Error, Sendable, Equatable {
    case nonPositiveStateLimit(Int)
    case nonPositivePermutationLimit(Int)
    case symmetryReductionWithoutDeclarations
    case permutationLimitExceeded(required: Int, limit: Int)
    case symmetryReductionRequiresSafetyOnly
}

package enum SymmetryReduction: Sendable, Equatable {
    case disabled
    case enabled(maximumPermutationCount: Int)
}

package struct FiniteExplorationConfiguration: Sendable, Equatable, Codable {
    package let maximumStateLimit: Int
    package let symmetryReduction: SymmetryReduction

    package init(
        maximumStateLimit: Int,
        symmetryReduction: SymmetryReduction
    ) throws {
        guard maximumStateLimit > 0 else {
            throw FiniteExplorationConfigurationError.nonPositiveStateLimit(maximumStateLimit)
        }
        if case .enabled(let maximumPermutationCount) = symmetryReduction,
           maximumPermutationCount <= 0 {
            throw FiniteExplorationConfigurationError.nonPositivePermutationLimit(
                maximumPermutationCount
            )
        }
        self.maximumStateLimit = maximumStateLimit
        self.symmetryReduction = symmetryReduction
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maximumStateLimit
        case symmetryReduction
        case maximumPermutationCount
    }

    private enum SymmetryReductionName: String, Codable {
        case disabled
        case enabled
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(validatingKeys: CodingKeys.self)
        let mode = try container.decode(SymmetryReductionName.self, forKey: .symmetryReduction)
        let symmetryReduction: SymmetryReduction
        switch mode {
        case .disabled:
            guard container.contains(.maximumPermutationCount) == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .maximumPermutationCount,
                    in: container,
                    debugDescription: "Disabled symmetry reduction cannot declare a permutation limit."
                )
            }
            symmetryReduction = .disabled
        case .enabled:
            symmetryReduction = .enabled(
                maximumPermutationCount: try container.decode(
                    Int.self,
                    forKey: .maximumPermutationCount
                )
            )
        }
        try self.init(
            maximumStateLimit: container.decode(Int.self, forKey: .maximumStateLimit),
            symmetryReduction: symmetryReduction
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maximumStateLimit, forKey: .maximumStateLimit)
        switch symmetryReduction {
        case .disabled:
            try container.encode(SymmetryReductionName.disabled, forKey: .symmetryReduction)
        case .enabled(let maximumPermutationCount):
            try container.encode(SymmetryReductionName.enabled, forKey: .symmetryReduction)
            try container.encode(maximumPermutationCount, forKey: .maximumPermutationCount)
        }
    }

    func validatePropertySupport(in compilation: CompiledSpecification) throws {
        if case .enabled = symmetryReduction,
           !compilation.semantics.behavior.temporalProperties.isEmpty || !compilation.refinements.isEmpty {
            throw FiniteExplorationConfigurationError.symmetryReductionRequiresSafetyOnly
        }
    }
}

/// Explores reachable compiled states with bounded breadth-first search.
package struct ModelChecker {
    let compilation: CompiledSpecification
    let configuration: FiniteExplorationConfiguration

    package init(
        compilation: CompiledSpecification,
        configuration: FiniteExplorationConfiguration
    ) {
        self.compilation = compilation
        self.configuration = configuration
    }

    func check() throws -> ModelCheckOutcome {
        let exploration = try explore()
        if case .invariantViolated = exploration.outcome { return exploration.outcome }
        if let refinementOutcome = try RefinementChecker(compilation: compilation).check(exploration) {
            return refinementOutcome
        }
        return exploration.outcome
    }
    func exploreGraph() throws -> StateGraph { try explore().graph }

    /// Safety violations are retained without truncating the reachable graph.
    package func explore() throws -> FiniteExploration {
        guard compilation.semantics.behavior.reachabilityProperties.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedReachabilityEvaluation, stage: .validation,
                path: "reachabilityProperties", expected: "generated native exploration for positive reachability",
                actual: "the formal parity explorer does not report positive reachability outcomes",
                nextSafeAction: "Explore the generated machine with ReachabilityGraph.")
        }
        try configuration.validatePropertySupport(in: compilation)
        let symmetry = try SymmetryPlan(
            compilation: compilation,
            reduction: configuration.symmetryReduction
        )
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        guard !initialStates.isEmpty else {
            return emptyExploration(
                outcome: .noInitialStates
            )
        }

        guard try runtime.assumeHolds(in: initialStates[0]) else {
            return emptyExploration(
                outcome: .assumptionViolated
            )
        }

        let exploration = try compiledBFS(
            runtime: runtime,
            seeds: initialStates,
            layout: compilation.layout,
            checkDeadlock: compilation.semantics.behavior.checkDeadlock,
            specificationName: compilation.description.name,
            configuration: configuration,
            symmetry: symmetry
        )
        return FiniteExploration(
            graph: exploration.graph,
            initialStateIDs: exploration.initialStateIDs,
            completion: exploration.completion,
            safetyViolations: exploration.safetyViolations,
            compilationIdentity: compilation.identity,
            configuration: configuration,
            compiledStates: exploration.compiledStates
        )
    }


    private func emptyExploration(
        outcome: ModelCheckOutcome
    ) -> FiniteExploration {
        FiniteExploration(
            graph: StateGraph(
                specName: compilation.description.name,
                variableNames: compilation.layout.variables.map(\.declaration.name),
                transitions: [:],
                states: [:]
            ),
            initialStateIDs: [],
            completion: outcome,
            compilationIdentity: compilation.identity,
            configuration: configuration,
            compiledStates: [:]
        )
    }

}

private func compiledBFS(
    runtime: CompiledRuntime,
    seeds: [CompiledState],
    layout: CompiledLayout,
    checkDeadlock: Bool,
    specificationName: String,
    configuration: FiniteExplorationConfiguration,
    symmetry: SymmetryPlan
) throws -> FiniteExploration {
    var queue: [CompiledState] = []
    var stateToID: [CompiledState: StateGraph.StateID] = [:]
    var idToState: [StateGraph.StateID: CompiledState] = [:]
    var initialStateIDs: [StateGraph.StateID] = []
    var transitions: [StateGraph.StateID: [StateGraph.Transition]] = [:]
    var predecessors: [CompiledState: (CompiledState, ActionID)] = [:]
    var nextID = 0
    var safetyViolations: [ModelCheckOutcome] = []

    func stateProjection(_ state: CompiledState) throws -> TLAStateProjection {
        try state.projection(using: layout)
    }

    func graph() throws -> StateGraph {
        var states: [StateGraph.StateID: TLAStateProjection] = [:]
        for (id, state) in idToState {
            states[id] = try stateProjection(state)
        }
        return StateGraph(
            specName: specificationName,
            variableNames: layout.variables.map(\.declaration.name),
            transitions: transitions,
            states: states
        )
    }

    func boundedExploration() throws -> FiniteExploration {
        .init(
            graph: try graph(),
            initialStateIDs: initialStateIDs,
            completion: .depthExceeded(
                statesCount: stateToID.count,
                limit: configuration.maximumStateLimit
            ),
            safetyViolations: safetyViolations,
            compilationIdentity: runtime.identity,
            configuration: configuration,
            compiledStates: idToState
        )
    }

    func replayFailure(_ actual: String) -> CompilationDiagnostic {
        .init(
            code: .compilationIdentityMismatch, stage: .checking, path: "counterexample.replay",
            expected: "a concrete initial state and enabled transitions witnessing the invariant failure",
            actual: actual,
            nextSafeAction: "Disable symmetry reduction and check that the declared symmetries preserve the model and invariant."
        )
    }

    func trace(to final: CompiledState) throws -> (state: CompiledState, steps: [TraceStep]) {
        var path: [(CompiledState, ActionID)] = []
        var current = final
        while let predecessor = predecessors[current] {
            path.append((current, predecessor.1))
            current = predecessor.0
        }
        guard var concrete = try seeds.first(where: { try symmetry.canonicalState($0) == current }) else {
            throw replayFailure("the recorded root has no concrete initial state")
        }
        var steps = [try TraceStep(state: concrete.projection(using: layout), action: "init")]
        // Canonical nodes can rename members. Replay only when producing a
        // counterexample, retaining the actual action arguments and target.
        for (target, action) in path.reversed() {
            let candidates = try runtime.successors(from: concrete).filter {
                try symmetry.canonicalState($0.state) == target
            }
            guard let successor = candidates.first(where: { $0.action == action }) ?? candidates.first else {
                throw replayFailure("no enabled concrete transition reaches the recorded successor orbit")
            }
            concrete = successor.state
            let arguments = try successor.arguments.map { try $0.rendered(using: layout) }
            steps.append(try TraceStep(
                state: concrete.projection(using: layout),
                action: formalActionCall(named: layout.actions[successor.action.ordinal].declaration.name, arguments: arguments)
            ))
        }
        return (concrete, steps)
    }

    func representative(_ state: CompiledState) throws -> CompiledState {
        try symmetry.canonicalState(state)
    }

    func checkInvariants(in state: CompiledState, witness: () throws -> (state: CompiledState, steps: [TraceStep])) throws {
        for invariant in runtime.behavior.invariants where !safetyViolations.contains(where: {
            if case .invariantViolated(let name, _, _) = $0 { name == invariant.name } else { false }
        }) {
            if try !runtime.invariantHolds(invariant, in: state) {
                let counterexample = try witness()
                guard try !runtime.invariantHolds(invariant, in: counterexample.state) else {
                    throw replayFailure("the concrete replay does not violate invariant '\(invariant.name)'")
                }
                safetyViolations.append(.invariantViolated(
                    invariant: invariant.name,
                    state: try counterexample.state.projection(using: layout),
                    trace: counterexample.steps
                ))
            }
        }
    }

    for seed in seeds {
        guard try runtime.constraintHolds(in: seed) else {
            try checkInvariants(in: seed) { (seed, [try TraceStep(state: seed.projection(using: layout), action: "init")]) }
            continue
        }
        let key = try representative(seed)
        guard stateToID[key] == nil else { continue }
        guard stateToID.count < configuration.maximumStateLimit else {
            return try boundedExploration()
        }
        let id = StateGraph.StateID(nextID)
        stateToID[key] = id
        idToState[id] = key
        queue.append(key)
        initialStateIDs.append(id)
        nextID += 1
    }

    var head = 0
    while head < queue.count {
        let current = queue[head]
        head += 1
        let key = try representative(current)
        guard let currentID = stateToID[key] else { continue }

        try checkInvariants(in: current) { try trace(to: current) }

        let successors = try runtime.successors(from: current)
        if checkDeadlock && successors.isEmpty && !safetyViolations.contains(where: {
            if case .deadlocked = $0 { true } else { false }
        }) {
            safetyViolations.append(.deadlocked(state: try current.projection(using: layout)))
        }

        for successor in successors {
            guard try runtime.constraintHolds(in: successor.state) else {
                try checkInvariants(in: successor.state) {
                    let source = try trace(to: current)
                    let target = try representative(successor.state)
                    guard let concrete = try runtime.successors(from: source.state).first(where: {
                        try $0.action == successor.action && representative($0.state) == target
                    }) else { throw replayFailure("no concrete transition reaches the excluded successor orbit") }
                    let arguments = try concrete.arguments.map { try $0.rendered(using: layout) }
                    let step = try TraceStep(state: concrete.state.projection(using: layout),
                        action: formalActionCall(named: layout.actions[concrete.action.ordinal].declaration.name, arguments: arguments))
                    return (concrete.state, source.steps + [step])
                }
                continue
            }
            let successorKey = try symmetry.canonicalState(successor.state)
            let formalArguments = try successor.arguments.map { try $0.rendered(using: layout) }
            let targetID: StateGraph.StateID
            if let existing = stateToID[successorKey] {
                targetID = existing
            } else {
                guard stateToID.count < configuration.maximumStateLimit else {
                    return try boundedExploration()
                }
                targetID = StateGraph.StateID(nextID)
                stateToID[successorKey] = targetID
                idToState[targetID] = successorKey
                predecessors[successorKey] = (
                    current,
                    successor.action
                )
                queue.append(successorKey)
                nextID += 1
            }
            let actionName = layout.actions[successor.action.ordinal].declaration.name
            transitions[currentID, default: []].append(
                .init(
                    label: .init(
                        action: successor.action,
                        formalName: actionName,
                        arguments: successor.arguments,
                        formalArguments: formalArguments
                    ),
                    target: targetID
                )
            )
        }
    }

    return .init(
        graph: try graph(),
        initialStateIDs: initialStateIDs,
        completion: initialStateIDs.isEmpty ? .noInitialStates : .ok(statesCount: stateToID.count),
        safetyViolations: safetyViolations,
        compilationIdentity: runtime.identity,
        configuration: configuration,
        compiledStates: idToState
    )
}

// MARK: - Results

/// The formal concept responsible for a model-checking failure.
package enum ModelCheckingFailureKind: String, Sendable, Equatable {
    case invariantViolated
    case deadlock
    case stateLimit
    case refinement
    case assumption
    case initialState
}

/// A model-checking failure with its state and counterexample trace.
package struct ModelCheckingDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let kind: ModelCheckingFailureKind
    public let subject: String?
    public let expected: String
    public let actual: String
    public let state: TLAStateProjection?
    public let trace: [TraceStep]
    public let nextSafeAction: String

    public init(
        kind: ModelCheckingFailureKind,
        subject: String? = nil,
        expected: String,
        actual: String,
        state: TLAStateProjection? = nil,
        trace: [TraceStep] = [],
        nextSafeAction: String
    ) {
        self.kind = kind
        self.subject = subject
        self.expected = expected
        self.actual = actual
        self.state = state
        self.trace = trace
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        let label = subject.map { " \($0)" } ?? ""
        let stateText: String
        if let state {
            stateText = " State: \(state)."
        } else {
            stateText = ""
        }
        let traceText = trace.isEmpty ? "" : " Trace: " + trace.map(\.description).joined(separator: " → ") + "."
        return "\(kind.rawValue)\(label): expected \(expected); found \(actual).\(stateText)\(traceText) Next: \(nextSafeAction)"
    }
}

package indirect enum ModelCheckOutcome: Sendable, CustomStringConvertible {
    case ok(statesCount: Int)
    case invariantViolated(invariant: String, state: TLAStateProjection, trace: [TraceStep])
    case depthExceeded(statesCount: Int, limit: Int)
    case deadlocked(state: TLAStateProjection)
    case noInitialStates
    case assumptionViolated
    case refinementViolated(refinement: String, failure: FormalRefinementFailure)
    case refinementUnproven(refinement: String, exploration: ModelCheckOutcome)

    /// The typed explanation of a failed check, including projected state and
    /// counterexample trace.
    public var diagnostic: ModelCheckingDiagnostic? {
        switch self {
        case .ok:
            return nil
        case .invariantViolated(let invariant, let state, let trace):
            return .init(
                kind: .invariantViolated,
                subject: invariant,
                expected: "the invariant to evaluate to true",
                actual: "false",
                state: state,
                trace: trace,
                nextSafeAction: "Inspect the final trace transition and revise the action guard, update, or invariant."
            )
        case .depthExceeded(let count, let limit):
            return .init(
                kind: .stateLimit,
                expected: "at most \(limit) explored states",
                actual: "\(count) states were needed before exploration completed",
                nextSafeAction: "Increase the finite exploration limit only after confirming the model bounds are intentional."
            )
        case .deadlocked(let state):
            return .init(
                kind: .deadlock,
                expected: "at least one enabled action",
                actual: "no action produced a successor",
                state: state,
                nextSafeAction: "Inspect the guards and explicit unchanged clauses for this state."
            )
        case .noInitialStates:
            return .init(
                kind: .initialState,
                expected: "at least one initial state",
                actual: "the compiled initial-state relation is empty",
                nextSafeAction: "Declare an initializer with at least one formal value."
            )
        case .assumptionViolated:
            return .init(
                kind: .assumption,
                expected: "the compiled assumption to evaluate to true",
                actual: "false",
                nextSafeAction: "Revise the assumption or its constant inputs."
            )
        case .refinementViolated(let refinement, let failure):
            switch failure {
            case .initialState(let mapped, let abstractInitialStates):
                return .init(
                    kind: .refinement,
                    subject: refinement,
                    expected: "the mapped concrete initial state to be an abstract initial state",
                    actual: "mapped state \(mapped); abstract initial states \(abstractInitialStates)",
                    state: mapped,
                    nextSafeAction: "Inspect the refinement mapping and abstract initial condition."
                )
            case .transition(let action, let source, let target, let mappedSource, let mappedTarget, let abstractSuccessors):
                return .init(
                    kind: .refinement,
                    subject: refinement,
                    expected: "an abstract successor or stuttering step for action \(action)",
                    actual: "\(source) to \(target) maps to \(mappedSource) to \(mappedTarget); abstract successors \(abstractSuccessors)",
                    state: source,
                    trace: [.init(state: target, action: action)],
                    nextSafeAction: "Inspect the refinement mapping and the named action update."
                )
            }
        case .refinementUnproven(let refinement, let exploration):
            return .init(
                kind: .stateLimit,
                subject: refinement,
                expected: "a complete exploration before refinement checking",
                actual: exploration.description,
                nextSafeAction: "Increase the declared finite bound, then rerun the refinement check."
            )
        }
    }

    public var description: String {
        switch self {
        case .ok(let count): return "OK — explored " + String(count) + " state(s)"
        case .invariantViolated:
            return diagnostic?.description ?? "Invariant violation"
        case .depthExceeded(let count, let l):
            return "DEPTH EXCEEDED — explored " + String(count) + " state(s) before hitting limit of " + String(l)
        case .deadlocked, .noInitialStates, .assumptionViolated,
             .refinementViolated:
            return diagnostic?.description ?? "Verification diagnostic unavailable"
        case .refinementUnproven:
            return diagnostic?.description ?? "Refinement is unproven"
        }
    }
}

package struct TraceStep: Sendable, Equatable, CustomStringConvertible {
    public let state: TLAStateProjection
    public let action: String
    public var description: String { "[" + action + "] " + state.description }
}
