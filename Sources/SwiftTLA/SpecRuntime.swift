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

    public func apply(actionName: String, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            throw RuntimeError.actionNotFound(actionName)
        }
        guard action.binding == nil else { throw RuntimeError.actionRequiresArgument(actionName) }
        return try applyOutcome(actionOutcome(named: actionName, in: state), actionName: actionName)
    }

    public func apply(actionName: String, argument: TLAValue?, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            throw RuntimeError.actionNotFound(actionName)
        }
        let body: ActionExpr
        if let binding = action.binding {
            guard let argument else { throw RuntimeError.actionRequiresArgument(actionName) }
            guard binding.values.contains(argument) else { throw RuntimeError.invalidActionArgument(actionName, argument) }
            body = action.body.substituteVar(binding.name, with: argument, in: action.body)
        } else {
            guard argument == nil else { throw RuntimeError.invalidActionArgument(actionName, argument!) }
            body = action.body
        }
        return try applyOutcome(evaluate(actionName: actionName, body: body, in: state), actionName: actionName)
    }

    private func applyOutcome(_ outcome: RuntimeActionOutcome, actionName: String) throws -> [String: TLAValue] {
        switch outcome {
        case .enabled(_, let successors):
            return successors[0]
        case .disabled:
            throw RuntimeError.actionNotEnabled(actionName)
        case .actionNotFound:
            throw RuntimeError.actionNotFound(actionName)
        case .evaluationFailed(_, let diagnostic):
            throw RuntimeError.actionEvaluationFailed(actionName, diagnostic)
        case .evaluationUnavailable(_, let diagnostic):
            throw RuntimeError.evaluationUnavailable(diagnostic.message)
        }
    }

    /// Returns the enabled action names for compatibility with interactive callers.
    ///
    /// This view intentionally omits disabled and failed evaluations. Conformance
    /// code must use `actionOutcomes(in:)`, which preserves every outcome.
    public func availableActions(in state: [String: TLAValue]) -> [String] {
        actionOutcomes(in: state).compactMap { outcome in
            guard case .enabled(let actionName, _) = outcome else { return nil }
            return actionName
        }
    }

    public func actionOutcome(
        named actionName: String,
        in state: [String: TLAValue]
    ) -> RuntimeActionOutcome {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            return .actionNotFound(actionName: actionName)
        }

        let bodies = action.binding?.values.map {
            action.body.substituteVar(action.binding!.name, with: $0, in: action.body)
        } ?? [action.body]
        var successors: [[String: TLAValue]] = []
        for body in bodies {
            let outcome = evaluate(actionName: actionName, body: body, in: state)
            switch outcome {
            case .enabled(_, let bodySuccessors):
                successors.append(contentsOf: bodySuccessors)
            case .disabled:
                continue
            case .evaluationFailed, .evaluationUnavailable, .actionNotFound:
                return outcome
            }
        }
        return successors.isEmpty
            ? .disabled(actionName: actionName)
            : .enabled(actionName: actionName, successors: successors)
    }

    private func evaluate(
        actionName: String,
        body: ActionExpr,
        in state: [String: TLAValue]
    ) -> RuntimeActionOutcome {
        do {
            let successors = try actionEvaluator(body, state, varNames)
            return successors.isEmpty
                ? .disabled(actionName: actionName)
                : .enabled(actionName: actionName, successors: successors)
        } catch RuntimeError.evaluationUnavailable(let message) {
            return .evaluationUnavailable(
                actionName: actionName,
                diagnostic: .init(code: .evaluatorUnavailable, message: message))
        } catch let error as EvalError {
            return .evaluationFailed(
                actionName: actionName,
                diagnostic: .init(code: .evaluationError, message: error.description))
        } catch let error as ActionError {
            return .evaluationFailed(
                actionName: actionName,
                diagnostic: .init(code: .actionError, message: error.description))
        } catch {
            return .evaluationFailed(
                actionName: actionName,
                diagnostic: .init(code: .evaluationError, message: String(describing: error)))
        }
    }

    public func actionOutcomes(in state: [String: TLAValue]) -> [RuntimeActionOutcome] {
        actions.map { actionOutcome(named: $0.name, in: state) }
    }

    public func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let inv = invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try inv.body.evaluateBool(in: state, runtimeFuncs: spec.runtimeFuncs, recursiveFuncs: spec.recursiveFuncs)
    }

    public func step(_ actionName: String, from state: [String: TLAValue]) throws -> StepResult {
        if let action = actions.first(where: { $0.name == actionName }), action.binding != nil {
            throw RuntimeError.actionRequiresArgument(actionName)
        }
        let outcome = actionOutcome(named: actionName, in: state)
        let available = availableActions(in: state)
        let next: [String: TLAValue]
        switch outcome {
        case .enabled(_, let successors):
            next = successors[0]
        case .disabled, .actionNotFound:
            return .actionNotEnabled(actionName, available: available)
        case .evaluationFailed(_, let diagnostic):
            throw RuntimeError.actionEvaluationFailed(actionName, diagnostic)
        case .evaluationUnavailable(_, let diagnostic):
            throw RuntimeError.evaluationUnavailable(diagnostic.message)
        }
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
        case actionNotEnabled(String, available: [String])
        case invariantViolated([String])
    }

    public enum RuntimeActionOutcome: Sendable, Equatable {
        case enabled(actionName: String, successors: [[String: TLAValue]])
        case disabled(actionName: String)
        case evaluationFailed(actionName: String, diagnostic: ActionEvaluationDiagnostic)
        case evaluationUnavailable(actionName: String, diagnostic: ActionEvaluationDiagnostic)
        case actionNotFound(actionName: String)
    }

    public struct ActionEvaluationDiagnostic: Sendable, Equatable {
        public enum Code: String, Sendable, Equatable {
            case actionError
            case evaluationError
            case evaluatorUnavailable
        }

        public let code: Code
        public let message: String

        public init(code: Code, message: String) {
            self.code = code
            self.message = message
        }
    }

    public enum RuntimeError: Error {
        case actionNotFound(String)
        case actionNotEnabled(String)
        case actionRequiresArgument(String)
        case invalidActionArgument(String, TLAValue)
        case actionEvaluationFailed(String, ActionEvaluationDiagnostic)
        case evaluationUnavailable(String)
        case invariantNotFound(String)
    }
}
