import Foundation

package enum GraphRunRecords {
  package static func write(_ run: GraphRun, to url: URL) throws {
    try encoded(records(for: run)).write(to: url, options: .atomic)
  }

  private static func graphRecords(for graph: CanonicalGraph) -> [[String: Any]] {
    graph.initialStateKeys.sorted().map {
      ["type": "initial", "state": $0.canonicalEncoding]
    } + graph.states.keys.sorted().map {
      ["type": "state", "state": $0.canonicalEncoding]
    } + graph.edges.sorted().map { edge in
      [
        "type": "edge",
        "source": edge.source.canonicalEncoding,
        "action": edge.action,
        "target": edge.target.canonicalEncoding
      ]
    }
  }

  private static func encoded(_ records: [[String: Any]]) throws -> Data {
    try records.reduce(into: Data()) { output, record in
      output.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      output.append(0x0a)
    }
  }

  private static func records(for run: GraphRun) -> [[String: Any]] {
    var records: [[String: Any]] = [[
      "type": "header",
      "schema": "swifttla.finite-graph",
      "version": 4,
      "observableActions": run.observableActions.sorted()
    ]]
    records += graphRecords(for: run.graph)
    if let trace = run.trace {
      records.append([
        "type": "trace",
        "id": trace.id,
        "cycleStartIndex": trace.cycleStartIndex.map { $0 as Any } ?? NSNull(),
        "steps": trace.steps.map {
          ["state": $0.state.canonicalEncoding, "action": $0.action.map { $0 as Any } ?? NSNull()]
        }
      ])
    }
    records.append([
      "type": "complete",
      "isComplete": run.isComplete,
      "outcome": outcomeRecord(run.outcome),
      "initialStateCount": run.graph.initialStateKeys.count,
      "stateCount": run.graph.states.count,
      "edgeCount": run.graph.edges.count,
      "traceCount": run.trace == nil ? 0 : 1
    ])
    return records
  }

  static func outcomeRecord(_ outcome: GraphRunOutcome) -> [String: String] {
    switch outcome {
    case .noViolation:
      ["kind": "noViolation"]
    case .invariantViolation(let message):
      ["kind": "invariantViolation", "message": message]
    case .temporalViolation(let property, let reason):
      ["kind": "temporalViolation", "property": property, "reason": reason.rawValue]
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
