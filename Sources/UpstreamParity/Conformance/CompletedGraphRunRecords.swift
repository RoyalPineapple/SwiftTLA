import Foundation

package enum CompletedGraphRunRecords {
  package static func write(_ run: CompletedGraphRun, to url: URL) throws {
    try encoded(records(for: run)).write(to: url, options: .atomic)
  }

  private static func graphRecords(for graph: CanonicalGraph) -> [[String: Any]] {
    graph.initialStateKeys.sorted().map {
      ["type": "initial", "state": $0.canonicalEncoding]
    } + graph.states.keys.sorted().map {
      ["type": "state", "state": $0.canonicalEncoding]
    } + graph.edgeOccurrences.keys.sorted().map { edge in
      [
        "type": "edge",
        "source": edge.source.canonicalEncoding,
        "action": edge.action,
        "target": edge.target.canonicalEncoding,
        "occurrences": graph.edgeOccurrences[edge, default: 0]
      ]
    }
  }

  private static func encoded(_ records: [[String: Any]]) throws -> Data {
    try records.reduce(into: Data()) { output, record in
      output.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      output.append(0x0a)
    }
  }

  private static func records(for run: CompletedGraphRun) -> [[String: Any]] {
    var records: [[String: Any]] = [[
      "type": "header",
      "schema": "swifttla.finite-graph",
      "version": 1,
      "observableActions": run.observableActions.sorted()
    ]]
    records += graphRecords(for: run.graph)
    if let trace = run.trace {
      records.append([
        "type": "trace",
        "id": trace.id,
        "steps": trace.steps.map {
          ["state": $0.state.canonicalEncoding, "action": $0.action]
        }
      ])
    }
    records.append([
      "type": "complete",
      "eligible": run.isPassEligible,
      "outcome": outcomeRecord(run.outcome),
      "initialStateCount": run.graph.initialStateKeys.count,
      "stateCount": run.graph.states.count,
      "edgeCount": run.graph.edgeOccurrences.values.reduce(0, +),
      "traceCount": run.trace == nil ? 0 : 1
    ])
    return records
  }

  static func outcomeRecord(_ outcome: GraphRunOutcome) -> [String: String] {
    switch outcome {
    case .exhaustiveSuccess:
      ["kind": "exhaustiveSuccess"]
    case .invariantViolation(let message):
      ["kind": "invariantViolation", "message": message]
    case .deadlock(let state):
      ["kind": "deadlock", "state": state.canonicalEncoding]
    case .incomplete(let reason):
      ["kind": "incomplete", "reason": reason]
    case .executionError(let message):
      ["kind": "executionError", "message": message]
    }
  }

}
