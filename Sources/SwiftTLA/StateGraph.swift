public struct StateGraph: Sendable {
    public let specName: String
    public let variableNames: [String]
    public let transitions: [StateID: [(action: String, target: StateID)]]
    public let states: [StateID: [String: TLAValue]]

    public init(
        specName: String,
        variableNames: [String],
        transitions: [StateID: [(action: String, target: StateID)]],
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
