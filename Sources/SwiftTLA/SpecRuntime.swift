public struct SpecRuntime: Sendable {
    public let spec: TLASpec
    /// Present when this runtime entered through the validated compiler gate.
    private let compiledSpecification: CompiledSpecification
    public var compilation: CompiledSpecification? { compiledSpecification }
    private let runtime: CompiledRuntime
    private let layout: CompiledLayout

    init(spec: TLASpec) throws {
        self.init(compilation: try spec.compile())
    }

    public init(compilation: CompiledSpecification) {
        self.spec = compilation.spec
        self.compiledSpecification = compilation
        self.runtime = CompiledRuntime(compilation: compilation)
        self.layout = compilation.layout
    }

    package func initialStates() throws -> [[String: TLAValue]] {
        try runtime.initialStates().map { try $0.projected(using: layout) }
    }

    public func initialStateProjections() throws -> [TLAStateProjection] {
        try initialStates().map(TLAStateProjection.init(formalValues:))
    }

    package func apply(_ invocation: TLAActionInvocation, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        let successors = try evaluatedSuccessors(invocation, from: state)
        guard let next = successors.first else {
            throw RuntimeError.actionNotEnabled(
                invocation,
                available: try availableInvocations(
                    in: state,
                    requested: invocation
                )
            )
        }
        return next
    }

    package func successors(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> [[String: TLAValue]] {
        try evaluatedSuccessors(invocation, from: state)
    }

    public func successors(
        _ invocation: TLAActionInvocation,
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        try successors(invocation, from: state.formalValues).map(TLAStateProjection.init(formalValues:))
    }

    private func evaluatedSuccessors(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue]
    ) throws -> [[String: TLAValue]] {
        let formalState: FormalState
        do {
            formalState = try FormalState(projected: state, layout: layout)
        } catch {
            throw RuntimeError.enumerationFailed(
                requested: invocation,
                evaluated: invocation,
                underlying: error
            )
        }
        guard let actionID = layout.actionID(named: invocation.name) else {
            throw RuntimeError.actionNotFound(invocation, available: try availableInvocations(in: state))
        }
        guard argumentSets(for: actionID).contains(invocation.arguments) else {
            throw RuntimeError.invalidActionArguments(invocation, available: try availableInvocations(in: state))
        }
        do {
            return try runtime.successors(for: actionID, from: formalState)
                .filter { $0.arguments == invocation.arguments }
                .map { try $0.state.projected(using: layout) }
        } catch {
            throw RuntimeError.enumerationFailed(
                requested: invocation,
                evaluated: invocation,
                underlying: error
            )
        }
    }

    package func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        try availableInvocations(in: state, requested: nil)
    }

    public func availableInvocations(in state: TLAStateProjection) throws -> [TLAActionInvocation] {
        try availableInvocations(in: state.formalValues)
    }

    private func availableInvocations(
        in state: [String: TLAValue],
        requested: TLAActionInvocation?
    ) throws -> [TLAActionInvocation] {
        let formalState: FormalState
        do {
            formalState = try FormalState(projected: state, layout: layout)
            return try runtime.successors(from: formalState).reduce(into: []) { available, successor in
                let invocation = TLAActionInvocation(
                    name: layout.actions[successor.action.ordinal].declaration.name,
                    arguments: successor.arguments
                )
                if available.last != invocation {
                    available.append(invocation)
                }
            }
        } catch {
            throw RuntimeError.enumerationFailed(
                requested: requested,
                evaluated: requested ?? .init(name: ""),
                underlying: error
            )
        }
    }

    package func actionReport(named actionName: String, in state: [String: TLAValue]) -> RuntimeActionReport {
        let requested = TLAActionInvocation(name: actionName)
        let projection: TLAStateProjectionResult
        do {
            projection = .projected(try .init(formalValues: state))
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            projection = .unavailable(diagnostic)
        } catch {
            projection = .unavailable(.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            ))
        }

        let status: RuntimeActionReport.Status
        let nextSafeAction: String
        if let action = spec.actions.first(where: { $0.name == actionName }) {
            do {
                let successors = try actionInvocations(action).flatMap {
                    try evaluatedSuccessors($0.invocation, from: state)
                }
                if successors.isEmpty {
                    status = .unavailable(
                        expected: "the guard for \(actionName) to be true",
                        actual: "the action produced no successor from this state"
                    )
                    nextSafeAction = "Apply one of the available actions, or inspect \(actionName)'s guard against this state."
                } else {
                    status = .enabled(successorCount: successors.count)
                    nextSafeAction = "Choose one returned successor and commit it through the generated machine."
                }
            } catch {
                let diagnostic = ActionEvaluationDiagnostic(code: .evaluationError, message: String(describing: error))
                status = .evaluationFailed(diagnostic)
                nextSafeAction = diagnostic.nextSafeAction
            }
        } else {
            status = .unavailable(
                expected: "a declared action named \(actionName)",
                actual: "no such action exists in specification \(spec.name)"
            )
            nextSafeAction = "Use one of the declared action names before retrying."
        }

        let availability: RuntimeActionReport.Availability
        do {
            availability = .known(try availableInvocations(
                in: state,
                requested: nil
            ))
        } catch let error as RuntimeError {
            availability = .unavailable(.init(error: error))
        } catch {
            availability = .unavailable(.init(
                code: .evaluationError,
                message: "Could not enumerate available actions: \(error)",
                nextSafeAction: "Inspect the formal state and the action guards before retrying."
            ))
        }

        return .init(
            requested: requested,
            state: projection,
            availability: availability,
            status: status,
            nextSafeAction: nextSafeAction
        )
    }

    public func actionReport(named actionName: String, in state: TLAStateProjection) -> RuntimeActionReport {
        actionReport(named: actionName, in: state.formalValues)
    }

    package func propertyOutcomes(in state: [String: TLAValue]) -> [RuntimePropertyOutcome] {
        invariantOutcomes(in: state) + spec.temporalProperties.map {
            .evaluationUnavailable(
                name: $0.name,
                diagnostic: .init(
                    code: .evaluatorUnavailable,
                    message: "Temporal properties require a complete graph evaluation"
                )
            )
        }
    }

    package func invariantOutcomes(in state: [String: TLAValue]) -> [RuntimePropertyOutcome] {
        let formalState: FormalState
        do {
            formalState = try FormalState(projected: state, layout: layout)
        } catch {
            return compiledSpecification.model.invariants.map {
                .evaluationFailed(
                    name: $0.name,
                    diagnostic: .init(code: .evaluationError, message: String(describing: error))
                )
            }
        }
        let outcomes = compiledSpecification.model.invariants.map { invariant -> RuntimePropertyOutcome in
            do {
                return try runtime.invariantHolds(invariant, in: formalState)
                    ? .satisfied(name: invariant.name)
                    : .violated(name: invariant.name)
            } catch {
                return .evaluationFailed(name: invariant.name, diagnostic: .init(code: .evaluationError, message: String(describing: error)))
            }
        }
        return outcomes
    }

    public func propertyOutcomes(in state: TLAStateProjection) -> [RuntimePropertyOutcome] {
        propertyOutcomes(in: state.formalValues)
    }

    public func invariantOutcomes(in state: TLAStateProjection) -> [RuntimePropertyOutcome] {
        invariantOutcomes(in: state.formalValues)
    }

    package func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let invariant = compiledSpecification.model.invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try runtime.invariantHolds(
            invariant,
            in: FormalState(projected: state, layout: layout)
        )
    }

    package func step(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> StepResult {
        let available = try availableInvocations(
            in: state,
            requested: invocation
        )
        guard available.contains(invocation) else {
            return .actionNotEnabled(invocation, available: available)
        }
        guard let next = try evaluatedSuccessors(
            invocation,
            from: state
        ).first else {
            return .actionNotEnabled(invocation, available: available)
        }
        let formalNext = try FormalState(projected: next, layout: layout)
        let violations = try compiledSpecification.model.invariants.compactMap { invariant in
            try runtime.invariantHolds(invariant, in: formalNext) ? nil : invariant.name
        }
        if !violations.isEmpty {
            return .invariantViolated(violations)
        }
        return .ok(next)
    }

    package enum StepResult {
        case ok([String: TLAValue])
        case actionNotEnabled(TLAActionInvocation, available: [TLAActionInvocation])
        case invariantViolated([String])
    }

    public enum RuntimeError: Error {
        case actionNotFound(TLAActionInvocation, available: [TLAActionInvocation])
        case actionNotEnabled(TLAActionInvocation, available: [TLAActionInvocation])
        case invalidActionArguments(TLAActionInvocation, available: [TLAActionInvocation])
        case enumerationFailed(
            requested: TLAActionInvocation?,
            evaluated: TLAActionInvocation,
            underlying: any Error
        )
        case evaluationUnavailable(String)
        case invariantNotFound(String)
    }

    private func argumentSets(for actionID: ActionID) -> [[TLAValue]] {
        guard let action = compiledSpecification.model.actions.first(where: { $0.id == actionID }) else {
            return []
        }
        return action.bindings.reduce([[]]) { arguments, binding in
            arguments.flatMap { prefix in binding.values.map { prefix + [$0] } }
        }
    }

    public enum RuntimePropertyOutcome: Sendable, Equatable {
        case satisfied(name: String)
        case violated(name: String)
        case evaluationFailed(name: String, diagnostic: PropertyEvaluationDiagnostic)
        case evaluationUnavailable(name: String, diagnostic: PropertyEvaluationDiagnostic)
    }

    public struct ActionEvaluationDiagnostic: Sendable, Equatable {
        public enum Code: String, Sendable, Equatable { case actionError, evaluationError, evaluatorUnavailable }
        public let code: Code
        public let message: String
        /// The safe recovery step, written for an engineer rather than the
        /// evaluator. It is retained alongside the cause instead of requiring
        /// a caller to infer recovery from a generic failure string.
        public let nextSafeAction: String

        public init(
            code: Code,
            message: String,
            nextSafeAction: String = "Inspect the reported action and formal state before retrying."
        ) {
            self.code = code
            self.message = message
            self.nextSafeAction = nextSafeAction
        }

        init(error: RuntimeError) {
            self.init(
                code: .evaluationError,
                message: error.description,
                nextSafeAction: "Inspect the requested action, its arguments, and the available alternatives before retrying."
            )
        }
    }

    public struct PropertyEvaluationDiagnostic: Sendable, Equatable {
        public enum Code: String, Sendable, Equatable { case evaluationError, evaluatorUnavailable }
        public let code: Code
        public let message: String
        public init(code: Code, message: String) { self.code = code; self.message = message }
    }

    /// A typed explanation of a runtime action query. No raw formal-state map
    /// crosses this public boundary; callers receive a validated projection or
    /// the precise reason a projection was unavailable.
    public struct RuntimeActionReport: Sendable, Equatable {
        public enum Availability: Sendable, Equatable {
            case known([TLAActionInvocation])
            case unavailable(ActionEvaluationDiagnostic)
        }

        public enum Status: Sendable, Equatable {
            case enabled(successorCount: Int)
            case unavailable(expected: String, actual: String)
            case evaluationFailed(ActionEvaluationDiagnostic)
        }

        public let requested: TLAActionInvocation
        public let state: TLAStateProjectionResult
        public let availability: Availability
        public let status: Status
        /// Runtime reports never commit state. A successful report only says
        /// successors were found; `CanonicalMachine.apply` performs a commit.
        public let stateCommitted: Bool
        public let nextSafeAction: String

        public init(
            requested: TLAActionInvocation,
            state: TLAStateProjectionResult,
            availability: Availability,
            status: Status,
            stateCommitted: Bool = false,
            nextSafeAction: String
        ) {
            self.requested = requested
            self.state = state
            self.availability = availability
            self.status = status
            self.stateCommitted = stateCommitted
            self.nextSafeAction = nextSafeAction
        }
    }
}

extension SpecRuntime.RuntimeError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .actionNotFound(let invocation, let available):
            return "Action \(invocation) was not found. Expected a declared action; available actions are \(available.map(\.description).joined(separator: ", ")). No state changed."
        case .actionNotEnabled(let invocation, let available):
            return "Action \(invocation) is unavailable in the supplied state. Expected its guard to be true; available actions are \(available.map(\.description).joined(separator: ", ")). No state changed."
        case .invalidActionArguments(let invocation, let available):
            return "Action \(invocation) has arguments outside its declared finite domain. Available invocations are \(available.map(\.description).joined(separator: ", ")). No state changed."
        case .enumerationFailed(let requested, let evaluated, let underlying):
            return "Could not evaluate \(evaluated)\(requested.map { " while resolving requested action \($0)" } ?? ""). Cause: \(underlying). No state changed."
        case .evaluationUnavailable(let message):
            return "Formal evaluation is unavailable: \(message). No state changed."
        case .invariantNotFound(let name):
            return "Invariant \(name) was not found. Expected a declared invariant with that name. No state changed."
        }
    }
}
