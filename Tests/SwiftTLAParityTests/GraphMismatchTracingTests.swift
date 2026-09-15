import Testing
import UpstreamParity

struct GraphMismatchTracingTests {
    @Test("transition mismatches retain complete rooted paths on both sides")
    func retainsReplayablePaths() throws {
        let states = (0...3).map { CanonicalState(bindings: ["x": .integer($0)]) }
        let common = [
            CanonicalEdge(source: states[0].key, action: "start", target: states[1].key),
            CanonicalEdge(source: states[1].key, action: "advance", target: states[2].key),
            CanonicalEdge(source: states[1].key, action: "reset", target: states[0].key),
            CanonicalEdge(source: states[0].key, action: "other", target: states[3].key)
        ]
        let tlc = try run(initial: [states[0]], states: states, edges: common + [
            .init(source: states[2].key, action: "finish", target: states[3].key)])
        let swift = try run(initial: [states[0]], states: states, edges: common + [
            .init(source: states[2].key, action: "stay", target: states[2].key)])
        let traces = try graphMismatchTraces(tlc: tlc, swift: swift)
        try #require(traces.count == 2)
        #expect(traces.map(\.id) == ["tlc-mismatch", "swift-mismatch"])
        #expect(traces[0].steps.map(\.state) == [0, 1, 2, 3].map { states[$0].key })
        #expect(traces[1].steps.map(\.state) == [0, 1, 2, 2].map { states[$0].key })
        #expect(traces[0].steps.map(\.action) == [nil, "start", "advance", "finish"])
        try traces[0].validate(in: tlc.graph)
        try traces[1].validate(in: swift.graph)
        let reordered = try run(initial: [states[0]], states: states.reversed(), edges: tlc.graph.edges.reversed())
        #expect(try graphMismatchTraces(tlc: reordered, swift: swift) == traces)
        #expect(try graphMismatchTraces(tlc: tlc, swift: tlc).isEmpty)
    }

    @Test("initial-state differences are rooted and unreachable evidence fails explicitly")
    func distinguishesInitialAndUnreachableStates() throws {
        let zero = CanonicalState(bindings: ["x": .integer(0)])
        let one = CanonicalState(bindings: ["x": .integer(1)])
        let base = try run(initial: [zero], states: [zero], edges: [])
        let additional = try run(initial: [zero, one], states: [zero, one], edges: [])
        let traces = try graphMismatchTraces(tlc: additional, swift: base)
        #expect(traces == [GraphTrace(id: "tlc-mismatch", steps: [.init(state: one.key, action: nil)])])
        let unreachable = try run(initial: [zero], states: [zero, one], edges: [])
        #expect(throws: EvidenceFormatError.self) {
            try graphMismatchTraces(tlc: unreachable, swift: base)
        }
        let incomplete = try GraphRun(isComplete: false, graph: base.graph,
            observableActions: [], outcome: .incomplete(reason: "state limit"))
        #expect(throws: EvidenceFormatError.self) {
            try graphMismatchTraces(tlc: incomplete, swift: base)
        }
    }

    private func run(initial: [CanonicalState], states: some Sequence<CanonicalState>,
        edges: some Sequence<CanonicalEdge>) throws -> GraphRun {
        let edges = Array(edges)
        return try GraphRun(isComplete: true,
            graph: CanonicalGraph(initialStates: initial, states: Array(states), edges: edges),
            observableActions: Set(edges.map(\.action)), outcome: .noViolation)
    }
}
