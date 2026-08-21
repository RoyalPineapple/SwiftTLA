import Foundation

public struct TemporalSymmetryDivergenceComparison: Equatable, Codable, Sendable {
  public let evidence: CoreEvidenceReference
  public let outcome: TemporalSymmetryExpectedOutcome
  public let normalizedDifferenceFingerprint: String?

  public init(evidence: CoreEvidenceReference, outcome: TemporalSymmetryExpectedOutcome, normalizedDifferenceFingerprint: String?) throws {
    self.evidence = evidence
    self.outcome = outcome
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    try validate()
  }

  public func validate() throws {
    try evidence.validate()
    let needsFingerprint = outcome == .difference
    guard needsFingerprint == (normalizedDifferenceFingerprint?.isEmpty == false) else {
      throw ConformanceGovernanceError.invalidField(record: "comparison", field: "normalizedDifferenceFingerprint")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case evidence, outcome, normalizedDifferenceFingerprint }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      evidence: container.decode(CoreEvidenceReference.self, forKey: .evidence),
      outcome: container.decode(TemporalSymmetryExpectedOutcome.self, forKey: .outcome),
      normalizedDifferenceFingerprint: try container.decodeIfPresent(String.self, forKey: .normalizedDifferenceFingerprint))
  }
}

public struct TemporalSymmetryDivergenceRecord: Equatable, Codable, Sendable {
  public let id: String
  public let kind: TemporalSymmetryCaseKind
  public let provenance: CoreDivergenceProvenance
  public let semanticCitations: [String]
  public let reproducer: CoreFiniteBounds
  public let originalEvidence: CoreEvidenceReference
  public let permanentRegressionCaseID: String
  public let classification: ConformanceDivergenceClassification
  public let disposition: ConformanceDivergenceDisposition
  public let normalizedDifferenceFingerprint: String
  public let latestComparison: TemporalSymmetryDivergenceComparison

  public init(
    id: String,
    kind: TemporalSymmetryCaseKind,
    provenance: CoreDivergenceProvenance,
    semanticCitations: [String],
    reproducer: CoreFiniteBounds,
    originalEvidence: CoreEvidenceReference,
    permanentRegressionCaseID: String,
    classification: ConformanceDivergenceClassification,
    disposition: ConformanceDivergenceDisposition,
    normalizedDifferenceFingerprint: String,
    latestComparison: TemporalSymmetryDivergenceComparison
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
      throw ConformanceGovernanceError.invalidField(record: id, field: "required evidence")
    }
    guard disposition != .resolved || latestComparison.outcome == .exact else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "latestComparison")
    }
    guard latestComparison.outcome != .difference || latestComparison.normalizedDifferenceFingerprint == normalizedDifferenceFingerprint else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "fingerprint drift")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, provenance, semanticCitations, reproducer, originalEvidence, permanentRegressionCaseID
    case classification, disposition, normalizedDifferenceFingerprint, latestComparison
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKind.self, forKey: .kind),
      provenance: container.decode(CoreDivergenceProvenance.self, forKey: .provenance),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations),
      reproducer: container.decode(CoreFiniteBounds.self, forKey: .reproducer),
      originalEvidence: container.decode(CoreEvidenceReference.self, forKey: .originalEvidence),
      permanentRegressionCaseID: container.decode(String.self, forKey: .permanentRegressionCaseID),
      classification: container.decode(ConformanceDivergenceClassification.self, forKey: .classification),
      disposition: container.decode(ConformanceDivergenceDisposition.self, forKey: .disposition),
      normalizedDifferenceFingerprint: container.decode(String.self, forKey: .normalizedDifferenceFingerprint),
      latestComparison: container.decode(TemporalSymmetryDivergenceComparison.self, forKey: .latestComparison))
  }
}

public struct TemporalSymmetryDivergenceLedger: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryDivergenceLedger"
  public let schema: String
  public let records: [TemporalSymmetryDivergenceRecord]

  public init(records: [TemporalSymmetryDivergenceRecord]) throws {
    try self.init(schema: Self.schema, records: records)
  }

  public init(schema: String, records: [TemporalSymmetryDivergenceRecord]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for record in records {
      try record.validate()
      guard ids.insert(record.id).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "divergence", id: record.id)
      }
    }
    self.schema = schema
    self.records = records
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, records }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      records: container.decode([TemporalSymmetryDivergenceRecord].self, forKey: .records))
  }

  public func validate(cases: TemporalSymmetryCases) throws {
    let casesByID = Dictionary(uniqueKeysWithValues: cases.cases.map { ($0.id, $0) })
    for record in records {
      guard let provenanceCase = casesByID[record.provenance.caseID] else {
        throw ConformanceGovernanceError.unknownCaseID(record.provenance.caseID)
      }
      guard let permanentRegression = casesByID[record.permanentRegressionCaseID] else {
        throw ConformanceGovernanceError.unknownCaseID(record.permanentRegressionCaseID)
      }
      guard provenanceCase.kind == record.kind, permanentRegression.kind == record.kind,
            permanentRegression.expectedOutcome == .difference,
            record.reproducer.isWithin(provenanceCase.finiteBounds) else {
        throw ConformanceGovernanceError.inconsistentReference(record: record.id, field: "kind, provenance, regression, or bounds")
      }
    }
  }
}

private extension CoreFiniteBounds {
  func isWithin(_ enclosing: CoreFiniteBounds) -> Bool {
    limits.allSatisfy { key, value in
      guard let enclosingValue = enclosing.limits[key] else { return false }
      return value <= enclosingValue
    }
  }
}
