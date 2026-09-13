import Foundation

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
  package let property: String
  package let status: PropertyComparisonStatus
  package let swiftResult: PropertyResult
  package let tlcResult: PropertyResult

  package init(
    caseID: String,
    property: String,
    swiftRun: GraphRun,
    tlcRun: GraphRun,
    swiftResult: PropertyResult,
    tlcResult: PropertyResult
  ) throws {
    guard swiftRun.isComparable, tlcRun.isComparable else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "incomplete comparison graph")
    }
    if case .violated(let trace) = swiftResult { try trace.validate(in: swiftRun.graph) }
    if case .violated(let trace) = tlcResult { try trace.validate(in: tlcRun.graph) }
    self.schema = Self.schema
    self.caseID = caseID
    self.property = property
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
