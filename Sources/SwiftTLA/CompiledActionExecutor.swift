public struct CompiledActionExecutor<Label: Hashable & Sendable>: Sendable {
    private let compilation: CompiledSpecification
    private let runtime: CompiledRuntime
    private let actionOrdinal: @Sendable (Label) -> Int
    private let arguments: @Sendable (Label) -> [TLAValue]
    private let label: @Sendable (Int, [TLAValue]) -> Label?

    public init(
        compilation: CompiledSpecification,
        actionOrdinal: @escaping @Sendable (Label) -> Int,
        arguments: @escaping @Sendable (Label) -> [TLAValue],
        label: @escaping @Sendable (Int, [TLAValue]) -> Label?
    ) {
        self.compilation = compilation
        self.runtime = CompiledRuntime(compilation: compilation)
        self.actionOrdinal = actionOrdinal
        self.arguments = arguments
        self.label = label
    }

    public func successors(
        for action: Label,
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try CompiledState(projection: state, compilation: compilation)
        let compiledAction = try compiledAction(for: action)
        let expectedArguments = arguments(action).map(CompiledValue.init(formal:))
        guard argumentSets(for: compiledAction).contains(expectedArguments) else {
            throw GeneratedMachineError.noMatchingSuccessor
        }
        return try runtime.successors(for: compiledAction.id, from: formalState)
            .filter { $0.arguments.map(CompiledValue.init(formal:)) == expectedArguments }
            .map { try $0.state.projection(using: compilation.layout) }
    }

    public func availableLabels(in state: TLAStateProjection) throws -> [Label] {
        let formalState = try CompiledState(projection: state, compilation: compilation)
        return try runtime.successors(from: formalState).reduce(into: []) { labels, successor in
            guard let label = self.label(successor.action.ordinal, successor.arguments) else {
                throw GeneratedMachineError.noMatchingSuccessor
            }
            if labels.last != label {
                labels.append(label)
            }
        }
    }

    private func compiledAction(for label: Label) throws -> CompiledAction {
        let ordinal = actionOrdinal(label)
        guard compilation.layout.actions.indices.contains(ordinal),
              let action = compilation.model.actions.first(where: { $0.id == compilation.layout.actions[ordinal].id })
        else {
            throw GeneratedMachineError.noMatchingSuccessor
        }
        return action
    }

    private func argumentSets(for action: CompiledAction) -> [[CompiledValue]] {
        action.bindings.reduce([[]]) { arguments, binding in
            arguments.flatMap { prefix in binding.values.map { prefix + [.init(formal: $0)] } }
        }
    }

}
