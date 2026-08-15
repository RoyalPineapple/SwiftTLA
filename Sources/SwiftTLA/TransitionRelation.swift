public struct TransitionRelation: Sendable {
    public typealias State = [String: TLAValue]
    public typealias ActionEvaluator = @Sendable (ActionExpr, State, [String]) throws -> [State]

    public struct Successor: Sendable, Equatable {
        public let invocation: TLAActionInvocation
        public let state: State

        public init(invocation: TLAActionInvocation, state: State) {
            self.invocation = invocation
            self.state = state
        }
    }

    public enum Error: Swift.Error {
        case actionNotFound(TLAActionInvocation)
        case invalidActionArguments(TLAActionInvocation)
        case enumerationFailed(invocation: TLAActionInvocation, underlying: any Swift.Error)
    }

    private let spec: TLASpec
    private let variableNames: [String]
    private let actionEvaluator: ActionEvaluator

    public init(
        spec: TLASpec,
        actionEvaluator: ActionEvaluator? = nil
    ) {
        self.init(resolvedSpec: substituteConstants(spec), actionEvaluator: actionEvaluator)
    }

    init(
        resolvedSpec: TLASpec,
        actionEvaluator: ActionEvaluator? = nil
    ) {
        self.spec = resolvedSpec
        self.variableNames = resolvedSpec.variables.map(\.name)
        self.actionEvaluator = actionEvaluator ?? { action, state, variableNames in
            try ActionEnumerator.enumerate(
                action,
                from: state,
                varNames: variableNames,
                formalOperatorDefinitions: resolvedSpec.resolvedFormalOperatorDefinitions
            )
        }
    }

    public func successors(from state: State) throws -> [Successor] {
        try spec.actions.flatMap { action in
            try actionInvocations(action).flatMap { variant in
                try successors(for: variant, from: state)
            }
        }
    }

    public func successors(
        for invocation: TLAActionInvocation,
        from state: State
    ) throws -> [Successor] {
        guard let action = spec.actions.first(where: { $0.name == invocation.name }) else {
            throw Error.actionNotFound(invocation)
        }
        guard let variant = actionInvocations(action).first(where: { $0.invocation == invocation }) else {
            throw Error.invalidActionArguments(invocation)
        }
        return try successors(for: variant, from: state)
    }

    private func successors(
        for variant: (invocation: TLAActionInvocation, body: ActionExpr, indices: [Int]),
        from state: State
    ) throws -> [Successor] {
        let states: [State]
        do {
            states = try actionEvaluator(variant.body, state, variableNames)
            if let constraint = spec.constraint {
                return try states.compactMap { successor in
                    try constraint.evaluateBool(
                        in: successor,
                        runtimeFuncs: spec.runtimeFuncs,
                        recursiveFuncs: spec.resolvedRecursiveFuncs,
                        formalOperatorDefinitions: spec.resolvedFormalOperatorDefinitions
                    ) ? Successor(invocation: variant.invocation, state: successor) : nil
                }
            }
        } catch {
            throw Error.enumerationFailed(invocation: variant.invocation, underlying: error)
        }
        return states.map { Successor(invocation: variant.invocation, state: $0) }
    }
}
