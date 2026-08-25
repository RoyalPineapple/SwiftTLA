import Foundation

package enum CanonicalGraphRecords {
  package static let recordsPerChunk = 512

  package static func chunks(for graph: CanonicalGraph) -> [[String]] {
    let records = records(for: graph)
    guard !records.isEmpty else { return [[]] }
    return stride(from: 0, to: records.count, by: recordsPerChunk).map {
      Array(records[$0..<min($0 + recordsPerChunk, records.count)])
    }
  }

  package static func digest(for graph: CanonicalGraph) -> String {
    digest(records(for: graph))
  }

  static func digest(_ records: [String]) -> String {
    SHA256.hex(Data(records.joined(separator: "\n").utf8))
  }

  private static func records(for graph: CanonicalGraph) -> [String] {
    graph.initialStateKeys.sorted().map { "initial:\($0.canonicalEncoding)" }
      + graph.states.keys.sorted().map { "state:\($0.canonicalEncoding)" }
      + graph.edgeOccurrences.keys.sorted().map { edge in
        "\(edge.canonicalEncoding);occurrences:\(graph.edgeOccurrences[edge, default: 0])"
      }
  }
}
