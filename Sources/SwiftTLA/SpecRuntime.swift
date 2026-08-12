public struct SpecRuntime: Sendable {
    public let spec: TLASpec
    private let varNames: [String]
    private let actions: [NamedAction]
    private let invariants: [NamedInvariant]

    public init(spec: TLASpec) {
        self.spec = spec
        self.varNames = spec.variables.map(\.name)
        self.actions = spec.actions
        self.invariants = spec.invariants
    }

    public func initialStates() -> [[String: TLAValue]] {
        computeInitialStates(spec)
    }

    public func apply(actionName: String, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            throw RuntimeError.actionNotFound(actionName)
        }
        guard action.binding == nil else { throw RuntimeError.actionRequiresArgument(actionName) }
        return try apply(actionName: actionName, argument: nil, to: state)
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
        let successors = try ActionEnumerator.enumerate(body, from: state, varNames: varNames)
        guard let next = successors.first else {
            throw RuntimeError.actionNotEnabled(actionName)
        }
        return next
    }

    public func availableActions(in state: [String: TLAValue]) -> [String] {
        actions.compactMap { action in
            let bodies = action.binding?.values.map { action.body.substituteVar(action.binding!.name, with: $0, in: action.body) } ?? [action.body]
            guard bodies.contains(where: { (try? ActionEnumerator.enumerate($0, from: state, varNames: varNames).isEmpty) == false }) else { return nil }
            return action.name
        }
    }

    public func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let inv = invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try inv.body.evaluateBool(in: state, runtimeFuncs: spec.runtimeFuncs, recursiveFuncs: spec.recursiveFuncs)
    }

    public func step(_ actionName: String, from state: [String: TLAValue]) throws -> StepResult {
        let available = availableActions(in: state)
        guard available.contains(actionName) else {
            return .actionNotEnabled(actionName, available: available)
        }
        let next = try apply(actionName: actionName, to: state)
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

    public enum RuntimeError: Error {
        case actionNotFound(String)
        case actionNotEnabled(String)
        case actionRequiresArgument(String)
        case invalidActionArgument(String, TLAValue)
        case invariantNotFound(String)
    }
}
