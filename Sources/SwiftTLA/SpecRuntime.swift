public struct SpecRuntime: Sendable {
    public let spec: TLASpec
    /// Present when this runtime entered through the validated compiler gate.
    private let compiledSpecification: CompiledSpecification
    public var compilation: CompiledSpecification? { compiledSpecification }
    private let invariants: [NamedInvariant]
    private let transitionRelation: TransitionRelation
    private let formalModuleClosure: FormalModuleClosure

    init(spec: TLASpec) throws {
        self.init(compilation: try spec.compile())
    }

    public init(compilation: CompiledSpecification) {
        let resolvedSpec = substituteConstants(compilation.spec)
        self.spec = compilation.spec
        self.compiledSpecification = compilation
        self.formalModuleClosure = compilation.formalModuleClosure
        self.invariants = resolvedSpec.invariants
        self.transitionRelation = TransitionRelation(compilation: compilation)
    }

    public func initialStates() -> [[String: TLAValue]] {
        computeInitialStates(
            spec,
            formalModuleClosure: formalModuleClosure,
            evaluationContext: StateExprEvaluationContext()
        )
    }

    public func apply(_ invocation: TLAActionInvocation, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        let successors = try successors(invocation, from: state)
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

    public func successors(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> [[String: TLAValue]] {
        try successors(invocation, from: state)
    }

    private func successors(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue]
    ) throws -> [[String: TLAValue]] {
        do {
            return try transitionRelation.successors(for: invocation, from: state).map(\.state)
        } catch {
            throw try runtimeError(
                for: error,
                requested: invocation,
                state: state
            )
        }
    }

    public func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        try availableInvocations(in: state, requested: nil)
    }

    private func availableInvocations(
        in state: [String: TLAValue],
        requested: TLAActionInvocation?
    ) throws -> [TLAActionInvocation] {
        do {
            return try transitionRelation.successors(from: state).reduce(into: []) { available, successor in
                if available.last != successor.invocation {
                    available.append(successor.invocation)
                }
            }
        } catch {
            throw try runtimeError(
                for: error,
                requested: requested,
                state: state
            )
        }
    }

    public func actionReport(named actionName: String, in state: [String: TLAValue]) -> RuntimeActionReport {
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
                    try transitionRelation.successors(
                        for: $0.invocation,
                        from: state
                    ).map(\.state)
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
            } catch let error as TransitionRelation.Error {
                let diagnostic = actionOutcomeFailureDiagnostic(error: error)
                status = .evaluationFailed(diagnostic)
                nextSafeAction = diagnostic.nextSafeAction
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

    public func propertyOutcomes(in state: [String: TLAValue]) -> [RuntimePropertyOutcome] {
        let evaluationContext = StateExprEvaluationContext()
        var outcomes = invariants.map { invariant -> RuntimePropertyOutcome in
            do {
                return try invariant.body.evaluateBool(
                    in: state,
                    runtimeFuncs: spec.runtimeFuncs,
                    recursiveFuncs: formalModuleClosure.resolvedRecursiveFuncs,
                    formalOperatorDefinitions: formalModuleClosure.resolvedFormalOperatorDefinitions,
                    evaluationContext: evaluationContext
                )
                    ? .satisfied(name: invariant.name) : .violated(name: invariant.name)
            } catch {
                return .evaluationFailed(name: invariant.name, diagnostic: .init(code: .evaluationError, message: String(describing: error)))
            }
        }
        outcomes += spec.temporalProperties.map {
            .evaluationUnavailable(
                name: $0.name,
                diagnostic: .init(
                    code: .evaluatorUnavailable,
                    message: "Temporal properties require a complete graph evaluation"
                )
            )
        }
        return outcomes
    }

    public func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let inv = invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try inv.body.evaluateBool(
            in: state,
            runtimeFuncs: spec.runtimeFuncs,
            recursiveFuncs: formalModuleClosure.resolvedRecursiveFuncs,
            formalOperatorDefinitions: formalModuleClosure.resolvedFormalOperatorDefinitions,
            evaluationContext: StateExprEvaluationContext()
        )
    }

    public func step(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> StepResult {
        let available = try availableInvocations(
            in: state,
            requested: invocation
        )
        guard available.contains(invocation) else {
            return .actionNotEnabled(invocation, available: available)
        }
        guard let next = try successors(
            invocation,
            from: state
        ).first else {
            return .actionNotEnabled(invocation, available: available)
        }
        var violations: [String] = []
        for inv in invariants {
            if !(try inv.body.evaluateBool(
                in: next,
                runtimeFuncs: spec.runtimeFuncs,
                recursiveFuncs: formalModuleClosure.resolvedRecursiveFuncs,
                formalOperatorDefinitions: formalModuleClosure.resolvedFormalOperatorDefinitions,
                evaluationContext: StateExprEvaluationContext()
            )) {
                violations.append(inv.name)
            }
        }
        if !violations.isEmpty {
            return .invariantViolated(violations)
        }
        return .ok(next)
    }

    public enum StepResult {
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

    private func runtimeError(
        for error: Swift.Error,
        requested: TLAActionInvocation?,
        state: [String: TLAValue]
    ) throws -> RuntimeError {
        guard let relationError = error as? TransitionRelation.Error else {
            return .enumerationFailed(
                requested: requested,
                evaluated: requested ?? .init(name: ""),
                underlying: error
            )
        }
        switch relationError {
        case .actionNotFound(let invocation):
            return .actionNotFound(invocation, available: try availableInvocations(
                in: state,
                requested: requested
            ))
        case .invalidActionArguments(let invocation):
            return .invalidActionArguments(invocation, available: try availableInvocations(
                in: state,
                requested: requested
            ))
        case .enumerationFailed(let invocation, let underlying):
            return .enumerationFailed(requested: requested, evaluated: invocation, underlying: underlying)
        }
    }

    private func actionOutcomeFailureDiagnostic(
        error: TransitionRelation.Error
    ) -> ActionEvaluationDiagnostic {
        guard case .enumerationFailed(_, let underlying) = error else {
            return .init(code: .evaluationError, message: String(describing: error))
        }
        if case RuntimeError.evaluationUnavailable(let message) = underlying {
            return .init(code: .evaluatorUnavailable, message: message)
        }
        if let error = underlying as? EvalError {
            return .init(code: .evaluationError, message: error.description)
        }
        if let error = underlying as? ActionError {
            return .init(code: .actionError, message: error.description)
        }
        return .init(code: .evaluationError, message: String(describing: underlying))
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
