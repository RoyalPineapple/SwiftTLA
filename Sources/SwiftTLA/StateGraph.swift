public struct StateGraph: Sendable {
    public let specName: String
    public let variableNames: [String]
    public struct Transition: Sendable {
        public let action: String
        public let target: StateID
        public init(action: String, target: StateID) {
            self.action = action; self.target = target
        }
    }

    public let transitions: [StateID: [Transition]]
    public let states: [StateID: [String: TLAValue]]

    public init(
        specName: String,
        variableNames: [String],
        transitions: [StateID: [Transition]],
        states: [StateID: [String: TLAValue]]
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
    }
}
