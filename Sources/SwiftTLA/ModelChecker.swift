public enum FiniteExplorationConfigurationError: Error, Sendable, Equatable {
    case nonPositiveStateLimit(Int)
}

public struct FiniteExplorationConfiguration: Sendable, Equatable, Hashable {
    public let maximumStateLimit: Int

    public init(maximumStateLimit: Int) throws {
        guard maximumStateLimit > 0 else {
            throw FiniteExplorationConfigurationError.nonPositiveStateLimit(maximumStateLimit)
        }
        self.init(validatedMaximumStateLimit: maximumStateLimit)
    }

    private init(validatedMaximumStateLimit: Int) {
        self.maximumStateLimit = validatedMaximumStateLimit
    }
}

/// Explores every reachable state of a TLA+ specification with breadth-first search.
package struct ModelChecker {
    private let spec: TLASpec
    let compilation: CompiledSpecification
    let configuration: FiniteExplorationConfiguration
    let permutationProductBudget: Int

    package init(
        compilation: CompiledSpecification,
        configuration: FiniteExplorationConfiguration,
        permutationProductBudget: Int = 100_000
    ) {
        self.spec = compilation.spec
        self.compilation = compilation
        self.configuration = configuration
        self.permutationProductBudget = permutationProductBudget
    }

    func check() throws -> CheckResult {
        do {
            let exploration = try explore()
            if let result = try RefinementChecker(compilation: compilation).check(exploration) {
                return result
            }
            guard case .ok = exploration.result.underlyingOutcome else { return exploration.result }
            return exploration.result
        } catch {
            guard !spec.symmetricCollections.isEmpty else { throw error }
            return bounded(.error(String(describing: error)))
        }
    }
    func exploreGraph() throws -> StateGraph { try explore().graph }

    package func explore() throws -> ModelExplorationResult { try runExploration() }

    func checkLiveness() throws -> CheckResult {
        do {
            let exploration = try explore()
            guard case .ok = exploration.result.underlyingOutcome else { return exploration.result }
            guard !self.spec.temporalProperties.isEmpty else { return exploration.result }

            let graph = exploration.graph
            let analyses = LivenessChecker(compilation: compilation, graph: graph).analyze(
                initialStateIDs: exploration.initialStateIDs,
                isComplete: exploration.isComplete
            )
            for (property, result) in zip(self.spec.temporalProperties, analyses) {
                switch result.status {
                case .satisfied:
                    continue
                case .violated:
                    return bounded(.livenessViolated("\(property.name): \(result.reason.rawValue)"))
                case .unavailable:
                    return bounded(.error("Liveness unavailable: \(result.diagnostic ?? result.reason.rawValue)"))
                }
            }
            return bounded(.ok(statesCount: exploration.graph.states.count))
        } catch {
            guard !spec.symmetricCollections.isEmpty else { throw error }
            return bounded(.error(String(describing: error)))
        }
    }

    private func runExploration() throws -> ModelExplorationResult {
        if let validationError = validateSymmetricCollections() {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error(validationError.description))
            )
        }
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        guard !initialStates.isEmpty else {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error("No initial states"))
            )
        }

        guard try runtime.assumeHolds(in: initialStates[0]) else {
            return emptyExploration(
                self.spec,
                variableNames: self.spec.variables.map(\.name),
                result: bounded(.error("ASSUME failed"))
            )
        }

        let exploration = try compiledBFS(
            runtime: runtime,
            seeds: initialStates,
            layout: compilation.layout,
            checkDeadlock: self.spec.checkDeadlock,
            specificationName: self.spec.name,
            configuration: configuration
        )
        return ModelExplorationResult(
            graph: exploration.graph,
            initialStateIDs: exploration.initialStateIDs,
            result: bounded(exploration.result),
            compilationIdentity: compilation.identity,
            configuration: configuration
        )
    }


    private func emptyExploration(
        _ specification: TLASpec,
        variableNames: [String],
        result: CheckResult
    ) -> ModelExplorationResult {
        ModelExplorationResult(
            graph: StateGraph(
                specName: specification.name,
                variableNames: variableNames,
                transitions: [:],
                states: [:]
            ),
            initialStateIDs: [],
            result: result,
            compilationIdentity: compilation.identity,
            configuration: configuration
        )
    }

    private func bounded(_ outcome: CheckResult) -> CheckResult {
        let scopes = spec.symmetricCollections.map {
            SymmetricCollectionScope(collectionName: $0.name, verificationScope: $0.verificationScope)
        }
        return scopes.isEmpty ? outcome : .bounded(scopes: scopes, outcome: outcome)
    }

    private func validateSymmetricCollections() -> SymmetricCollectionValidationError? {
        spec.symmetricCollectionValidationError(
            permutationProductBudget: permutationProductBudget
        )
    }
}

private func compiledBFS(
    runtime: CompiledRuntime,
    seeds: [CompiledState],
    layout: CompiledLayout,
    checkDeadlock: Bool,
    specificationName: String,
    configuration: FiniteExplorationConfiguration
) throws -> ModelExplorationResult {
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

    for seed in seeds {
        let key = try runtime.canonicalState(seed)
        guard stateToID[key] == nil else { continue }
        let id = StateGraph.StateID(nextID)
        stateToID[key] = id
        idToState[id] = seed
        queue.append(seed)
        initialStateIDs.append(id)
        nextID += 1
    }

    var head = 0
    var processed = 0
    while head < queue.count {
        guard processed < configuration.maximumStateLimit else {
            return .init(
                graph: try graph(),
                initialStateIDs: initialStateIDs,
                result: .depthExceeded(statesCount: processed, limit: configuration.maximumStateLimit),
                compilationIdentity: runtime.compilation.identity,
                configuration: configuration,
                compiledStates: idToState
            )
        }
        let current = queue[head]
        head += 1
        processed += 1
        let key = try runtime.canonicalState(current)
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
            let formalArguments = try successor.arguments.map { try $0.rendered(using: layout) }
            let successorKey = try runtime.canonicalState(successor.state)
            let targetID: StateGraph.StateID
            if let existing = stateToID[successorKey] {
                targetID = existing
            } else {
                targetID = StateGraph.StateID(nextID)
                stateToID[successorKey] = targetID
                idToState[targetID] = successor.state
                let actionName = layout.actions[successor.action.ordinal].declaration.name
                predecessors[successor.state] = (
                    current,
                    formalActionCall(named: actionName, arguments: formalArguments)
                )
                queue.append(successor.state)
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
        result: .ok(statesCount: processed),
        compilationIdentity: runtime.compilation.identity,
        configuration: configuration,
        compiledStates: idToState
    )
}

// MARK: - Results

/// The class of a model-checking result that needs an engineer's attention.
/// This is deliberately a domain enum rather than a Boolean or a generic
/// error string so tooling can present the failed formal concept directly.
package enum ModelCheckingFailureKind: String, Sendable, Equatable {
    case invariantViolated
    case deadlock
    case stateLimit
    case liveness
    case refinement
    case assumption
    case initialState
    case evaluation
}

/// One safely projected state in a counterexample trace.
package struct ModelTraceEvidence: Sendable, Equatable, CustomStringConvertible {
    public let action: String
    public let state: TLAStateProjectionResult

    package init(action: String, state: TLAStateProjection) {
        self.action = action
        self.state = .projected(state)
    }

    public var description: String {
        switch state {
        case .projected(let projection): "[\(action)] \(projection)"
        case .unavailable(let diagnostic): "[\(action)] state unavailable: \(diagnostic)"
        }
    }
}

/// Inspection-ready evidence for a model-checking failure.
///
/// This companion is the public diagnostic boundary: it retains the named formal
/// property, the failing state, counterexample trace when there is one, the
/// expected condition, actual result, mutation outcome, and recovery step.
package struct ModelCheckingDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let kind: ModelCheckingFailureKind
    public let subject: String?
    public let expected: String
    public let actual: String
    public let state: TLAStateProjectionResult?
    public let trace: [ModelTraceEvidence]
    public let stateCommitted: Bool
    public let nextSafeAction: String

    public init(
        kind: ModelCheckingFailureKind,
        subject: String? = nil,
        expected: String,
        actual: String,
        state: TLAStateProjectionResult? = nil,
        trace: [ModelTraceEvidence] = [],
        stateCommitted: Bool = false,
        nextSafeAction: String
    ) {
        self.kind = kind
        self.subject = subject
        self.expected = expected
        self.actual = actual
        self.state = state
        self.trace = trace
        self.stateCommitted = stateCommitted
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        let label = subject.map { " \($0)" } ?? ""
        let stateText: String
        if let state {
            switch state {
            case .projected(let projection): stateText = " State: \(projection)."
            case .unavailable(let projectionError): stateText = " State could not be projected: \(projectionError)."
            }
        } else {
            stateText = ""
        }
        let traceText = trace.isEmpty ? "" : " Trace: " + trace.map(\.description).joined(separator: " → ") + "."
        return "\(kind.rawValue)\(label): expected \(expected); found \(actual).\(stateText)\(traceText) State was \(stateCommitted ? "committed" : "not committed"). Next: \(nextSafeAction)"
    }
}

package indirect enum CheckResult: CustomStringConvertible {
    case ok(statesCount: Int)
    case invariantViolated(invariant: String, state: TLAStateProjection, trace: [TraceStep])
    case depthExceeded(statesCount: Int, limit: Int)
    case deadlocked(state: TLAStateProjection)
    case livenessViolated(String)
    case error(String)
    case refinementViolated(refinement: String, evidence: RefinementFailureEvidence)
    case refinementUnproven(refinement: String, exploration: CheckResult)
    case bounded(scopes: [SymmetricCollectionScope], outcome: CheckResult)

    public var underlyingOutcome: CheckResult {
        if case .refinementUnproven = self { return self }
        if case .bounded(_, let outcome) = self { return outcome.underlyingOutcome }
        return self
    }

    public var boundedScopes: [SymmetricCollectionScope] {
        if case .bounded(let scopes, _) = self { return scopes }
        return []
    }

    /// The typed explanation of any non-success result. This preserves formal
    /// state and counterexample evidence without exposing the engine's raw
    /// string-keyed state map to application code.
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
                state: .projected(state),
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
                state: .projected(state),
                nextSafeAction: "Inspect the guards and explicit unchanged clauses for this state."
            )
        case .livenessViolated(let message):
            return .init(
                kind: .liveness,
                expected: "the declared temporal property to hold",
                actual: message,
                nextSafeAction: "Inspect the lasso or fairness diagnostic and revise the temporal property or transition relation."
            )
        case .error(let message):
            let kind: ModelCheckingFailureKind
            if message == "No initial states" { kind = .initialState }
            else if message == "ASSUME failed" { kind = .assumption }
            else { kind = .evaluation }
            return .init(
                kind: kind,
                expected: kind == .assumption ? "ASSUME to evaluate to true" : "a complete evaluable model-checking step",
                actual: message,
                nextSafeAction: "Inspect the named construct in the diagnostic and correct the model before rerunning verification."
            )
        case .refinementViolated(let refinement, let evidence):
            switch evidence {
            case .initialState(let mapped, let abstractInitialStates):
                return .init(
                    kind: .refinement,
                    subject: refinement,
                    expected: "the mapped concrete initial state to be an abstract initial state",
                    actual: "mapped state \(mapped); abstract initial states \(abstractInitialStates)",
                    state: .projected(mapped),
                    nextSafeAction: "Inspect the refinement mapping and abstract initial condition."
                )
            case .transition(let action, let source, let target, let mappedSource, let mappedTarget, let abstractSuccessors):
                return .init(
                    kind: .refinement,
                    subject: refinement,
                    expected: "an abstract successor or stuttering step for action \(action)",
                    actual: "\(source) to \(target) maps to \(mappedSource) to \(mappedTarget); abstract successors \(abstractSuccessors)",
                    state: .projected(source),
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
        case .bounded(_, let outcome):
            return outcome.diagnostic
        }
    }

    public var description: String {
        switch self {
        case .ok(let count): return "OK — explored " + String(count) + " state(s)"
        case .invariantViolated:
            return diagnostic?.description ?? "Invariant violation"
        case .depthExceeded(let count, let l):
            return "DEPTH EXCEEDED — explored " + String(count) + " state(s) before hitting limit of " + String(l)
        case .deadlocked, .livenessViolated, .error, .refinementViolated:
            return diagnostic?.description ?? "Verification diagnostic unavailable"
        case .refinementUnproven:
            return diagnostic?.description ?? "Refinement is unproven"
        case .bounded(let scopes, let outcome):
            return "BOUNDED VERIFICATION — " + scopes.map(\.description).joined(separator: "; ")
                + "; this does not prove larger populations\n" + outcome.description
        }
    }
}

package struct TraceStep: CustomStringConvertible {
    public let state: TLAStateProjection
    public let action: String
    public var description: String { "[" + action + "] " + state.description }
}
