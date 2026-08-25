import Foundation

package enum CanonicalGraphRecords {
  package static func write(_ run: CanonicalRun, to url: URL) throws {
    let data = try records(for: run).reduce(into: Data()) { output, record in
      output.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      output.append(0x0a)
    }
    try data.write(to: url, options: .atomic)
  }

  package static func digest(for graph: CanonicalGraph) -> String {
    SHA256.hex(Data(graphRecords(for: graph).joined(separator: "\n").utf8))
  }

  private static func graphRecords(for graph: CanonicalGraph) -> [String] {
    graph.initialStateKeys.sorted().map { "initial:\($0.canonicalEncoding)" }
      + graph.states.keys.sorted().map { "state:\($0.canonicalEncoding)" }
      + graph.edgeOccurrences.keys.sorted().map { edge in
        "\(edge.canonicalEncoding);occurrences:\(graph.edgeOccurrences[edge, default: 0])"
      }
  }

  private static func records(for run: CanonicalRun) -> [[String: Any]] {
    let graph = run.graph
    return [[
      "type": "header",
      "schema": run.schema.rawValue,
      "observableActions": run.observableActions.sorted()
    ]] + graph.initialStateKeys.sorted().map {
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
    } + [[
      "type": "complete",
      "eligible": run.isPassEligible,
      "outcome": outcome(run.outcome),
      "initialStateCount": graph.initialStateKeys.count,
      "stateCount": graph.states.count,
      "edgeCount": graph.edgeOccurrences.values.reduce(0, +),
      "errorCount": run.errors.count
    ]]
  }

  private static func outcome(_ outcome: CanonicalOutcome) -> [String: String] {
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
