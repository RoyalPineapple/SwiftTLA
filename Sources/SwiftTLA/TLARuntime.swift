public struct TLARuntime: CustomStringConvertible {
    public private(set) var state: [String: TLAValue]
    public private(set) var history: [String]
    private let graph: StateGraph
    private let initialState: [String: TLAValue]
    private let specName: String

    public init(spec: TLASpec) {
        let checker = ModelChecker(spec: spec)
        guard let g = try? checker.exploreGraph() else { fatalError("Could not explore graph") }
        self.graph = g
        self.specName = spec.name
        self.initialState = spec.variables.reduce(into: [:]) { $0[$1.name] = $1.initial }
        self.state = initialState
        self.history = []
    }

    public var availableActions: [String] {
        guard let id = graph.stateID(for: state) else { return [] }
        return graph.transitions[id]?.map(\.action) ?? []
    }

    public mutating func apply(_ action: String) {
        guard let id = graph.stateID(for: state),
              let t = graph.transitions[id]?.first(where: { $0.action == action }),
              let next = graph.states[t.target] else { return }
        state = next
        history.append(action)
    }

    public mutating func reset() {
        state = initialState
        history = []
    }

    public var description: String {
        var lines = ["TLARuntime(\(specName))"]
        lines.append("  state: \(state.sorted(by: { $0.key < $1.key }).map { "\($0.key) = \($0.value)" }.joined(separator: ", "))")
        lines.append("  available: [\(availableActions.joined(separator: ", "))]")
        if !history.isEmpty { lines.append("  history: [\(history.joined(separator: " → "))]") }
        return lines.joined(separator: "\n")
    }
}

extension StateGraph {
    func stateID(for state: [String: TLAValue]) -> StateID? {
        states.first(where: { $0.value == state })?.key
    }
}
