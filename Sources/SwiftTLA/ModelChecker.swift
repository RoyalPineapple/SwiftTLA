package enum FiniteExplorationConfigurationError: Error, Sendable, Equatable {
    case nonPositiveStateLimit(Int)
    case nonPositivePermutationLimit(Int)
    case symmetryReductionWithoutDeclarations
    case permutationLimitExceeded(required: Int, limit: Int)
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

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private enum SymmetryReductionName: String, Codable {
        case disabled
        case enabled
    }

    package init(from decoder: Decoder) throws {
        let actual = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        let unknown = Set(actual.allKeys.map(\.stringValue)).subtracting(known)
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown exploration field: \(unknown.sorted().joined(separator: ", "))"
                )
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        if let result = try RefinementChecker(compilation: compilation).check(exploration) {
            return result
        }
        return exploration.result
    }
    func exploreGraph() throws -> StateGraph { try explore().graph }

    package func explore() throws -> ModelExploration { try runExploration() }

    func checkLiveness() throws -> ModelCheckOutcome {
        let exploration = try explore()
        guard case .ok = exploration.result else { return exploration.result }
        guard compilation.semantics.temporalProperties.isEmpty == false else { return exploration.result }

        let analyses = try exploration.analyzeTemporalProperties(in: compilation)
        for (property, result) in zip(compilation.semantics.temporalProperties, analyses) {
            switch result.status {
            case .satisfied:
                continue
            case .violated:
                guard let witness = result.witness else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch,
                        stage: .checking,
                        path: "temporalProperties.\(property.name).witness",
                        expected: "a fair-lasso witness for the violated property",
                        actual: "the violated analysis has no witness",
                        nextSafeAction: "Explore the compiled specification again before checking liveness."
                    )
                }
                return .livenessViolated(
                    property: property.name,
                    reason: result.reason,
                    witness: witness
                )
            case .unavailable:
                return .livenessUnavailable(property: property.name, reason: result.reason)
            }
        }
        return .ok(statesCount: exploration.graph.states.count)
    }

    private func runExploration() throws -> ModelExploration {
        let symmetry = try SymmetryPlan(
            compilation: compilation,
            reduction: configuration.symmetryReduction
        )
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        guard !initialStates.isEmpty else {
            return emptyExploration(
                result: .noInitialStates
            )
        }

        guard try runtime.assumeHolds(in: initialStates[0]) else {
            return emptyExploration(
                result: .assumptionViolated
            )
        }

        let exploration = try compiledBFS(
            runtime: runtime,
            seeds: initialStates,
            layout: compilation.layout,
            checkDeadlock: compilation.semantics.checkDeadlock,
            specificationName: compilation.description.name,
            configuration: configuration,
            symmetry: symmetry
        )
        return ModelExploration(
            graph: exploration.graph,
            initialStateIDs: exploration.initialStateIDs,
            result: exploration.result,
            compilationIdentity: compilation.identity,
            configuration: configuration,
            compiledStates: exploration.compiledStates
        )
    }


    private func emptyExploration(
        result: ModelCheckOutcome
    ) -> ModelExploration {
        ModelExploration(
            graph: StateGraph(
                specName: compilation.description.name,
                variableNames: compilation.layout.variables.map(\.declaration.name),
                transitions: [:],
                states: [:]
            ),
            initialStateIDs: [],
            result: result,
            compilationIdentity: compilation.identity,
            configuration: configuration
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
) throws -> ModelExploration {
    var queue: [CompiledState] = []
    var stateToID: [CompiledState: StateGraph.StateID] = [:]
    var idToState: [StateGraph.StateID: CompiledState] = [:]
    var initialStateIDs: [StateGraph.StateID] = []
    var transitions: [StateGraph.StateID: [StateGraph.Transition]] = [:]
    var predecessors: [CompiledState: (CompiledState, String)] = [:]
    var nextID = 0

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

    func boundedResult() throws -> ModelExploration {
        .init(
            graph: try graph(),
            initialStateIDs: initialStateIDs,
            result: .depthExceeded(
                statesCount: stateToID.count,
                limit: configuration.maximumStateLimit
            ),
            compilationIdentity: runtime.compilation.identity,
            configuration: configuration,
            compiledStates: idToState
        )
    }

    func trace(to final: CompiledState, initial: CompiledState) throws -> [TraceStep] {
        var steps: [(CompiledState, String)] = []
        var current = final
        while let predecessor = predecessors[current] {
            steps.append((current, predecessor.1))
            current = predecessor.0
        }
        return try [TraceStep(state: initial.projection(using: layout), action: "init")]
            + steps.reversed().map { try TraceStep(state: $0.0.projection(using: layout), action: $0.1) }
    }

    func representative(_ state: CompiledState) throws -> CompiledState {
        try symmetry.canonicalState(state)
    }

    for seed in seeds {
        let key = try representative(seed)
        guard stateToID[key] == nil else { continue }
        guard stateToID.count < configuration.maximumStateLimit else {
            return try boundedResult()
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

        for invariant in runtime.compilation.semantics.invariants {
            guard try runtime.invariantHolds(invariant, in: current) else {
                return .init(
                    graph: try graph(),
                    initialStateIDs: initialStateIDs,
                    result: .invariantViolated(
                        invariant: invariant.name,
                        state: try current.projection(using: layout),
                        trace: try trace(to: current, initial: queue[0])
                    ),
                    compilationIdentity: runtime.compilation.identity,
                    configuration: configuration,
                    compiledStates: idToState
                )
            }
        }

        let successors = try runtime.successors(from: current)
        if checkDeadlock && successors.isEmpty {
            return .init(
                graph: try graph(),
                initialStateIDs: initialStateIDs,
                result: .deadlocked(state: try current.projection(using: layout)),
                compilationIdentity: runtime.compilation.identity,
                configuration: configuration,
                compiledStates: idToState
            )
        }

        for successor in successors {
            let successorKey = try symmetry.canonicalState(successor.state)
            let formalArguments = try successor.arguments.map { try $0.rendered(using: layout) }
            let targetID: StateGraph.StateID
            if let existing = stateToID[successorKey] {
                targetID = existing
            } else {
                guard stateToID.count < configuration.maximumStateLimit else {
                    return try boundedResult()
                }
                targetID = StateGraph.StateID(nextID)
                stateToID[successorKey] = targetID
                idToState[targetID] = successorKey
                let actionName = layout.actions[successor.action.ordinal].declaration.name
                predecessors[successorKey] = (
                    current,
                    formalActionCall(named: actionName, arguments: formalArguments)
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
                        arguments: formalArguments
                    ),
                    target: targetID
                )
            )
        }
    }

    return .init(
        graph: try graph(),
        initialStateIDs: initialStateIDs,
        result: .ok(statesCount: stateToID.count),
        compilationIdentity: runtime.compilation.identity,
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
    case liveness
    case refinement
    case assumption
    case initialState
}

/// One safely projected state in a counterexample trace.
package struct ModelTraceEvidence: Sendable, Equatable, CustomStringConvertible {
    public let action: String
    public let state: TLAStateProjection

    package init(action: String, state: TLAStateProjection) {
        self.action = action
        self.state = state
    }

    public var description: String {
        "[\(action)] \(state)"
    }
}

/// Inspection-ready evidence for a model-checking failure.
package struct ModelCheckingDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let kind: ModelCheckingFailureKind
    public let subject: String?
    public let expected: String
    public let actual: String
    public let state: TLAStateProjection?
    public let trace: [ModelTraceEvidence]
    public let nextSafeAction: String

    public init(
        kind: ModelCheckingFailureKind,
        subject: String? = nil,
        expected: String,
        actual: String,
        state: TLAStateProjection? = nil,
        trace: [ModelTraceEvidence] = [],
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
    case livenessViolated(
        property: String,
        reason: TemporalDiagnosticReason,
        witness: FairLassoWitness
    )
    case livenessUnavailable(property: String, reason: TemporalDiagnosticReason)
    case refinementViolated(refinement: String, evidence: RefinementFailureEvidence)
    case refinementUnproven(refinement: String, exploration: ModelCheckOutcome)

    /// The typed explanation of a failed check, including projected state and
    /// counterexample evidence.
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
                trace: trace.map { .init(action: $0.action, state: $0.state) },
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
        case .livenessViolated(let property, let reason, _):
            return .init(
                kind: .liveness,
                subject: property,
                expected: "the declared temporal property to hold",
                actual: reason.rawValue,
                nextSafeAction: "Inspect the lasso or fairness diagnostic and revise the temporal property or transition relation."
            )
        case .livenessUnavailable(let property, let reason):
            return .init(
                kind: .liveness,
                subject: property,
                expected: "complete typed liveness evidence",
                actual: reason.rawValue,
                nextSafeAction: "Complete the declared exploration inputs before checking the temporal property."
            )
        case .refinementViolated(let refinement, let evidence):
            switch evidence {
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
                    trace: [.init(action: action, state: target)],
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
             .livenessViolated, .livenessUnavailable, .refinementViolated:
            return diagnostic?.description ?? "Verification diagnostic unavailable"
        case .refinementUnproven:
            return diagnostic?.description ?? "Refinement is unproven"
        }
    }
}

package struct TraceStep: Sendable, CustomStringConvertible {
    public let state: TLAStateProjection
    public let action: String
    public var description: String { "[" + action + "] " + state.description }
}
