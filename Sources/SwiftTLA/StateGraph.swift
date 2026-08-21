public struct StateGraph: Sendable {
    public let specName: String
    public let variableNames: [String]
    public struct TransitionLabel: Hashable, Sendable, CustomStringConvertible {
        public let action: String
        public let arguments: [TLAValue]
        let actionID: ActionID?

        public init(_ formalActionCall: FormalActionCall) {
            self.action = formalActionCall.name
            self.arguments = formalActionCall.arguments
            self.actionID = nil
        }

        init(action: ActionID, formalName: String, arguments: [TLAValue]) {
            self.action = formalName
            self.arguments = arguments
            self.actionID = action
        }

        public var description: String {
            formalActionCall(named: action, arguments: arguments)
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

public struct ModelExplorationResult {
    public let graph: StateGraph
    public let initialStateIDs: [StateGraph.StateID]
    public let result: CheckResult
    let compiledStates: [StateGraph.StateID: CompiledState]

    public var isComplete: Bool {
        if case .ok = result.underlyingOutcome { return true }
        return false
    }

    public init(
        graph: StateGraph,
        initialStateIDs: [StateGraph.StateID],
        result: CheckResult
    ) {
        self.graph = graph
        self.initialStateIDs = initialStateIDs
        self.result = result
        compiledStates = [:]
    }

    init(
        graph: StateGraph,
        initialStateIDs: [StateGraph.StateID],
        result: CheckResult,
        compiledStates: [StateGraph.StateID: CompiledState]
    ) {
        self.graph = graph
        self.initialStateIDs = initialStateIDs
        self.result = result
        self.compiledStates = compiledStates
    }
}
