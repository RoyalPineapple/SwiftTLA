public struct StateGraph: Codable, Sendable {
    public let specName: String
    public let variableNames: [String]
    public struct Transition: Codable, Sendable {
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

    public struct StateID: Hashable, Codable, Sendable, CustomStringConvertible {
        public let id: Int
        public init(_ id: Int) { self.id = id }
        public var description: String { "s\(id)" }
    }
}
