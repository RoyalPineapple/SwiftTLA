public struct TransitionRelation: Sendable {
    public typealias State = [String: TLAValue]

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

    private let runtime: CompiledRuntime
    private let layout: CompiledLayout

    public init(spec: TLASpec) throws {
        self.init(compilation: try spec.compile())
    }

    public init(compilation: CompiledSpecification) {
        runtime = CompiledRuntime(compilation: compilation)
        layout = compilation.layout
    }

    public func successors(from state: State) throws -> [Successor] {
        let formalState = try FormalState(projected: state, layout: layout)
        do {
            return try runtime.successors(from: formalState).map(project)
        } catch {
            throw Error.enumerationFailed(
                invocation: .init(name: ""),
                underlying: error
            )
        }
    }

    public func successors(
        for invocation: TLAActionInvocation,
        from state: State
    ) throws -> [Successor] {
        guard let actionID = layout.actionID(named: invocation.name) else {
            throw Error.actionNotFound(invocation)
        }
        guard argumentSets(for: actionID).contains(invocation.arguments) else {
            throw Error.invalidActionArguments(invocation)
        }
        let formalState = try FormalState(projected: state, layout: layout)
        do {
            return try runtime.successors(for: actionID, from: formalState)
                .filter { $0.arguments == invocation.arguments }
                .map(project)
        } catch {
            throw Error.enumerationFailed(invocation: invocation, underlying: error)
        }
    }

    private func project(_ successor: CompiledSuccessor) throws -> Successor {
        let name = layout.actions[successor.action.ordinal].declaration.name
        return try .init(
            invocation: .init(name: name, arguments: successor.arguments),
            state: successor.state.projected(using: layout)
        )
    }

    private func argumentSets(for actionID: ActionID) -> [[TLAValue]] {
        guard let action = runtime.compilation.model.actions.first(where: { $0.id == actionID }) else {
            return []
        }
        return action.bindings.reduce([[]]) { arguments, binding in
            arguments.flatMap { prefix in
                binding.values.map { prefix + [$0] }
            }
        }
    }
}
