import Foundation

public enum TemporalSymmetryDivergenceClassificationV1: String, CaseIterable, Codable, Sendable {
  case swiftTLADefect
  case harnessOrConfigurationDefect
  case unsupportedConstruct
  case publishedSemanticsAmbiguity
  case suspectedTLCDefect
}

public enum TemporalSymmetryDivergenceDispositionV1: String, CaseIterable, Codable, Sendable {
  case open
  case resolved
  case unsupported
  case awaitingSemanticsReview
  case suspectedReferenceDefect
}

public struct TemporalSymmetryDivergenceComparisonV1: Equatable, Codable, Sendable {
  public let evidence: CoreEvidenceReferenceV1
  public let outcome: TemporalSymmetryExpectedOutcomeV1
  public let normalizedDifferenceFingerprint: String?

  public init(evidence: CoreEvidenceReferenceV1, outcome: TemporalSymmetryExpectedOutcomeV1, normalizedDifferenceFingerprint: String?) throws {
    self.evidence = evidence
    self.outcome = outcome
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    try validate()
  }

  public func validate() throws {
    try evidence.validate()
    let needsFingerprint = outcome == .difference
    guard needsFingerprint == (normalizedDifferenceFingerprint?.isEmpty == false) else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "comparison", field: "normalizedDifferenceFingerprint")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case evidence, outcome, normalizedDifferenceFingerprint }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      evidence: container.decode(CoreEvidenceReferenceV1.self, forKey: .evidence),
      outcome: container.decode(TemporalSymmetryExpectedOutcomeV1.self, forKey: .outcome),
      normalizedDifferenceFingerprint: try container.decodeIfPresent(String.self, forKey: .normalizedDifferenceFingerprint))
  }
}

public struct TemporalSymmetryDivergenceRecordV1: Equatable, Codable, Sendable {
  public let id: String
  public let kind: TemporalSymmetryCaseKindV1
  public let provenance: CoreDivergenceProvenanceV1
  public let semanticCitations: [String]
  public let reproducer: CoreFiniteBoundsV1
  public let originalEvidence: CoreEvidenceReferenceV1
  public let permanentRegressionCaseID: String
  public let classification: TemporalSymmetryDivergenceClassificationV1
  public let disposition: TemporalSymmetryDivergenceDispositionV1
  public let normalizedDifferenceFingerprint: String
  public let latestComparison: TemporalSymmetryDivergenceComparisonV1

  public init(
    id: String,
    kind: TemporalSymmetryCaseKindV1,
    provenance: CoreDivergenceProvenanceV1,
    semanticCitations: [String],
    reproducer: CoreFiniteBoundsV1,
    originalEvidence: CoreEvidenceReferenceV1,
    permanentRegressionCaseID: String,
    classification: TemporalSymmetryDivergenceClassificationV1,
    disposition: TemporalSymmetryDivergenceDispositionV1,
    normalizedDifferenceFingerprint: String,
    latestComparison: TemporalSymmetryDivergenceComparisonV1
  ) throws {
    self.id = id
    self.kind = kind
    self.provenance = provenance
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
    try provenance.validate()
    try reproducer.validate()
    try originalEvidence.validate()
    try latestComparison.validate()
    guard !id.isEmpty, !permanentRegressionCaseID.isEmpty, !normalizedDifferenceFingerprint.isEmpty,
          !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: id, field: "required evidence")
    }
    guard disposition != .resolved || latestComparison.outcome == .exact else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: id, field: "latestComparison")
    }
    guard latestComparison.outcome != .difference || latestComparison.normalizedDifferenceFingerprint == normalizedDifferenceFingerprint else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: id, field: "fingerprint drift")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, provenance, semanticCitations, reproducer, originalEvidence, permanentRegressionCaseID
    case classification, disposition, normalizedDifferenceFingerprint, latestComparison
  }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKindV1.self, forKey: .kind),
      provenance: container.decode(CoreDivergenceProvenanceV1.self, forKey: .provenance),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations),
      reproducer: container.decode(CoreFiniteBoundsV1.self, forKey: .reproducer),
      originalEvidence: container.decode(CoreEvidenceReferenceV1.self, forKey: .originalEvidence),
      permanentRegressionCaseID: container.decode(String.self, forKey: .permanentRegressionCaseID),
      classification: container.decode(TemporalSymmetryDivergenceClassificationV1.self, forKey: .classification),
      disposition: container.decode(TemporalSymmetryDivergenceDispositionV1.self, forKey: .disposition),
      normalizedDifferenceFingerprint: container.decode(String.self, forKey: .normalizedDifferenceFingerprint),
      latestComparison: container.decode(TemporalSymmetryDivergenceComparisonV1.self, forKey: .latestComparison))
  }
}

public struct TemporalSymmetryDivergenceLedgerV1: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryDivergenceLedgerV1"
  public let schema: String
  public let records: [TemporalSymmetryDivergenceRecordV1]

  public init(records: [TemporalSymmetryDivergenceRecordV1]) throws {
    try self.init(schema: Self.schema, records: records)
  }

  public init(schema: String, records: [TemporalSymmetryDivergenceRecordV1]) throws {
    guard schema == Self.schema else { throw TemporalSymmetryGovernanceErrorV1.invalidSchema(schema) }
    var ids = Set<String>()
    for record in records {
      try record.validate()
      guard ids.insert(record.id).inserted else {
        throw TemporalSymmetryGovernanceErrorV1.duplicateID(kind: "divergence", id: record.id)
      }
    }
    self.schema = schema
    self.records = records
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, records }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      records: container.decode([TemporalSymmetryDivergenceRecordV1].self, forKey: .records))
  }

  public func validate(cases: TemporalSymmetryCasesV1) throws {
    let casesByID = Dictionary(uniqueKeysWithValues: cases.cases.map { ($0.id, $0) })
    for record in records {
      guard let provenanceCase = casesByID[record.provenance.caseID] else {
        throw TemporalSymmetryGovernanceErrorV1.unknownCaseID(record.provenance.caseID)
      }
      guard let permanentRegression = casesByID[record.permanentRegressionCaseID] else {
        throw TemporalSymmetryGovernanceErrorV1.unknownCaseID(record.permanentRegressionCaseID)
      }
      guard provenanceCase.kind == record.kind, permanentRegression.kind == record.kind,
            permanentRegression.expectedOutcome == .difference,
            record.reproducer.isWithin(provenanceCase.finiteBounds) else {
        throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: record.id, field: "kind, provenance, regression, or bounds")
      }
    }
  }
}

private extension CoreFiniteBoundsV1 {
  func isWithin(_ enclosing: CoreFiniteBoundsV1) -> Bool {
    limits.allSatisfy { key, value in
      guard let enclosingValue = enclosing.limits[key] else { return false }
      return value <= enclosingValue
    }
  }
}
