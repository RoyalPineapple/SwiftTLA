import Darwin
import Foundation

package enum GraphRunRecords {
  package static func write(_ run: GraphRun, to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).jsonl")
    try Data().write(to: temporary, options: .withoutOverwriting)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let output = try FileHandle(forWritingTo: temporary)
    defer { try? output.close() }
    func emit(_ record: [String: Any]) throws {
      try autoreleasepool {
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(0x0a)
        try output.write(contentsOf: data)
      }
    }
    try emit([
      "type": "header",
      "schema": "swifttla.finite-graph",
      "version": 4,
      "observableActions": run.observableActions.sorted()
    ])
    for state in run.graph.initialStateKeys.sorted() {
      try emit(["type": "initial", "state": state.canonicalEncoding])
    }
    for state in run.graph.states.keys.sorted() {
      try emit(["type": "state", "state": state.canonicalEncoding])
    }
    for edge in run.graph.edges.sorted() {
      try emit([
        "type": "edge",
        "source": edge.source.canonicalEncoding,
        "action": edge.action,
        "target": edge.target.canonicalEncoding
      ])
    }
    if let trace = run.trace {
      try emit([
        "type": "trace",
        "id": trace.id,
        "cycleStartIndex": trace.cycleStartIndex.map { $0 as Any } ?? NSNull(),
        "steps": trace.steps.map {
          ["state": $0.state.canonicalEncoding, "action": $0.action.map { $0 as Any } ?? NSNull()]
        }
      ])
    }
    try emit([
      "type": "complete",
      "isComplete": run.isComplete,
      "outcome": outcomeRecord(run.outcome),
      "initialStateCount": run.graph.initialStateKeys.count,
      "stateCount": run.graph.states.count,
      "edgeCount": run.graph.edges.count,
      "traceCount": run.trace == nil ? 0 : 1
    ])
    try output.close()
    guard rename(temporary.path, url.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  static func outcomeRecord(_ outcome: GraphRunOutcome) -> [String: String] {
    switch outcome {
    case .noViolation:
      ["kind": "noViolation"]
    case .invariantViolation(let message):
      ["kind": "invariantViolation", "message": message]
    case .refinementViolation(let name):
      ["kind": "refinementViolation", "message": name]
    case .deadlock(let state):
      ["kind": "deadlock", "state": state.canonicalEncoding]
    case .incomplete(let reason):
      ["kind": "incomplete", "reason": reason]
    case .executionError(let message):
      ["kind": "executionError", "message": message]
    }
  }

}
