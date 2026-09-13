import Foundation
import SwiftTLA

/// A named model property and deadlock freedom are independent checks.
package enum ModelCheck: Equatable, Encodable, Sendable {
  case property(String)
  case deadlock

  package var artifactPath: String {
    switch self {
    case .property(let name): "properties/\(name)"
    case .deadlock: "deadlock"
    }
  }

  package func bundle(from rendered: RenderedSpecification) throws -> TLAModuleBundle {
    switch self {
    case .property(let name): try rendered.tlaBundle(checking: [name], checkDeadlock: false)
    case .deadlock: try rendered.tlaBundle(checking: [], checkDeadlock: true)
    }
  }
}

package enum PropertyComparisonStatus: String, Codable, Sendable {
  case exact
  case propertyOutcomeDifference
  case graphDifference
  case unavailable
}

package struct PropertyComparison: Equatable, Encodable, Sendable {
  package static let schema = "PropertyComparison"

  package let schema: String
  package let caseID: String
  package let check: ModelCheck
  package let status: PropertyComparisonStatus
  package let swiftResult: PropertyResult
  package let tlcResult: PropertyResult

  package init(
    caseID: String,
    check: ModelCheck,
    swiftRun: GraphRun,
    tlcRun: GraphRun,
    swiftResult: PropertyResult,
    tlcResult: PropertyResult
  ) throws {
    guard swiftRun.isComparable, tlcRun.isComparable else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "incomplete comparison graph")
    }
    for (result, graph) in [(swiftResult, swiftRun.graph), (tlcResult, tlcRun.graph)] {
      guard case .violated(let trace) = result else { continue }
      try trace.validate(in: graph)
      if check == .deadlock {
        guard trace.cycleStartIndex == nil, let final = trace.steps.last,
              !graph.edges.contains(where: { $0.source == final.state }) else {
          throw EvidenceFormatError.invalidField(record: caseID, field: "deadlock counterexample")
        }
      }
    }
    self.schema = Self.schema
    self.caseID = caseID
    self.check = check
    self.swiftResult = swiftResult
    self.tlcResult = tlcResult
    guard !caseID.isEmpty else {
      throw EvidenceFormatError.inconsistentReference(record: caseID, field: "property comparison")
    }
    switch (swiftResult, tlcResult) {
    case (.unavailable, _), (_, .unavailable):
      status = .unavailable
    case (.satisfied, .violated), (.violated, .satisfied):
      status = .propertyOutcomeDifference
    case (.satisfied, .satisfied), (.violated, .violated):
      status = compareFiniteGraphs(tlc: tlcRun, swift: swiftRun).matches
        ? .exact
        : .graphDifference
    }
  }
}
