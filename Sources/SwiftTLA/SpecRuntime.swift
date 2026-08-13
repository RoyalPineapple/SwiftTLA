public struct SpecRuntime: Sendable {
    public typealias ActionEvaluator = @Sendable (ActionExpr, [String: TLAValue], [String]) throws -> [[String: TLAValue]]

    public let spec: TLASpec
    private let varNames: [String]
    private let actions: [NamedAction]
    private let invariants: [NamedInvariant]
    private let actionEvaluator: ActionEvaluator

    public init(
        spec: TLASpec,
        actionEvaluator: @escaping ActionEvaluator = { action, state, varNames in
            try ActionEnumerator.enumerate(action, from: state, varNames: varNames)
        }
    ) {
        self.spec = spec
        self.varNames = spec.variables.map(\.name)
        self.actions = spec.actions
        self.invariants = spec.invariants
        self.actionEvaluator = actionEvaluator
    }

    public func initialStates() -> [[String: TLAValue]] {
        computeInitialStates(spec)
    }

    public func apply(_ invocation: TLAActionInvocation, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        let successors = try successors(invocation, from: state)
        guard let next = successors.first else {
            throw RuntimeError.actionNotEnabled(invocation, available: try availableInvocations(in: state, requested: invocation))
        }
        return next
    }

    public func successors(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> [[String: TLAValue]] {
        guard let action = actions.first(where: { $0.name == invocation.name }) else {
            throw RuntimeError.actionNotFound(invocation, available: try availableInvocations(in: state, requested: invocation))
        }
        guard let variant = actionInvocations(action).first(where: { $0.invocation == invocation }) else {
            throw RuntimeError.invalidActionArguments(invocation, available: try availableInvocations(in: state, requested: invocation))
        }
        let successors: [[String: TLAValue]]
        do {
            successors = try actionEvaluator(variant.body, state, varNames)
        } catch {
            throw RuntimeError.enumerationFailed(
                requested: invocation,
                evaluated: variant.invocation,
                underlying: error
            )
        }
        return successors
    }

    public func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        try availableInvocations(in: state, requested: nil)
    }

    private func availableInvocations(
        in state: [String: TLAValue],
        requested: TLAActionInvocation?
    ) throws -> [TLAActionInvocation] {
        var available: [TLAActionInvocation] = []
        for action in actions {
            for variant in actionInvocations(action) {
                do {
                    if try !actionEvaluator(variant.body, state, varNames).isEmpty {
                        available.append(variant.invocation)
                    }
                } catch {
                    throw RuntimeError.enumerationFailed(
                        requested: requested,
                        evaluated: variant.invocation,
                        underlying: error
                    )
                }
            }
        }
        return available
    }

    /// Compatibility projection for callers that do not need parameter labels.
    public func availableActions(in state: [String: TLAValue]) -> [String] {
        (try? availableInvocations(in: state).map(\.name)) ?? []
    }

    public func actionOutcome(named actionName: String, in state: [String: TLAValue]) -> RuntimeActionOutcome {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            return .actionNotFound(actionName: actionName)
        }
        var successors: [[String: TLAValue]] = []
        for variant in actionInvocations(action) {
            do {
                successors += try actionEvaluator(variant.body, state, varNames)
            } catch RuntimeError.evaluationUnavailable(let message) {
                return .evaluationUnavailable(actionName: actionName, diagnostic: .init(code: .evaluatorUnavailable, message: message))
            } catch let error as EvalError {
                return .evaluationFailed(actionName: actionName, diagnostic: .init(code: .evaluationError, message: error.description))
            } catch let error as ActionError {
                return .evaluationFailed(actionName: actionName, diagnostic: .init(code: .actionError, message: error.description))
            } catch {
                return .evaluationFailed(actionName: actionName, diagnostic: .init(code: .evaluationError, message: String(describing: error)))
            }
        }
        return successors.isEmpty ? .disabled(actionName: actionName) : .enabled(actionName: actionName, successors: successors)
    }

    public func generatedActionOutcome(actionName: String, in state: [String: TLAValue]) -> RuntimeActionOutcome {
        actionOutcome(named: actionName, in: state)
    }

    public func actionOutcomes(in state: [String: TLAValue]) -> [RuntimeActionOutcome] {
        actions.map { actionOutcome(named: $0.name, in: state) }
    }

    public func propertyOutcomes(in state: [String: TLAValue]) -> [RuntimePropertyOutcome] {
        var outcomes = invariants.map { invariant -> RuntimePropertyOutcome in
            do {
                return try invariant.body.evaluateBool(in: state, runtimeFuncs: spec.runtimeFuncs, recursiveFuncs: spec.recursiveFuncs)
                    ? .satisfied(name: invariant.name) : .violated(name: invariant.name)
            } catch {
                return .evaluationFailed(name: invariant.name, diagnostic: .init(code: .evaluationError, message: String(describing: error)))
            }
        }
        outcomes += spec.temporalProperties.map {
            .evaluationUnavailable(name: $0.name, diagnostic: .init(code: .evaluatorUnavailable, message: "Temporal properties require a complete graph evaluation"))
        }
        return outcomes
    }

    public func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let inv = invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try inv.body.evaluateBool(in: state, runtimeFuncs: spec.runtimeFuncs, recursiveFuncs: spec.recursiveFuncs)
    }

    public func step(_ invocation: TLAActionInvocation, from state: [String: TLAValue]) throws -> StepResult {
        let available = try availableInvocations(in: state, requested: invocation)
        guard available.contains(invocation) else {
            return .actionNotEnabled(invocation, available: available)
        }
        let next = try apply(invocation, to: state)
        var violations: [String] = []
        for inv in invariants {
            if !(try inv.body.evaluateBool(in: next, runtimeFuncs: spec.runtimeFuncs, recursiveFuncs: spec.recursiveFuncs)) {
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

    public enum RuntimeActionOutcome: Sendable, Equatable {
        case enabled(actionName: String, successors: [[String: TLAValue]])
        case disabled(actionName: String)
        case evaluationFailed(actionName: String, diagnostic: ActionEvaluationDiagnostic)
        case evaluationUnavailable(actionName: String, diagnostic: ActionEvaluationDiagnostic)
        case actionNotFound(actionName: String)
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
        public init(code: Code, message: String) { self.code = code; self.message = message }
    }

    public struct PropertyEvaluationDiagnostic: Sendable, Equatable {
        public enum Code: String, Sendable, Equatable { case evaluationError, evaluatorUnavailable }
        public let code: Code
        public let message: String
        public init(code: Code, message: String) { self.code = code; self.message = message }
    }
}
