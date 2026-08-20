public struct SpecRuntime: Sendable {
    public let spec: TLASpec
    /// Present when this runtime entered through the validated compiler gate.
    public let compilation: CompiledSpecification
    private let runtime: CompiledRuntime
    private let layout: CompiledLayout

    init(spec: TLASpec) throws {
        self.init(compilation: try spec.compile())
    }

    public init(compilation: CompiledSpecification) {
        self.spec = compilation.spec
        self.compilation = compilation
        self.runtime = CompiledRuntime(compilation: compilation)
        self.layout = compilation.layout
    }

    public func initialStateProjections() throws -> [TLAStateProjection] {
        try runtime.initialStates().map { try $0.projection(using: layout) }
    }

    public func successors(
        _ invocation: TLAActionInvocation,
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try FormalState(projection: state, compilation: compilation)
        let request = try compiledActionRequest(invocation, in: formalState)
        return try evaluatedSuccessors(request, from: formalState, requested: invocation).map {
            try $0.state.projection(using: layout)
        }
    }

    private func compiledActionRequest(
        _ invocation: TLAActionInvocation,
        in formalState: FormalState
    ) throws -> CompiledActionRequest {
        guard let actionID = layout.actionID(named: invocation.name) else {
            throw RuntimeError.actionNotFound(
                invocation,
                available: try availableInvocations(in: formalState, requested: invocation)
            )
        }
        let request = CompiledActionRequest(
            compilation: compilation.identity,
            action: actionID,
            arguments: invocation.arguments.map(CompiledValue.init(formal:))
        )
        guard argumentSets(for: actionID).contains(request.arguments) else {
            throw RuntimeError.invalidActionArguments(
                invocation,
                available: try availableInvocations(in: formalState, requested: invocation)
            )
        }
        return request
    }

    private func evaluatedSuccessors(
        _ request: CompiledActionRequest,
        from formalState: FormalState,
        requested invocation: TLAActionInvocation
    ) throws -> [CompiledSuccessor] {
        try request.requireIdentity(compilation.identity)
        do {
            return try runtime.successors(for: request.action, from: formalState)
                .filter { $0.arguments.map(CompiledValue.init(formal:)) == request.arguments }
        } catch {
            throw RuntimeError.enumerationFailed(
                requested: invocation,
                evaluated: invocation,
                underlying: error
            )
        }
    }

    public func availableInvocations(in state: TLAStateProjection) throws -> [TLAActionInvocation] {
        try availableInvocations(
            in: FormalState(projection: state, compilation: compilation),
            requested: nil
        )
    }

    func successors(
        actionAt declarationOrder: Int,
        arguments: [TLAValue],
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try FormalState(projection: state, compilation: compilation)
        let request = try compiledActionRequest(
            actionAt: declarationOrder,
            arguments: arguments,
            in: formalState
        )
        do {
            return try runtime.successors(for: request.action, from: formalState)
                .filter { $0.arguments.map(CompiledValue.init(formal:)) == request.arguments }
                .map { try $0.state.projection(using: layout) }
        } catch {
            throw RuntimeError.evaluationUnavailable("The compiled action could not be evaluated.")
        }
    }

    func availableActionResults(
        in state: TLAStateProjection
    ) throws -> [(action: Int, arguments: [TLAValue])] {
        let formalState = try FormalState(projection: state, compilation: compilation)
        do {
            return try runtime.successors(from: formalState).reduce(into: []) { available, successor in
                let result = (action: successor.action.ordinal, arguments: successor.arguments)
                if available.last?.action != result.action || available.last?.arguments != result.arguments {
                    available.append(result)
                }
            }
        } catch {
            throw RuntimeError.evaluationUnavailable("The compiled action results could not be enumerated.")
        }
    }

    private func availableInvocations(
        in formalState: FormalState,
        requested: TLAActionInvocation?
    ) throws -> [TLAActionInvocation] {
        do {
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

    private func compiledActionRequest(
        actionAt declarationOrder: Int,
        arguments: [TLAValue],
        in formalState: FormalState
    ) throws -> CompiledActionRequest {
        guard layout.actions.indices.contains(declarationOrder) else {
            throw RuntimeError.evaluationUnavailable("The compiled action reference is outside this model's action layout.")
        }
        let action = layout.actions[declarationOrder].id
        let request = CompiledActionRequest(
            compilation: compilation.identity,
            action: action,
            arguments: arguments.map(CompiledValue.init(formal:))
        )
        guard argumentSets(for: action).contains(request.arguments) else {
            throw RuntimeError.evaluationUnavailable("The generated action arguments are outside the compiled action domain.")
        }
        return request
    }

    public func propertyOutcomes(in state: TLAStateProjection) -> [RuntimePropertyOutcome] {
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

    public func invariantOutcomes(in state: TLAStateProjection) -> [RuntimePropertyOutcome] {
        let formalState: FormalState
        do {
            formalState = try FormalState(projection: state, compilation: compilation)
        } catch {
            return compilation.model.invariants.map {
                .evaluationFailed(
                    name: $0.name,
                    diagnostic: .init(code: .evaluationError, message: String(describing: error))
                )
            }
        }
        let outcomes = compilation.model.invariants.map { invariant -> RuntimePropertyOutcome in
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

    public func check(_ invariantName: String, in state: TLAStateProjection) throws -> Bool {
        guard let invariant = compilation.model.invariants.first(where: { $0.name == invariantName }) else {
            throw RuntimeError.invariantNotFound(invariantName)
        }
        return try runtime.invariantHolds(
            invariant,
            in: FormalState(projection: state, compilation: compilation)
        )
    }

    package func step(_ invocation: TLAActionInvocation, from state: TLAStateProjection) throws -> StepResult {
        let formalState = try FormalState(projection: state, compilation: compilation)
        let available = try availableInvocations(
            in: formalState,
            requested: invocation
        )
        guard available.contains(invocation) else {
            return .actionNotEnabled(invocation, available: available)
        }
        let request = try compiledActionRequest(invocation, in: formalState)
        guard let next = try evaluatedSuccessors(request, from: formalState, requested: invocation).first else {
            return .actionNotEnabled(invocation, available: available)
        }
        let formalNext = next.state
        let violations = try compilation.model.invariants.compactMap { invariant in
            try runtime.invariantHolds(invariant, in: formalNext) ? nil : invariant.name
        }
        if violations.isEmpty == false {
            return .invariantViolated(violations)
        }
        return .ok(try formalNext.projection(using: layout))
    }

    package enum StepResult {
        case ok(TLAStateProjection)
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

    private func argumentSets(for actionID: ActionID) -> [[CompiledValue]] {
        guard let action = compilation.model.actions.first(where: { $0.id == actionID }) else {
            return []
        }
        return action.bindings.reduce([[]]) { arguments, binding in
            arguments.flatMap { prefix in binding.values.map { prefix + [.init(formal: $0)] } }
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

}

private struct CompiledActionRequest: Sendable {
    let compilation: CompilationIdentity
    let action: ActionID
    let arguments: [CompiledValue]

    func requireIdentity(_ expected: CompilationIdentity) throws {
        guard compilation == expected else {
            throw CompiledEvaluationError.invalidCompilationIdentity(
                expected: expected,
                actual: compilation
            )
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
