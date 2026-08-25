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

  @Test("canonical graph stream declares completion and exact counts")
  func graphStreamDeclaresCompletion() throws {
    let states = (0...3).map {
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
    let url = root.appendingPathComponent("swift-graph.jsonl")
    try CanonicalGraphRecords.write(run, to: url)

    let data = try Data(contentsOf: url)
    let streamRecords = try records(in: data)
    #expect(streamRecords.map { $0["type"] as? String } == [
      "header", "initial", "state", "state", "state", "state", "edge", "complete"
    ])
    let completion = try #require(streamRecords.last)
    #expect(completion["eligible"] as? Bool == true)
    #expect(completion["initialStateCount"] as? Int == 1)
    #expect(completion["stateCount"] as? Int == 4)
    #expect(completion["edgeCount"] as? Int == 1)

    let truncated = streamRecords.dropLast()
    #expect(truncated.last?["type"] as? String != "complete")

    let incomplete = try CanonicalRun(
      graph: run.graph,
      observableActions: run.observableActions,
      outcome: .incomplete(reason: "state limit reached")
    )
    let incompleteURL = root.appendingPathComponent("incomplete-graph.jsonl")
    try CanonicalGraphRecords.write(incomplete, to: incompleteURL)
    let incompleteRecords = try records(in: Data(contentsOf: incompleteURL))
    #expect(incompleteRecords.last?["eligible"] as? Bool == false)
    #expect((incompleteRecords.last?["outcome"] as? [String: String])?["kind"] == "incomplete")
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

  private func records(in data: Data) throws -> [[String: Any]] {
    try data.split(separator: 0x0a).map {
      try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
    }
  }

}
