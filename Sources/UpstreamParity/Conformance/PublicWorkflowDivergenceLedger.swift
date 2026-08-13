import Foundation

public enum PublicWorkflowDivergenceClassificationV1: String, Codable, Sendable {
  case swiftTLADefect
  case harnessOrConfigurationDefect
  case unsupportedConstruct
  case publishedSemanticsAmbiguity
  case suspectedTLCDefect
}

public enum PublicWorkflowDivergenceDispositionV1: String, Codable, Sendable {
  case open
  case resolved
  case unsupported
  case awaitingSemanticsReview
  case suspectedReferenceDefect
}

public struct PublicWorkflowDivergenceComparisonV1: Equatable, Codable, Sendable {
  public let evidence: CoreEvidenceReferenceV1
  public let outcome: PublicWorkflowExpectedOutcomeV1
  public let normalizedDifferenceFingerprint: String?

  public init(evidence: CoreEvidenceReferenceV1, outcome: PublicWorkflowExpectedOutcomeV1, normalizedDifferenceFingerprint: String?) throws {
    self.evidence = evidence
    self.outcome = outcome
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    try validate()
  }

  public func validate() throws {
    try evidence.validate()
    guard outcome == .difference ? normalizedDifferenceFingerprint?.isEmpty == false : normalizedDifferenceFingerprint == nil else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "comparison", field: "normalizedDifferenceFingerprint")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case evidence, outcome, normalizedDifferenceFingerprint }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(evidence: try container.decode(CoreEvidenceReferenceV1.self, forKey: .evidence), outcome: try container.decode(PublicWorkflowExpectedOutcomeV1.self, forKey: .outcome), normalizedDifferenceFingerprint: try container.decodeIfPresent(String.self, forKey: .normalizedDifferenceFingerprint))
  }
}

public struct PublicWorkflowDivergenceRecordV1: Equatable, Codable, Sendable {
  public let id: String
  public let caseID: String
  public let semanticCitations: [String]
  public let reproducer: CoreFiniteBoundsV1
  public let originalEvidence: CoreEvidenceReferenceV1
  public let permanentRegressionCaseID: String
  public let classification: PublicWorkflowDivergenceClassificationV1
  public let disposition: PublicWorkflowDivergenceDispositionV1
  public let normalizedDifferenceFingerprint: String
  public let latestComparison: PublicWorkflowDivergenceComparisonV1

  public init(id: String, caseID: String, semanticCitations: [String], reproducer: CoreFiniteBoundsV1, originalEvidence: CoreEvidenceReferenceV1, permanentRegressionCaseID: String, classification: PublicWorkflowDivergenceClassificationV1, disposition: PublicWorkflowDivergenceDispositionV1, normalizedDifferenceFingerprint: String, latestComparison: PublicWorkflowDivergenceComparisonV1) throws {
    self.id = id
    self.caseID = caseID
    self.semanticCitations = semanticCitations
    self.reproducer = reproducer
    self.originalEvidence = originalEvidence
    self.permanentRegressionCaseID = permanentRegressionCaseID
    self.classification = classification
    self.disposition = disposition
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    self.latestComparison = latestComparison
    try validate()
  }

  public func validate() throws {
    try reproducer.validate()
    try originalEvidence.validate()
    try latestComparison.validate()
    guard !id.isEmpty, !caseID.isEmpty, !permanentRegressionCaseID.isEmpty, !normalizedDifferenceFingerprint.isEmpty,
          !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "required evidence")
    }
    guard disposition != .resolved || latestComparison.outcome == .exact else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "latest comparison")
    }
    guard latestComparison.outcome != .difference || latestComparison.normalizedDifferenceFingerprint == normalizedDifferenceFingerprint else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "fingerprint drift")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case id, caseID, semanticCitations, reproducer, originalEvidence, permanentRegressionCaseID, classification, disposition, normalizedDifferenceFingerprint, latestComparison }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(id: try container.decode(String.self, forKey: .id), caseID: try container.decode(String.self, forKey: .caseID), semanticCitations: try container.decode([String].self, forKey: .semanticCitations), reproducer: try container.decode(CoreFiniteBoundsV1.self, forKey: .reproducer), originalEvidence: try container.decode(CoreEvidenceReferenceV1.self, forKey: .originalEvidence), permanentRegressionCaseID: try container.decode(String.self, forKey: .permanentRegressionCaseID), classification: try container.decode(PublicWorkflowDivergenceClassificationV1.self, forKey: .classification), disposition: try container.decode(PublicWorkflowDivergenceDispositionV1.self, forKey: .disposition), normalizedDifferenceFingerprint: try container.decode(String.self, forKey: .normalizedDifferenceFingerprint), latestComparison: try container.decode(PublicWorkflowDivergenceComparisonV1.self, forKey: .latestComparison))
  }
}

public struct PublicWorkflowDivergenceLedgerV1: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowDivergenceLedgerV1"
  public let schema: String
  public let records: [PublicWorkflowDivergenceRecordV1]

  public init(records: [PublicWorkflowDivergenceRecordV1]) throws { try self.init(schema: Self.schema, records: records) }

  public init(schema: String, records: [PublicWorkflowDivergenceRecordV1]) throws {
    guard schema == Self.schema else { throw PublicWorkflowGovernanceErrorV1.invalidSchema(schema) }
    var ids = Set<String>()
    for record in records {
      try record.validate()
      guard ids.insert(record.id).inserted else { throw PublicWorkflowGovernanceErrorV1.duplicateID(kind: "divergence", id: record.id) }
    }
    self.schema = schema
    self.records = records
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, records }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), records: try container.decode([PublicWorkflowDivergenceRecordV1].self, forKey: .records))
  }

  public func validate(caseIDs: Set<String>) throws {
    for record in records {
      guard caseIDs.contains(record.caseID), caseIDs.contains(record.permanentRegressionCaseID) else {
        throw PublicWorkflowGovernanceErrorV1.unknownCaseID(caseIDs.contains(record.caseID) ? record.permanentRegressionCaseID : record.caseID)
      }
    }
  }

  public var unexplainedRecords: [PublicWorkflowDivergenceRecordV1] {
    records.filter { $0.disposition != .resolved || $0.latestComparison.outcome != .exact }
  }
}
