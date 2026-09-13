import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct CompletedGraphRunRecordsTests {
  @Test("exported failures preserve their check category in retained records")
  func preservesFailureCategories() throws {
    let value = Var<Int>("value")
    let compilation = try TLASpec("FailureCategories") { Variable(value, 0) }.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
    ).explore()
    let initial = try #require(exploration.initialStateIDs.first)
    let projection = try #require(exploration.graph.states[initial])
    let outcomes: [(ModelCheckOutcome, [String: String])] = [
      (.invariantViolated(invariant: "Check", state: projection, trace: []),
       ["kind": "invariantViolation", "message": "Check"]),
      (.livenessViolated(property: "Check", reason: .violatingFairLasso,
        witness: .init(prefix: [initial], cycle: [initial, initial],
          prefixActions: [], cycleActions: ["[stutter]"])),
       ["kind": "temporalViolation", "property": "Check", "reason": "violating-fair-lasso"]),
      (.refinementViolated(refinement: "Check",
        failure: .initialState(mapped: projection, abstractInitialStates: [])),
       ["kind": "refinementViolation", "message": "Check"])
    ]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    for (outcome, expected) in outcomes {
      let failed = FiniteExploration(
        graph: exploration.graph, initialStateIDs: exploration.initialStateIDs,
        outcome: outcome, compilationIdentity: exploration.compilationIdentity,
        configuration: exploration.configuration, compiledStates: exploration.compiledStates
      )
      let run = try SwiftGraphExporter().export(failed)
      try CompletedGraphRunRecords.write(run, to: url)
      let completion = try #require(records(in: Data(contentsOf: url)).last)
      #expect(completion["outcome"] as? [String: String] == expected)
      #expect(completion["eligible"] as? Bool == false)
    }
  }

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

    #expect(try encodedGraph(forward) == encodedGraph(reversed))

    let changed = try graph(first, second, edges: [
      .init(source: first.key, action: "reset", target: second.key)
    ])
    #expect((try encodedGraph(forward) == encodedGraph(changed)) == false)
  }

  @Test("canonical graph stream declares completion and exact counts")
  func graphStreamDeclaresCompletion() throws {
    let states = (0...3).map {
      state(counter: $0, values: [.integer($0)])
    }
    let initial = try #require(states.first)
    let second = try #require(states.dropFirst().first)
    let run = try CompletedGraphRun(
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
    try CompletedGraphRunRecords.write(run, to: url)

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

    let incomplete = try CompletedGraphRun(
      graph: run.graph,
      observableActions: run.observableActions,
      outcome: .incomplete(reason: "state limit reached")
    )
    let incompleteURL = root.appendingPathComponent("incomplete-graph.jsonl")
    try CompletedGraphRunRecords.write(incomplete, to: incompleteURL)
    let incompleteRecords = try records(in: Data(contentsOf: incompleteURL))
    #expect(incompleteRecords.last?["eligible"] as? Bool == false)
    #expect((incompleteRecords.last?["outcome"] as? [String: String])?["kind"] == "incomplete")
  }

  @Test("completed graph run retains its counterexample trace")
  func graphStreamRetainsTrace() throws {
    let first = state(counter: 1, values: [.integer(1)])
    let second = state(counter: 2, values: [.integer(2)])
    let run = try CompletedGraphRun(
      graph: graph(
        first,
        second,
        edges: [.init(source: first.key, action: "advance", target: second.key)]
      ),
      observableActions: ["advance"],
      outcome: .invariantViolation("counter escaped its range"),
      trace: .init(
        id: "counterexample",
        steps: [
          .init(state: first.key, action: "advance"),
          .init(state: second.key, action: "")
        ]
      )
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("graph.jsonl")
    try CompletedGraphRunRecords.write(run, to: url)

    let streamRecords = try records(in: Data(contentsOf: url))
    let trace = try #require(streamRecords.first { $0["type"] as? String == "trace" })
    #expect(trace["id"] as? String == "counterexample")
    #expect((trace["steps"] as? [[String: String]])?.count == 2)
    #expect(streamRecords.last?["traceCount"] as? Int == 1)
    #expect(streamRecords.last?["eligible"] as? Bool == false)
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

  private func data(for records: [[String: Any]]) throws -> Data {
    try records.reduce(into: Data()) { data, record in
      data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      data.append(0x0a)
    }
  }

  private func encodedGraph(_ graph: CanonicalGraph) throws -> Data {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("graph.jsonl")
    try CompletedGraphRunRecords.write(
      CompletedGraphRun(
        graph: graph,
        observableActions: Set(graph.edgeOccurrences.keys.map(\.action)),
        outcome: .exhaustiveSuccess
      ),
      to: url
    )
    let graphRecordTypes = Set(["initial", "state", "edge"])
    return try data(for: records(in: Data(contentsOf: url)).filter {
      graphRecordTypes.contains($0["type"] as? String ?? "")
    })
  }

}
