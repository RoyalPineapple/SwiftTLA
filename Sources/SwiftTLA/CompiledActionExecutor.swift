public struct CompiledActionExecutor<Label: Hashable & Sendable>: Sendable {
    private let runtime: SpecRuntime
    private let actionOrdinal: @Sendable (Label) -> Int
    private let arguments: @Sendable (Label) -> [TLAValue]
    private let label: @Sendable (Int, [TLAValue]) -> Label?

    public init(
        compilation: CompiledSpecification,
        actionOrdinal: @escaping @Sendable (Label) -> Int,
        arguments: @escaping @Sendable (Label) -> [TLAValue],
        label: @escaping @Sendable (Int, [TLAValue]) -> Label?
    ) {
        self.runtime = SpecRuntime(compilation: compilation)
        self.actionOrdinal = actionOrdinal
        self.arguments = arguments
        self.label = label
    }

    public func successors(
        for action: Label,
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        try runtime.successors(
            actionAt: actionOrdinal(action),
            arguments: arguments(action),
            from: state
        )
    }

    public func availableLabels(in state: TLAStateProjection) throws -> [Label] {
        try runtime.availableActionResults(in: state).map { result in
            guard let label = label(result.action, result.arguments) else {
                throw SpecRuntime.RuntimeError.evaluationUnavailable("The compiled action result cannot be represented by the generated action label.")
            }
            return label
        }
    }

}
