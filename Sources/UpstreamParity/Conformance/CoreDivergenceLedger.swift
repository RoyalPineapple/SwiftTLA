import Foundation

public enum CoreRegressionOutcome: String, Codable, Sendable {
  case exact
  case difference
}

public struct CoreFiniteBounds: Equatable, Codable, Sendable {
  public let summary: String
  public let limits: [String: Int]

  public init(summary: String, limits: [String: Int]) throws {
    self.summary = summary
    self.limits = limits
    try validate()
  }

  public func validate() throws {
    guard !summary.isEmpty, !limits.isEmpty, limits.allSatisfy({ !$0.key.isEmpty && $0.value > 0 }) else {
      throw ConformanceGovernanceError.invalidField(record: "finiteBounds", field: "limits")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case summary, limits }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      summary: container.decode(String.self, forKey: .summary),
      limits: container.decode([String: Int].self, forKey: .limits))
  }
}

public struct CoreDivergenceProvenance: Equatable, Codable, Sendable {
  public let caseID: String
  public let moduleSHA256: String
  public let cfgSHA256: String
  public let argumentsSHA256: String
  public let tlcTag: String
  public let tlcCommit: String
  public let tlcJarSHA256: String
  public let javaDistribution: String
  public let javaVersion: String
  public let javaArchiveSHA256: String
  public let bridgeClass: String
  public let bridgeSourceSHA256: String
  public let bridgeBinarySHA256: String

  public init(
    caseID: String,
    moduleSHA256: String,
    cfgSHA256: String,
    argumentsSHA256: String,
    tlcTag: String,
    tlcCommit: String,
    tlcJarSHA256: String,
    javaDistribution: String,
    javaVersion: String,
    javaArchiveSHA256: String,
    bridgeClass: String,
    bridgeSourceSHA256: String,
    bridgeBinarySHA256: String
  ) throws {
    self.caseID = caseID
    self.moduleSHA256 = moduleSHA256
    self.cfgSHA256 = cfgSHA256
    self.argumentsSHA256 = argumentsSHA256
    self.tlcTag = tlcTag
    self.tlcCommit = tlcCommit
    self.tlcJarSHA256 = tlcJarSHA256
    self.javaDistribution = javaDistribution
    self.javaVersion = javaVersion
    self.javaArchiveSHA256 = javaArchiveSHA256
    self.bridgeClass = bridgeClass
    self.bridgeSourceSHA256 = bridgeSourceSHA256
    self.bridgeBinarySHA256 = bridgeBinarySHA256
    try validate()
  }

  public func validate() throws {
    guard !caseID.isEmpty, !tlcTag.isEmpty, !tlcCommit.isEmpty, !javaDistribution.isEmpty,
          !javaVersion.isEmpty, !bridgeClass.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "provenance")
    }
    for (field, digest) in [
      ("moduleSHA256", moduleSHA256), ("cfgSHA256", cfgSHA256),
      ("argumentsSHA256", argumentsSHA256), ("tlcJarSHA256", tlcJarSHA256),
      ("javaArchiveSHA256", javaArchiveSHA256),
      ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
    ] where !TLCReferencePin.isSHA256(digest) {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: field)
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, moduleSHA256, cfgSHA256, argumentsSHA256, tlcTag, tlcCommit, tlcJarSHA256
    case javaDistribution, javaVersion, javaArchiveSHA256, bridgeClass, bridgeSourceSHA256
    case bridgeBinarySHA256
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      moduleSHA256: container.decode(String.self, forKey: .moduleSHA256),
      cfgSHA256: container.decode(String.self, forKey: .cfgSHA256),
      argumentsSHA256: container.decode(String.self, forKey: .argumentsSHA256),
      tlcTag: container.decode(String.self, forKey: .tlcTag),
      tlcCommit: container.decode(String.self, forKey: .tlcCommit),
      tlcJarSHA256: container.decode(String.self, forKey: .tlcJarSHA256),
      javaDistribution: container.decode(String.self, forKey: .javaDistribution),
      javaVersion: container.decode(String.self, forKey: .javaVersion),
      javaArchiveSHA256: container.decode(String.self, forKey: .javaArchiveSHA256),
      bridgeClass: container.decode(String.self, forKey: .bridgeClass),
      bridgeSourceSHA256: container.decode(String.self, forKey: .bridgeSourceSHA256),
      bridgeBinarySHA256: container.decode(String.self, forKey: .bridgeBinarySHA256))
  }
}

public struct CoreEvidenceReference: Equatable, Codable, Sendable {
  public let path: String
  public let sha256: String

  public init(path: String, sha256: String) throws {
    self.path = path
    self.sha256 = sha256
    try validate()
  }

  public func validate() throws {
    guard !path.isEmpty, !path.hasPrefix("/"), TLCReferencePin.isSHA256(sha256) else {
      throw ConformanceGovernanceError.invalidField(record: "evidence", field: "path or sha256")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case path, sha256 }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      path: container.decode(String.self, forKey: .path),
      sha256: container.decode(String.self, forKey: .sha256))
  }
}

public struct CoreDivergenceComparison: Equatable, Codable, Sendable {
  public let evidence: CoreEvidenceReference
  public let outcome: CoreRegressionOutcome
  public let normalizedDifferenceFingerprint: String?

  public init(
    evidence: CoreEvidenceReference,
    outcome: CoreRegressionOutcome,
    normalizedDifferenceFingerprint: String?
  ) throws {
    self.evidence = evidence
    self.outcome = outcome
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
    try validate()
  }

  public func validate() throws {
    try evidence.validate()
    guard outcome == .exact ? normalizedDifferenceFingerprint == nil : normalizedDifferenceFingerprint?.isEmpty == false else {
      throw ConformanceGovernanceError.invalidField(record: "comparison", field: "normalizedDifferenceFingerprint")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case evidence, outcome, normalizedDifferenceFingerprint
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      evidence: container.decode(CoreEvidenceReference.self, forKey: .evidence),
      outcome: container.decode(CoreRegressionOutcome.self, forKey: .outcome),
      normalizedDifferenceFingerprint: try container.decodeIfPresent(
        String.self, forKey: .normalizedDifferenceFingerprint))
  }
}

public struct CoreDivergenceRecord: Equatable, Codable, Sendable {
  public let id: String
  public let provenance: CoreDivergenceProvenance
  public let semanticCitations: [String]
  public let reproducer: CoreFiniteBounds
  public let originalEvidence: CoreEvidenceReference
  public let permanentRegressionCaseID: String
  public let classification: ConformanceDivergenceClassification
  public let disposition: ConformanceDivergenceDisposition
  public let normalizedDifferenceFingerprint: String
  public let latestComparison: CoreDivergenceComparison

  public init(
    id: String,
    provenance: CoreDivergenceProvenance,
    semanticCitations: [String],
    reproducer: CoreFiniteBounds,
    originalEvidence: CoreEvidenceReference,
    permanentRegressionCaseID: String,
    classification: ConformanceDivergenceClassification,
    disposition: ConformanceDivergenceDisposition,
    normalizedDifferenceFingerprint: String,
    latestComparison: CoreDivergenceComparison
  ) throws {
    self.id = id
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
    guard !id.isEmpty, !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }),
          !permanentRegressionCaseID.isEmpty, !normalizedDifferenceFingerprint.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "required evidence")
    }
    guard disposition != .resolved || latestComparison.outcome == .exact else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "latestComparison")
    }
    guard latestComparison.outcome == .exact || latestComparison.normalizedDifferenceFingerprint == normalizedDifferenceFingerprint else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "latestComparison")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, provenance, semanticCitations, reproducer, originalEvidence, permanentRegressionCaseID
    case classification, disposition, normalizedDifferenceFingerprint, latestComparison
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      provenance: container.decode(CoreDivergenceProvenance.self, forKey: .provenance),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations),
      reproducer: container.decode(CoreFiniteBounds.self, forKey: .reproducer),
      originalEvidence: container.decode(CoreEvidenceReference.self, forKey: .originalEvidence),
      permanentRegressionCaseID: container.decode(String.self, forKey: .permanentRegressionCaseID),
      classification: container.decode(ConformanceDivergenceClassification.self, forKey: .classification),
      disposition: container.decode(ConformanceDivergenceDisposition.self, forKey: .disposition),
      normalizedDifferenceFingerprint: container.decode(String.self, forKey: .normalizedDifferenceFingerprint),
      latestComparison: container.decode(CoreDivergenceComparison.self, forKey: .latestComparison))
  }
}

public struct CoreDivergenceLedger: Equatable, Codable, Sendable {
  public static let schema = "CoreDivergenceLedger"

  public let schema: String
  public let records: [CoreDivergenceRecord]

  public init(records: [CoreDivergenceRecord]) throws {
    try self.init(schema: Self.schema, records: records)
  }

  public init(schema: String, records: [CoreDivergenceRecord]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var identifiers = Set<String>()
    for record in records {
      try record.validate()
      guard identifiers.insert(record.id).inserted else {
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
      records: container.decode([CoreDivergenceRecord].self, forKey: .records))
  }

  public func validate(caseIDs: Set<String>) throws {
    for record in records {
      guard caseIDs.contains(record.provenance.caseID) else {
        throw ConformanceGovernanceError.unknownCaseID(record.provenance.caseID)
      }
      guard caseIDs.contains(record.permanentRegressionCaseID) else {
        throw ConformanceGovernanceError.unknownCaseID(record.permanentRegressionCaseID)
      }
    }
  }

  /// Produces the stable digest for the canonical nonconformant comparison
  /// projection: `{ "conformant": false, "differences": [...] }`.
  /// Correlation IDs are excluded because each reproduction has a new run ID;
  /// the complete artifact remains bound by its separate evidence digest.
  public static func normalizedDifferenceFingerprint(from data: Data) throws -> String {
    guard let comparison = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let conformant = comparison["conformant"] as? Bool, !conformant,
          let differences = comparison["differences"] as? [Any], !differences.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: "comparison", field: "differences")
    }
    let normalized: [String: Any] = [
      "conformant": false,
      "differences": differences
    ]
    return SHA256.hex(try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]))
  }
}
