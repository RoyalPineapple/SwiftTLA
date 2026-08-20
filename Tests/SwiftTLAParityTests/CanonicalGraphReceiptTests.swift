import Testing
@testable import UpstreamParity

struct CanonicalGraphReceiptTests {
  @Test("canonical graph receipt ignores traversal and collection insertion order")
  func receiptIsStableAcrossEquivalentGraphs() throws {
    let first = state(counter: 1, values: [.integer(2), .integer(1)])
    let second = state(counter: 2, values: [.integer(1), .integer(2)])
    let forward = try graph(first, second, edges: [
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: second.key, action: "reset", target: first.key)
    ])
    let reversed = try graph(second, first, edges: [
      .init(source: second.key, action: "reset", target: first.key),
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: first.key, action: "advance", target: second.key)
    ])

    let forwardReceipt = receipt(forward)
    #expect(forwardReceipt.initialStateCount == 1)
    #expect(forwardReceipt.stateCount == 2)
    #expect(forwardReceipt.edgeCount == 3)
    #expect(forwardReceipt == receipt(reversed))
  }

  @Test("canonical graph receipt changes for graph and identity changes")
  func receiptChangesForMeaningfulDifferences() throws {
    let first = state(counter: 1, values: [.integer(1), .integer(2)])
    let second = state(counter: 2, values: [.integer(1), .integer(2)])
    let base = try graph(first, second, edges: [
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: first.key, action: "advance", target: second.key)
    ])
    let changedAction = try graph(first, second, edges: [
      .init(source: first.key, action: "reset", target: second.key),
      .init(source: first.key, action: "advance", target: second.key)
    ])
    let removedRepeatedEdge = try graph(first, second, edges: [
      .init(source: first.key, action: "advance", target: second.key)
    ])
    let changedState = state(counter: 3, values: [.integer(1), .integer(2)])
    let changedStateGraph = try graph(first, changedState, edges: [
      .init(source: first.key, action: "advance", target: changedState.key),
      .init(source: first.key, action: "advance", target: changedState.key)
    ])

    #expect(receipt(base).graphDigest != receipt(changedAction).graphDigest)
    #expect(receipt(base).graphDigest != receipt(removedRepeatedEdge).graphDigest)
    #expect(receipt(base).graphDigest != receipt(changedStateGraph).graphDigest)
    #expect(receipt(base, configuration: "config-2").graphDigest != receipt(base).graphDigest)
    #expect(receipt(base, symmetry: "symmetry-2").graphDigest != receipt(base).graphDigest)
    #expect(receipt(base, limit: 3).graphDigest != receipt(base, limit: 2).graphDigest)
    #expect(
      receipt(base, diagnostics: [.init(code: "source", message: "changed")]).graphDigest
        != receipt(base).graphDigest
    )
  }

  @Test("bounded graph receipt cannot support exact conformance")
  func boundedReceiptCannotEqualCompleteReceipt() throws {
    let first = state(counter: 1, values: [.integer(1)])
    let complete = receipt(try graph(first, first, edges: []))
    let bounded = receipt(
      try graph(first, first, edges: []),
      status: .bounded,
      outcome: .incomplete(reason: "state limit reached")
    )
    let failed = receipt(
      try graph(first, first, edges: []),
      status: .failed,
      outcome: .executionError("exploration failed")
    )

    #expect(complete.supportsExactConformance)
    #expect(!bounded.supportsExactConformance)
    #expect(!failed.supportsExactConformance)
    #expect(complete != bounded)
    #expect(complete != failed)
  }

  private func state(counter: Int, values: [CanonicalValue]) -> CanonicalState {
    CanonicalState(bindings: [
      "counter": .integer(counter),
      "values": .set(values)
    ])
  }

  private func graph(
    _ first: CanonicalState,
    _ second: CanonicalState,
    edges: [CanonicalEdge]
  ) throws -> CanonicalGraph {
    try CanonicalGraph(initialStates: [first], states: [first, second], edges: edges)
  }

  private func receipt(
    _ graph: CanonicalGraph,
    configuration: String = "config-1",
    symmetry: String = "symmetry-1",
    limit: Int = 2,
    status: CanonicalGraphReceipt.ExplorationStatus = .complete,
    outcome: CanonicalOutcome = .exhaustiveSuccess,
    diagnostics: [CanonicalDiagnostic] = []
  ) -> CanonicalGraphReceipt {
    CanonicalGraphReceipt(
      graph: graph,
      compiledModelIdentity: "model-1",
      configurationIdentity: configuration,
      symmetrySchemaIdentity: symmetry,
      explorationStatus: status,
      maximumStateLimit: limit,
      outcome: outcome,
      diagnostics: diagnostics
    )
  }
}
