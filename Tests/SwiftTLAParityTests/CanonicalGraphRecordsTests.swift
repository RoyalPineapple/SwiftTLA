import Foundation
import Testing
@testable import UpstreamParity

struct CanonicalGraphRecordsTests {
  @Test("canonical graph records ignore traversal and collection insertion order")
  func recordsAreStableAcrossEquivalentGraphs() throws {
    let first = state(counter: 1, values: [.integer(2), .integer(1)])
    let second = state(counter: 2, values: [.integer(1), .integer(2)])
    let forward = try graph(first, second, edges: [
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: second.key, action: "reset", target: first.key)
    ])
    let reversed = try CanonicalGraph(initialStates: [first], states: [second, first], edges: [
      .init(source: second.key, action: "reset", target: first.key),
      .init(source: first.key, action: "advance", target: second.key),
      .init(source: first.key, action: "advance", target: second.key)
    ])

    #expect(CanonicalGraphRecords.digest(for: forward) == CanonicalGraphRecords.digest(for: reversed))

    let changed = try graph(first, second, edges: [
      .init(source: first.key, action: "reset", target: second.key)
    ])
    #expect(CanonicalGraphRecords.digest(for: forward) != CanonicalGraphRecords.digest(for: changed))
  }

  @Test("canonical run evidence verifies its sorted graph chunks")
  func canonicalRunEvidenceUsesVerifiedChunks() throws {
    let states = (0...CanonicalGraphRecords.recordsPerChunk).map {
      state(counter: $0, values: [.integer($0)])
    }
    let initial = try #require(states.first)
    let second = try #require(states.dropFirst().first)
    let run = try CanonicalRun(
      graph: CanonicalGraph(
        initialStates: [initial],
        states: states,
        edges: [.init(source: initial.key, action: "advance", target: second.key)]
      ),
      observableActions: ["advance"],
      outcome: .exhaustiveSuccess
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("swift-run.json")
    try CanonicalRunEvidence.write(
      run,
      correlation: .init(caseID: "chunked", runID: UUID(), engine: .swift),
      to: url
    )

    let loaded = try CanonicalRunEvidence.read(from: url)
    #expect(loaded.run == run)
    #expect(loaded.evidence.graph.chunks.count == 2)

    let firstChunk = root.appendingPathComponent("swift-run.graph/000000.jsonl")
    try Data("changed".utf8).write(to: firstChunk, options: .atomic)
    #expect(throws: CanonicalRunEvidenceError.self) {
      try CanonicalRunEvidence.read(from: url)
    }
  }

  private func state(counter: Int, values: [CanonicalValue]) -> CanonicalState {
    CanonicalState(bindings: ["counter": .integer(counter), "values": .set(values)])
  }

  private func graph(
    _ first: CanonicalState,
    _ second: CanonicalState,
    edges: [CanonicalEdge]
  ) throws -> CanonicalGraph {
    try CanonicalGraph(initialStates: [first], states: [first, second], edges: edges)
  }
}
