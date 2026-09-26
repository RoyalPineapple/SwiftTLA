import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct GraphRunRecordsTests {
  @Test("buffered publication preserves every byte across flushes and oversized records")
  func preservesBufferedRecords() throws {
    let state = CanonicalState(bindings: ["x": .integer(0)])
    let actions = (0..<4096).map { "step-\($0)-" + String(repeating: "x", count: 300) }
      + [String(repeating: "large-\"\\\nλ", count: 150_000)]
    let edges = actions.map { CanonicalEdge(source: state.key, action: $0, target: state.key) }
    let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: edges)
    let run = try GraphRun(isComplete: true, graph: graph,
      observableActions: Set(actions), outcome: .noViolation)
    var expected: [[String: Any]] = [
      ["type": "header", "schema": "swifttla.finite-graph", "version": 4,
       "observableActions": actions.sorted()],
      ["type": "initial", "state": state.key.canonicalEncoding],
      ["type": "state", "state": state.key.canonicalEncoding]
    ]
    expected.append(contentsOf: edges.sorted().map {
      ["type": "edge", "source": $0.source.canonicalEncoding,
       "action": $0.action, "target": $0.target.canonicalEncoding]
    })
    expected.append(["type": "complete", "isComplete": true,
      "outcome": ["kind": "noViolation"], "initialStateCount": 1,
      "stateCount": 1, "edgeCount": edges.count, "traceCount": 0])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try GraphRunRecords.write(run, to: url)
    #expect(try Data(contentsOf: url) == data(for: expected))
  }

  @Test("graph publication preserves exact bytes and cleans temporary files")
  func publishesCompleteRecords() throws {
    let state = CanonicalState(bindings: ["x": .integer(0)])
    let graph = try CanonicalGraph(initialStates: [state], states: [state], edges: [
      CanonicalEdge(source: state.key, action: "step", target: state.key)
    ])
    let run = try GraphRun(isComplete: true, graph: graph, observableActions: ["step"], outcome: .noViolation)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("graph.jsonl")
    let expected = """
    {"observableActions":["step"],"schema":"swifttla.finite-graph","type":"header","version":4}
    {"state":"state:[78=integer:0]","type":"initial"}
    {"state":"state:[78=integer:0]","type":"state"}
    {"action":"step","source":"state:[78=integer:0]","target":"state:[78=integer:0]","type":"edge"}
    {"edgeCount":1,"initialStateCount":1,"isComplete":true,"outcome":{"kind":"noViolation"},"stateCount":1,"traceCount":0,"type":"complete"}
    """ + "\n"
    for _ in 0..<2 {
      try GraphRunRecords.write(run, to: url)
      #expect(try Data(contentsOf: url) == Data(expected.utf8))
      #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["graph.jsonl"])
    }
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    let sentinel = url.appendingPathComponent("keep")
    try Data("existing content".utf8).write(to: sentinel)
    #expect(throws: (any Error).self) { try GraphRunRecords.write(run, to: url) }
    #expect(try Data(contentsOf: sentinel) == Data("existing content".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["graph.jsonl"])
  }

  @Test("native lasso conversion rejects truncated paths and disconnected cycles")
  func rejectsMalformedNativeLassos() throws {
    let witnesses: [FairLassoWitness<Int, String?>] = [
      .init(prefix: [], cycle: [0, 0], prefixActions: [], cycleActions: [nil]),
      .init(prefix: [0, 1], cycle: [1, 1], prefixActions: [], cycleActions: [nil]),
      .init(prefix: [0], cycle: [0, 0], prefixActions: [], cycleActions: []),
      .init(prefix: [0], cycle: [1, 1], prefixActions: [], cycleActions: [nil]),
      .init(prefix: [0], cycle: [0, 1], prefixActions: [], cycleActions: ["advance"]),
      .init(prefix: [0], cycle: [0], prefixActions: [], cycleActions: [])
    ]
    for witness in witnesses {
      #expect(throws: GraphRunError.invalidLasso) {
        try GraphTrace(id: "invalid", witness: witness,
          stateKey: { CanonicalState(bindings: ["value": .integer($0)]).key }, actionName: { $0 })
      }
    }
  }

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
      (.invariantViolated(invariant: "Check", state: projection, trace: [.init(state: projection, action: "init")]),
       ["kind": "invariantViolation", "message": "Check"]),
      (.refinementViolated(refinement: "Check",
        failure: .initialState(mapped: projection, abstractInitialStates: [])),
       ["kind": "refinementViolation", "message": "Check"])
    ]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    for (outcome, expected) in outcomes {
      let failed = FiniteExploration(
        graph: exploration.graph, initialStateIDs: exploration.initialStateIDs,
        completion: outcome, compilationIdentity: exploration.compilationIdentity,
        configuration: exploration.configuration, compiledStates: exploration.compiledStates
      )
      let run = try FormalGraphExporter().export(failed)
      try GraphRunRecords.write(run, to: url)
      let completion = try #require(records(in: Data(contentsOf: url)).last)
      #expect(completion["outcome"] as? [String: String] == expected)
      #expect(completion["isComplete"] as? Bool == false)
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
    let run = try GraphRun(
      isComplete: true,
      graph: CanonicalGraph(
        initialStates: [initial],
        states: states,
        edges: [.init(source: initial.key, action: "advance", target: second.key)]
      ),
      observableActions: ["advance"],
      outcome: .noViolation
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("swift-graph.jsonl")
    try GraphRunRecords.write(run, to: url)

    let data = try Data(contentsOf: url)
    let streamRecords = try records(in: data)
    #expect(streamRecords.map { $0["type"] as? String } == [
      "header", "initial", "state", "state", "state", "state", "edge", "complete"
    ])
    let completion = try #require(streamRecords.last)
    #expect(streamRecords.first?["version"] as? Int == 4)
    let edge = try #require(streamRecords.first { $0["type"] as? String == "edge" })
    #expect(Set(edge.keys) == ["type", "source", "action", "target"])
    #expect(completion["isComplete"] as? Bool == true)
    #expect(completion["initialStateCount"] as? Int == 1)
    #expect(completion["stateCount"] as? Int == 4)
    #expect(completion["edgeCount"] as? Int == 1)

    let truncated = streamRecords.dropLast()
    #expect(truncated.last?["type"] as? String != "complete")

    let incomplete = try GraphRun(
      isComplete: false,
      graph: run.graph,
      observableActions: run.observableActions,
      outcome: .incomplete(reason: "state limit reached")
    )
    let incompleteURL = root.appendingPathComponent("incomplete-graph.jsonl")
    try GraphRunRecords.write(incomplete, to: incompleteURL)
    let incompleteRecords = try records(in: Data(contentsOf: incompleteURL))
    #expect(incompleteRecords.last?["isComplete"] as? Bool == false)
    #expect((incompleteRecords.last?["outcome"] as? [String: String])?["kind"] == "incomplete")
  }

  @Test("completed graph run retains its counterexample trace")
  func graphStreamRetainsTrace() throws {
    let first = state(counter: 1, values: [.integer(1)])
    let second = state(counter: 2, values: [.integer(2)])
    let run = try GraphRun(
      isComplete: true,
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
          .init(state: first.key, action: nil),
          .init(state: second.key, action: "advance")
        ]
      )
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("graph.jsonl")
    try GraphRunRecords.write(run, to: url)

    let streamRecords = try records(in: Data(contentsOf: url))
    let trace = try #require(streamRecords.first { $0["type"] as? String == "trace" })
    #expect(trace["id"] as? String == "counterexample")
    #expect((trace["steps"] as? [[String: Any]])?.count == 2)
    #expect(streamRecords.last?["traceCount"] as? Int == 1)
    #expect(streamRecords.last?["isComplete"] as? Bool == true)
  }

  @Test("retained counterexamples must follow graph transitions from an initial state")
  func rejectsInvalidTracePaths() throws {
    let first = state(counter: 0, values: [])
    let second = state(counter: 1, values: [])
    let missing = state(counter: 2, values: [])
    let graph = try graph(first, second,
      edges: [.init(source: first.key, action: "advance", target: second.key)])
    let invalid: [[GraphTraceStep]] = [
      [],
      [.init(state: first.key, action: "Init")],
      [.init(state: first.key, action: nil), .init(state: second.key, action: nil)],
      [.init(state: missing.key, action: nil)],
      [.init(state: second.key, action: nil)],
      [.init(state: first.key, action: nil), .init(state: second.key, action: "wrong")],
      [.init(state: first.key, action: nil), .init(state: first.key, action: "advance")]
    ]
    for steps in invalid {
      #expect(throws: GraphRunError.self) {
        try GraphRun(isComplete: true, graph: graph, observableActions: ["advance"],
          outcome: .invariantViolation("Check"), trace: .init(id: "invalid", steps: steps))
      }
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
    try GraphRunRecords.write(
      GraphRun(
        isComplete: true,
        graph: graph,
        observableActions: graph.observedActions,
        outcome: .noViolation
      ),
      to: url
    )
    let graphRecordTypes = Set(["initial", "state", "edge"])
    return try data(for: records(in: Data(contentsOf: url)).filter {
      graphRecordTypes.contains($0["type"] as? String ?? "")
    })
  }

}
