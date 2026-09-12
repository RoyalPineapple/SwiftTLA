package struct StateGraph: Sendable {
    public let specName: String
    public let variableNames: [String]
    public struct TransitionLabel: Hashable, Sendable, CustomStringConvertible {
        public let action: String
        let arguments: [CompiledValue]
        let actionID: ActionID?
        private let renderedDescription: String

        public init(_ formalActionCall: FormalActionCall) {
            self.action = formalActionCall.name
            self.arguments = formalActionCall.arguments.map(CompiledValue.init(formal:))
            self.actionID = nil
            self.renderedDescription = formalActionCall.description
        }

        init(
            action: ActionID,
            formalName: String,
            arguments: [CompiledValue],
            formalArguments: [TLAValue]
        ) {
            self.action = formalName
            self.arguments = arguments
            self.actionID = action
            self.renderedDescription = formalActionCall(named: formalName, arguments: formalArguments)
        }

        public var description: String {
            renderedDescription
        }

        func formalArguments(using layout: CompiledLayout) throws -> [TLAValue] {
            try arguments.map { try $0.rendered(using: layout) }
        }
    }

    public struct Transition: Sendable {
        public let label: TransitionLabel
        public var action: String { label.description }
        public let target: StateID
        public init(label: TransitionLabel, target: StateID) {
            self.label = label; self.target = target
        }
    }

    public let transitions: [StateID: [Transition]]
    public let states: [StateID: TLAStateProjection]

    public init(
        specName: String,
        variableNames: [String],
        transitions: [StateID: [Transition]],
        states: [StateID: TLAStateProjection]
    ) {
        self.specName = specName
        self.variableNames = variableNames
        self.transitions = transitions
        self.states = states
    }

    public struct StateID: Hashable, Sendable, CustomStringConvertible {
        public let id: Int
        public init(_ id: Int) { self.id = id }
        public var description: String { "s\(id)" }
    }
}

package struct FiniteExploration {
    public let graph: StateGraph
    public let initialStateIDs: [StateGraph.StateID]
    public let outcome: ModelCheckOutcome
    package let compilationIdentity: CompilationIdentity
    package let configuration: FiniteExplorationConfiguration
    let compiledStates: [StateGraph.StateID: CompiledState]

    public var isComplete: Bool {
        if case .ok = outcome { return true }
        return false
    }

    init(
        graph: StateGraph,
        initialStateIDs: [StateGraph.StateID],
        outcome: ModelCheckOutcome,
        compilationIdentity: CompilationIdentity,
        configuration: FiniteExplorationConfiguration,
        compiledStates: [StateGraph.StateID: CompiledState]
    ) {
        self.graph = graph
        self.initialStateIDs = initialStateIDs
        self.outcome = outcome
        self.compilationIdentity = compilationIdentity
        self.configuration = configuration
        self.compiledStates = compiledStates
    }

    func validate(for compilation: CompiledSpecification) throws {
        guard compilationIdentity == compilation.identity else {
            throw CompiledEvaluationError.invalidCompilationIdentity(
                expected: compilation.identity, actual: compilationIdentity
            )
        }
        try configuration.validatePropertySupport(in: compilation)
        guard (!isComplete || !initialStateIDs.isEmpty),
              initialStateIDs.allSatisfy({ compiledStates[$0] != nil }),
              Set(graph.states.keys) == Set(compiledStates.keys) else {
            throw inconsistentGraph("initial state IDs and compiled states do not cover the explored graph")
        }
        for (id, state) in compiledStates {
            try state.requireIdentity(compilation.identity)
            guard try state.projection(using: compilation.layout) == graph.states[id] else {
                throw inconsistentGraph("compiled state \(id) disagrees with its graph projection")
            }
        }
    }

    private func inconsistentGraph(_ actual: String) -> CompilationDiagnostic {
        .init(
            code: .compilationIdentityMismatch, stage: .checking, path: "exploration.graph",
            expected: "compiled states and initial state IDs consistent with the explored graph",
            actual: actual, nextSafeAction: "Explore the compiled specification again before checking properties."
        )
    }
}
