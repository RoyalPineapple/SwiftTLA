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
            successors = try ActionEnumerator.enumerate(variant.body, from: state, varNames: varNames)
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
                    if try !ActionEnumerator.enumerate(variant.body, from: state, varNames: varNames).isEmpty {
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
        case invariantNotFound(String)
    }
}
