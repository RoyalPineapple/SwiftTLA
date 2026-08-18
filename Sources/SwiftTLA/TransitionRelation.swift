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
    private let actionEvaluator: ActionEvaluator?
    private let formalModuleClosure: FormalModuleClosure

    public init(
        spec: TLASpec,
        actionEvaluator: ActionEvaluator? = nil
    ) throws {
        self.init(compilation: try spec.compile(), actionEvaluator: actionEvaluator)
    }

    public init(
        compilation: CompiledSpecification,
        actionEvaluator: ActionEvaluator? = nil
    ) {
        self.init(
            resolvedSpec: substituteConstants(compilation.spec),
            formalModuleClosure: compilation.formalModuleClosure,
            actionEvaluator: actionEvaluator
        )
    }

    init(
        resolvedSpec: TLASpec,
        formalModuleClosure: FormalModuleClosure,
        actionEvaluator: ActionEvaluator? = nil
    ) {
        self.spec = resolvedSpec
        self.variableNames = resolvedSpec.variables.map(\.name)
        self.actionEvaluator = actionEvaluator
        self.formalModuleClosure = formalModuleClosure
    }

    public func successors(from state: State) throws -> [Successor] {
        try successors(from: state, evaluationContext: StateExprEvaluationContext())
    }

    func successors(
        from state: State,
        evaluationContext: StateExprEvaluationContext
    ) throws -> [Successor] {
        try spec.actions.flatMap { action in
            try actionInvocations(action).flatMap { variant in
                try successors(for: variant, from: state, evaluationContext: evaluationContext)
            }
        }
    }

    public func successors(
        for invocation: TLAActionInvocation,
        from state: State
    ) throws -> [Successor] {
        try successors(
            for: invocation,
            from: state,
            evaluationContext: StateExprEvaluationContext()
        )
    }

    func successors(
        for invocation: TLAActionInvocation,
        from state: State,
        evaluationContext: StateExprEvaluationContext
    ) throws -> [Successor] {
        guard let action = spec.actions.first(where: { $0.name == invocation.name }) else {
            throw Error.actionNotFound(invocation)
        }
        guard let variant = actionInvocations(action).first(where: { $0.invocation == invocation }) else {
            throw Error.invalidActionArguments(invocation)
        }
        return try successors(for: variant, from: state, evaluationContext: evaluationContext)
    }

    private func successors(
        for variant: (invocation: TLAActionInvocation, body: ActionExpr, indices: [Int]),
        from state: State,
        evaluationContext: StateExprEvaluationContext
    ) throws -> [Successor] {
        let states: [State]
        do {
            states = try enumerate(
                variant.body,
                from: state,
                evaluationContext: evaluationContext
            )
            if let constraint = spec.constraint {
                return try states.compactMap { successor in
                    try constraint.evaluateBool(
                        in: successor,
                        runtimeFuncs: spec.runtimeFuncs,
                        recursiveFuncs: formalModuleClosure.resolvedRecursiveFuncs,
                        formalOperatorDefinitions: formalModuleClosure.resolvedFormalOperatorDefinitions,
                        evaluationContext: evaluationContext
                    ) ? Successor(invocation: variant.invocation, state: successor) : nil
                }
            }
        } catch {
            throw Error.enumerationFailed(invocation: variant.invocation, underlying: error)
        }
        return states.map { Successor(invocation: variant.invocation, state: $0) }
    }

    private func enumerate(
        _ action: ActionExpr,
        from state: State,
        evaluationContext: StateExprEvaluationContext
    ) throws -> [State] {
        if let actionEvaluator {
            return try actionEvaluator(action, state, variableNames)
        } else {
            return try ActionEnumerator.enumerate(
                action,
                from: state,
                varNames: variableNames,
                formalOperatorDefinitions: formalModuleClosure.resolvedFormalOperatorDefinitions,
                evaluationContext: evaluationContext
            )
        }
    }
}
