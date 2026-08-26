import Foundation

package struct TemporalComparison: Equatable, Encodable, Sendable {
  package static let schema = "TemporalComparison"

  package let schema: String
  package let caseID: String
  package let configuration: TemporalCaseConfiguration
  package let status: TemporalComparisonStatus
  package let swiftResult: TemporalPropertyResult
  package let tlcResult: TemporalPropertyResult

  package init(
    caseID: String,
    configuration: TemporalCaseConfiguration,
    swiftRun: CompletedGraphRun,
    tlcRun: CompletedGraphRun,
    swiftResult: TemporalPropertyResult,
    tlcResult: TemporalPropertyResult
  ) throws {
    guard swiftRun.isPassEligible, tlcRun.isPassEligible else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "incomplete comparison graph")
    }
    self.schema = Self.schema
    self.caseID = caseID
    self.configuration = configuration
    self.swiftResult = swiftResult
    self.tlcResult = tlcResult
    guard !caseID.isEmpty else {
      throw EvidenceFormatError.inconsistentReference(record: caseID, field: "temporal comparison")
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
