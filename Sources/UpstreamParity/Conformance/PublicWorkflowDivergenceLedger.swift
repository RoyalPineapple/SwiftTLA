import Foundation

public struct PublicWorkflowDivergenceComparison: Equatable, Codable, Sendable {
  public let evidence: CoreEvidenceReference
  public let outcome: PublicWorkflowExpectedOutcome
  public let normalizedDifferenceFingerprint: String?

  public init(evidence: CoreEvidenceReference, outcome: PublicWorkflowExpectedOutcome, normalizedDifferenceFingerprint: String?) throws {
    self.evidence = evidence
    self.outcome = outcome
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    try validate()
  }

  public func validate() throws {
    try evidence.validate()
    guard outcome == .difference ? normalizedDifferenceFingerprint?.isEmpty == false : normalizedDifferenceFingerprint == nil else {
      throw ConformanceGovernanceError.invalidField(record: "comparison", field: "normalizedDifferenceFingerprint")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case evidence, outcome, normalizedDifferenceFingerprint }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(evidence: try container.decode(CoreEvidenceReference.self, forKey: .evidence), outcome: try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .outcome), normalizedDifferenceFingerprint: try container.decodeIfPresent(String.self, forKey: .normalizedDifferenceFingerprint))
  }
}

public struct PublicWorkflowDivergenceRecord: Equatable, Codable, Sendable {
  public let id: String
  public let caseID: String
  public let semanticCitations: [String]
  public let reproducer: CoreFiniteBounds
  public let originalEvidence: CoreEvidenceReference
  public let permanentRegressionCaseID: String
  public let classification: ConformanceDivergenceClassification
  public let disposition: ConformanceDivergenceDisposition
  public let normalizedDifferenceFingerprint: String
  public let latestComparison: PublicWorkflowDivergenceComparison

  public init(id: String, caseID: String, semanticCitations: [String], reproducer: CoreFiniteBounds, originalEvidence: CoreEvidenceReference, permanentRegressionCaseID: String, classification: ConformanceDivergenceClassification, disposition: ConformanceDivergenceDisposition, normalizedDifferenceFingerprint: String, latestComparison: PublicWorkflowDivergenceComparison) throws {
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
      throw ConformanceGovernanceError.invalidField(record: id, field: "required evidence")
    }
    guard disposition != .resolved || latestComparison.outcome == .exact else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "latest comparison")
    }
    guard latestComparison.outcome != .difference || latestComparison.normalizedDifferenceFingerprint == normalizedDifferenceFingerprint else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "fingerprint drift")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case id, caseID, semanticCitations, reproducer, originalEvidence, permanentRegressionCaseID, classification, disposition, normalizedDifferenceFingerprint, latestComparison }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(id: try container.decode(String.self, forKey: .id), caseID: try container.decode(String.self, forKey: .caseID), semanticCitations: try container.decode([String].self, forKey: .semanticCitations), reproducer: try container.decode(CoreFiniteBounds.self, forKey: .reproducer), originalEvidence: try container.decode(CoreEvidenceReference.self, forKey: .originalEvidence), permanentRegressionCaseID: try container.decode(String.self, forKey: .permanentRegressionCaseID), classification: try container.decode(ConformanceDivergenceClassification.self, forKey: .classification), disposition: try container.decode(ConformanceDivergenceDisposition.self, forKey: .disposition), normalizedDifferenceFingerprint: try container.decode(String.self, forKey: .normalizedDifferenceFingerprint), latestComparison: try container.decode(PublicWorkflowDivergenceComparison.self, forKey: .latestComparison))
  }
}

public struct PublicWorkflowDivergenceLedger: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowDivergenceLedger"
  public let schema: String
  public let records: [PublicWorkflowDivergenceRecord]

  public init(records: [PublicWorkflowDivergenceRecord]) throws { try self.init(schema: Self.schema, records: records) }

  public init(schema: String, records: [PublicWorkflowDivergenceRecord]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for record in records {
      try record.validate()
      guard ids.insert(record.id).inserted else { throw ConformanceGovernanceError.duplicateID(kind: "divergence", id: record.id) }
    }
    self.schema = schema
    self.records = records
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, records }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), records: try container.decode([PublicWorkflowDivergenceRecord].self, forKey: .records))
  }

  public func validate(caseIDs: Set<String>) throws {
    for record in records {
      guard caseIDs.contains(record.caseID), caseIDs.contains(record.permanentRegressionCaseID) else {
        throw ConformanceGovernanceError.unknownCaseID(caseIDs.contains(record.caseID) ? record.permanentRegressionCaseID : record.caseID)
      }
    }
  }

  public var unexplainedRecords: [PublicWorkflowDivergenceRecord] {
    records.filter { $0.disposition != .resolved || $0.latestComparison.outcome != .exact }
  }
}
