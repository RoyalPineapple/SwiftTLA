public struct StateGraph: Sendable {
    public let specName: String
    public let variableNames: [String]
    public struct TransitionLabel: Hashable, Sendable, CustomStringConvertible {
        public let action: String
        public let argument: TLAValue?

        public init(action: String, argument: TLAValue? = nil) {
            self.action = action
            self.argument = argument
        }

        public var description: String {
            argument.map { "\(action)(\($0))" } ?? action
        }
    }

    public struct Transition: Sendable {
        public let label: TransitionLabel
        public var action: String { label.description }
        public let target: StateID
        public init(action: String, target: StateID) {
            self.init(label: .init(action: action), target: target)
        }
        public init(label: TransitionLabel, target: StateID) {
            self.label = label; self.target = target
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
