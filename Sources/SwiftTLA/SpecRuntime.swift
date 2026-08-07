public struct SpecRuntime {
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
        return computeInitialStateMaps(spec)
    }

    public func apply(actionName: String, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        guard let action = actions.first(where: { $0.name == actionName }) else {
            throw RuntimeError.actionNotFound(actionName)
        }
        let successors = try ActionEnumerator.enumerate(action.body, from: state, varNames: varNames)
        guard let next = successors.first else {
            throw RuntimeError.actionNotEnabled(actionName)
        }
        return next
    }

    public func availableActions(in state: [String: TLAValue]) -> [String] {
        actions.compactMap { action in
            guard let successors = try? ActionEnumerator.enumerate(action.body, from: state, varNames: varNames),
                  !successors.isEmpty else { return nil }
            return action.name
        }
    }

    public func check(_ invariantName: String, in state: [String: TLAValue]) throws -> Bool {
        guard let inv = invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try Evaluator.evaluateBool(inv.body, in: state)
    }

    public func step(_ actionName: String, from state: [String: TLAValue]) throws -> StepResult {
        let available = availableActions(in: state)
        guard available.contains(actionName) else {
            return .actionNotEnabled(actionName, available: available)
        }
        let next = try apply(actionName: actionName, to: state)
        var violations: [String] = []
        for inv in invariants {
            if !(try Evaluator.evaluateBool(inv.body, in: next)) {
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
        case invariantNotFound(String)
    }

    private func computeInitialStateMaps(_ spec: TLASpec) -> [[String: TLAValue]] {
        let substituted = substituteConstants(spec)
        let base = Dictionary(uniqueKeysWithValues: substituted.variables.map { ($0.name, $0.initial) })
        let nondeterministic = substituted.variables.filter { v in
            guard v.initialSet != nil else { return false }
            if case .set = v.initial { return true }
            return false
        }
        var states: [[String: TLAValue]] = nondeterministic.reduce([base]) { states, variable in
            guard case .set(let values) = variable.initial else { return states }
            let sorted = TLAValue.sorted(values)
            return states.flatMap { state in sorted.map { state.merging([variable.name: $0]) { _, new in new } } }
        }
        for variable in substituted.variables where variable.initExpr != nil {
            states = states.compactMap { state in
                guard let val = try? Evaluator.evaluate(variable.initExpr!, in: state) else { return nil }
                var s = state
                s[variable.name] = val
                return s
            }
        }
        return states
    }
}
