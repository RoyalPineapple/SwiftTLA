import Foundation

public enum CoreConformanceCaseRoleV1: String, Codable, Sendable {
  case requiredComparison
  case permanentRegression
}

public enum CoreSupportCategoryV1: String, Codable, Sendable {
  case stateSpace
  case transitionRelation
  case invariantSafety
  case temporal
  case symmetry
  case parser
  case annotation
  case generatedBehavior
  case platform

  public var isSupportedByV1: Bool {
    switch self {
    case .stateSpace, .transitionRelation, .invariantSafety: true
    case .temporal, .symmetry, .parser, .annotation, .generatedBehavior, .platform: false
    }
  }
}

public enum CoreSupportRequestV1: String, Codable, Sendable {
  case requested
  case unsupported
  case blocked
}

public enum CoreSupportDecisionV1: String, Codable, Sendable {
  case admitted
  case blocked
  case unsupported
}

public enum CoreSupportAdmissionExitClassV1: String, Codable, Sendable {
  case success
  case blocked
}

public enum CoreSupportReasonCodeV1: String, CaseIterable, Codable, Sendable {
  case invalidRegister
  case unsupportedCategory
  case explicitlyUnsupported
  case declaredBlocked
  case missingPrerequisite
  case missingEvidence
  case partialEvidence
  case foreignRun
  case manifestDigestMismatch
  case toolchainDigestMismatch
  case executionFailed
  case nonExactComparison
  case unresolvedDivergence
  case unexplainedDivergence
}

public struct CoreConformanceCaseGovernanceV1: Equatable, Codable, Sendable {
  public let role: CoreConformanceCaseRoleV1
  public let finiteBounds: CoreFiniteBoundsV1
  public let semanticCitations: [String]
  public let expectedRegressionOutcome: CoreRegressionOutcomeV1

  public init(
    role: CoreConformanceCaseRoleV1,
    finiteBounds: CoreFiniteBoundsV1,
    semanticCitations: [String],
    expectedRegressionOutcome: CoreRegressionOutcomeV1
  ) throws {
    self.role = role
    self.finiteBounds = finiteBounds
    self.semanticCitations = semanticCitations
    self.expectedRegressionOutcome = expectedRegressionOutcome
    try validate()
  }

  public func validate() throws {
    try finiteBounds.validate()
    guard !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
      throw CoreGovernanceErrorV1.invalidField(record: "case", field: "semanticCitations")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case role, finiteBounds, semanticCitations, expectedRegressionOutcome
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      role: container.decode(CoreConformanceCaseRoleV1.self, forKey: .role),
      finiteBounds: container.decode(CoreFiniteBoundsV1.self, forKey: .finiteBounds),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations),
      expectedRegressionOutcome: container.decode(CoreRegressionOutcomeV1.self, forKey: .expectedRegressionOutcome))
  }
}

public struct CoreSupportSurfaceEntryV1: Equatable, Codable, Sendable {
  public let id: String
  public let behavior: String
  public let category: CoreSupportCategoryV1
  public let finiteBounds: CoreFiniteBoundsV1
  public let relation: CanonicalSchemaV1
  public let mandatoryCaseIDs: [String]
  public let requestedStatus: CoreSupportRequestV1
  public let linkedDivergenceIDs: [String]
  public let reason: String?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case behavior
    case category
    case finiteBounds
    case relation
    case mandatoryCaseIDs
    case requestedStatus
    case linkedDivergenceIDs
    case reason
  }

  public init(
    id: String,
    behavior: String,
    category: CoreSupportCategoryV1,
    finiteBounds: CoreFiniteBoundsV1,
    relation: CanonicalSchemaV1 = .exactFiniteTLCGraphV1,
    mandatoryCaseIDs: [String],
    requestedStatus: CoreSupportRequestV1,
    linkedDivergenceIDs: [String] = [],
    reason: String? = nil
  ) throws {
    self.id = id
    self.behavior = behavior
    self.category = category
    self.finiteBounds = finiteBounds
    self.relation = relation
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.requestedStatus = requestedStatus
    self.linkedDivergenceIDs = linkedDivergenceIDs
    self.reason = reason
    try validate()
  }

  public func validate() throws {
    try finiteBounds.validate()
    guard !id.isEmpty, !behavior.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count,
          Set(linkedDivergenceIDs).count == linkedDivergenceIDs.count else {
      throw CoreGovernanceErrorV1.invalidField(record: id, field: "support entry")
    }
    guard category.isSupportedByV1 else {
      throw CoreGovernanceErrorV1.unsupportedCategory(category.rawValue)
    }
    guard relation == .exactFiniteTLCGraphV1 else {
      throw CoreGovernanceErrorV1.invalidField(record: id, field: "relation")
    }
    if requestedStatus != .requested, reason?.isEmpty != false {
      throw CoreGovernanceErrorV1.invalidField(record: id, field: "reason")
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    let relation = try CanonicalSchemaV1(validating: container.decode(String.self, forKey: .relation))
    try self.init(
      id: container.decode(String.self, forKey: .id),
      behavior: container.decode(String.self, forKey: .behavior),
      category: container.decode(CoreSupportCategoryV1.self, forKey: .category),
      finiteBounds: container.decode(CoreFiniteBoundsV1.self, forKey: .finiteBounds),
      relation: relation,
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      requestedStatus: container.decode(CoreSupportRequestV1.self, forKey: .requestedStatus),
      linkedDivergenceIDs: try container.decodeIfPresent([String].self, forKey: .linkedDivergenceIDs) ?? [],
      reason: try container.decodeIfPresent(String.self, forKey: .reason))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(behavior, forKey: .behavior)
    try container.encode(category, forKey: .category)
    try container.encode(finiteBounds, forKey: .finiteBounds)
    try container.encode(relation.rawValue, forKey: .relation)
    try container.encode(mandatoryCaseIDs, forKey: .mandatoryCaseIDs)
    try container.encode(requestedStatus, forKey: .requestedStatus)
    try container.encode(linkedDivergenceIDs, forKey: .linkedDivergenceIDs)
    try container.encodeIfPresent(reason, forKey: .reason)
  }
}

public struct CoreSupportSurfaceV1: Equatable, Codable, Sendable {
  public static let schema = "CoreSupportSurfaceV1"

  public let schema: String
  public let entries: [CoreSupportSurfaceEntryV1]

  public init(entries: [CoreSupportSurfaceEntryV1]) throws {
    try self.init(schema: Self.schema, entries: entries)
  }

  public init(schema: String, entries: [CoreSupportSurfaceEntryV1]) throws {
    guard schema == Self.schema else { throw CoreGovernanceErrorV1.invalidSchema(schema) }
    var identifiers = Set<String>()
    for entry in entries {
      try entry.validate()
      guard identifiers.insert(entry.id).inserted else {
        throw CoreGovernanceErrorV1.duplicateID(kind: "support", id: entry.id)
      }
    }
    self.schema = schema
    self.entries = entries
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, entries }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      entries: container.decode([CoreSupportSurfaceEntryV1].self, forKey: .entries))
  }

  public func validate(caseIDs: Set<String>, ledger: CoreDivergenceLedgerV1) throws {
    try ledger.validate(caseIDs: caseIDs)
    let divergenceIDs = Set(ledger.records.map(\.id))
    for entry in entries {
      for caseID in entry.mandatoryCaseIDs where !caseIDs.contains(caseID) {
        throw CoreGovernanceErrorV1.unknownCaseID(caseID)
      }
      for divergenceID in entry.linkedDivergenceIDs where !divergenceIDs.contains(divergenceID) {
        throw CoreGovernanceErrorV1.unknownDivergenceID(divergenceID)
      }
    }
    let linkedDivergenceIDs = Set(entries.flatMap(\.linkedDivergenceIDs))
    guard divergenceIDs.isSubset(of: linkedDivergenceIDs) else {
      throw CoreGovernanceErrorV1.invalidField(record: "support surface", field: "unlinked divergence")
    }
  }
}

public struct CoreSupportAdmissionEntryV1: Equatable, Codable, Sendable {
  public let supportID: String
  public let decision: CoreSupportDecisionV1
  public let reasonCodes: [CoreSupportReasonCodeV1]
  public let mandatoryCaseIDs: [String]
  public let divergenceIDs: [String]
  public let evidence: [CoreEvidenceReferenceV1]
  public let caseRunCorrelations: [CoreSupportCaseRunCorrelationV1]

  public init(
    supportID: String,
    decision: CoreSupportDecisionV1,
    reasonCodes: [CoreSupportReasonCodeV1],
    mandatoryCaseIDs: [String],
    divergenceIDs: [String],
    evidence: [CoreEvidenceReferenceV1] = [],
    caseRunCorrelations: [CoreSupportCaseRunCorrelationV1] = []
  ) throws {
    self.supportID = supportID
    self.decision = decision
    self.reasonCodes = reasonCodes
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.divergenceIDs = divergenceIDs
    self.evidence = evidence
    self.caseRunCorrelations = caseRunCorrelations
    try validate()
  }

  public func validate() throws {
    guard !supportID.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(reasonCodes).count == reasonCodes.count,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count,
          Set(divergenceIDs).count == divergenceIDs.count else {
      throw CoreGovernanceErrorV1.invalidField(record: supportID, field: "admission entry")
    }
    if decision == .admitted, !reasonCodes.isEmpty {
      throw CoreGovernanceErrorV1.invalidField(record: supportID, field: "reasonCodes")
    }
    if decision != .admitted, reasonCodes.isEmpty {
      throw CoreGovernanceErrorV1.invalidField(record: supportID, field: "reasonCodes")
    }
    try evidence.forEach { try $0.validate() }
    try caseRunCorrelations.forEach { try $0.validate() }
    let correlatedCases = Set(caseRunCorrelations.map(\.caseID))
    guard correlatedCases.count == caseRunCorrelations.count else {
      throw CoreGovernanceErrorV1.invalidField(record: supportID, field: "caseRunCorrelations")
    }
    if decision == .admitted {
      guard !evidence.isEmpty, correlatedCases == Set(mandatoryCaseIDs) else {
        throw CoreGovernanceErrorV1.invalidField(record: supportID, field: "evidence or caseRunCorrelations")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case supportID, decision, reasonCodes, mandatoryCaseIDs, divergenceIDs, evidence, caseRunCorrelations
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      supportID: container.decode(String.self, forKey: .supportID),
      decision: container.decode(CoreSupportDecisionV1.self, forKey: .decision),
      reasonCodes: container.decode([CoreSupportReasonCodeV1].self, forKey: .reasonCodes),
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      divergenceIDs: container.decode([String].self, forKey: .divergenceIDs),
      evidence: container.decode([CoreEvidenceReferenceV1].self, forKey: .evidence),
      caseRunCorrelations: container.decode(
        [CoreSupportCaseRunCorrelationV1].self, forKey: .caseRunCorrelations))
  }
}

public struct CoreSupportCaseRunCorrelationV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let swiftRunID: UUID
  public let tlcRunID: UUID
  public let comparisonRunID: UUID

  public init(
    caseID: String,
    gateRunID: UUID,
    swiftRunID: UUID,
    tlcRunID: UUID,
    comparisonRunID: UUID
  ) throws {
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.swiftRunID = swiftRunID
    self.tlcRunID = tlcRunID
    self.comparisonRunID = comparisonRunID
    try validate()
  }

  public func validate() throws {
    guard !caseID.isEmpty else {
      throw CoreGovernanceErrorV1.invalidField(record: "caseRunCorrelation", field: "caseID")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, gateRunID, swiftRunID, tlcRunID, comparisonRunID
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      swiftRunID: container.decode(UUID.self, forKey: .swiftRunID),
      tlcRunID: container.decode(UUID.self, forKey: .tlcRunID),
      comparisonRunID: container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

public struct CoreSupportAdmissionCountsV1: Equatable, Codable, Sendable {
  public let admitted: Int
  public let blocked: Int
  public let unsupported: Int
  public let missing: Int
  public let stale: Int
  public let failing: Int
  public let unexplained: Int

  public init(entries: [CoreSupportAdmissionEntryV1]) {
    admitted = entries.count { $0.decision == .admitted }
    blocked = entries.count { $0.decision == .blocked }
    unsupported = entries.count { $0.decision == .unsupported }
    missing = entries.count { entry in
      entry.reasonCodes.contains(.missingPrerequisite) || entry.reasonCodes.contains(.missingEvidence)
    }
    stale = entries.count { entry in
      entry.reasonCodes.contains(.partialEvidence) || entry.reasonCodes.contains(.foreignRun)
        || entry.reasonCodes.contains(.manifestDigestMismatch)
        || entry.reasonCodes.contains(.toolchainDigestMismatch)
    }
    failing = entries.count { $0.reasonCodes.contains(.executionFailed) }
    unexplained = entries.reduce(into: 0) { count, entry in
      if entry.reasonCodes.contains(.unexplainedDivergence) { count += 1 }
    }
  }

  private init(
    admitted: Int,
    blocked: Int,
    unsupported: Int,
    missing: Int,
    stale: Int,
    failing: Int,
    unexplained: Int
  ) throws {
    guard [admitted, blocked, unsupported, missing, stale, failing, unexplained].allSatisfy({ $0 >= 0 }) else {
      throw CoreGovernanceErrorV1.invalidField(record: "admission", field: "counts")
    }
    self.admitted = admitted
    self.blocked = blocked
    self.unsupported = unsupported
    self.missing = missing
    self.stale = stale
    self.failing = failing
    self.unexplained = unexplained
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case admitted, blocked, unsupported, missing, stale, failing, unexplained
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      admitted: container.decode(Int.self, forKey: .admitted),
      blocked: container.decode(Int.self, forKey: .blocked),
      unsupported: container.decode(Int.self, forKey: .unsupported),
      missing: container.decode(Int.self, forKey: .missing),
      stale: container.decode(Int.self, forKey: .stale),
      failing: container.decode(Int.self, forKey: .failing),
      unexplained: container.decode(Int.self, forKey: .unexplained))
  }
}

public struct CoreSupportAdmissionV1: Equatable, Codable, Sendable {
  public static let schema = "CoreSupportAdmissionV1"
  public static let authorityBoundary =
    "Published TLA+ semantics are authoritative; TLC is a pinned executable reference; "
    + "TLC source and tests are diagnostic evidence; no hidden checker or oracle is claimed."

  public let schema: String
  public let gateRunID: UUID
  public let authority: String
  public let entries: [CoreSupportAdmissionEntryV1]
  public let counts: CoreSupportAdmissionCountsV1
  public let finalExitClass: CoreSupportAdmissionExitClassV1

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, gateRunID, authority, entries, counts, finalExitClass
  }

  public init(gateRunID: UUID, entries: [CoreSupportAdmissionEntryV1]) throws {
    try self.init(schema: Self.schema, gateRunID: gateRunID, authority: Self.authorityBoundary, entries: entries)
  }

  public init(schema: String, gateRunID: UUID, authority: String, entries: [CoreSupportAdmissionEntryV1]) throws {
    guard schema == Self.schema, authority == Self.authorityBoundary else {
      throw CoreGovernanceErrorV1.invalidSchema(schema)
    }
    var identifiers = Set<String>()
    for entry in entries {
      try entry.validate()
      guard entry.caseRunCorrelations.allSatisfy({ $0.gateRunID == gateRunID }) else {
        throw CoreGovernanceErrorV1.invalidField(record: entry.supportID, field: "caseRunCorrelations")
      }
      guard identifiers.insert(entry.supportID).inserted else {
        throw CoreGovernanceErrorV1.duplicateID(kind: "admission", id: entry.supportID)
      }
    }
    self.schema = schema
    self.gateRunID = gateRunID
    self.authority = authority
    self.entries = entries
    self.counts = CoreSupportAdmissionCountsV1(entries: entries)
    self.finalExitClass = !entries.contains { $0.decision == .blocked } && counts.unexplained == 0
      ? .success
      : .blocked
  }

  public init(from decoder: Decoder) throws {
    let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    let entries = try container.decode([CoreSupportAdmissionEntryV1].self, forKey: .entries)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      authority: container.decode(String.self, forKey: .authority),
      entries: entries)
    let reportedCounts = try container.decode(CoreSupportAdmissionCountsV1.self, forKey: .counts)
    guard reportedCounts == counts else {
      throw CoreGovernanceErrorV1.invalidField(record: "admission", field: "counts")
    }
    let reportedExitClass = try container.decode(CoreSupportAdmissionExitClassV1.self, forKey: .finalExitClass)
    guard reportedExitClass == finalExitClass else {
      throw CoreGovernanceErrorV1.invalidField(record: "admission", field: "finalExitClass")
    }
  }
}

/// The evidence produced for one case during the admission invocation.
/// `relativeDirectory` is retained in the report; `directory` is only used to
/// inspect the invocation's evidence files.
public struct CoreSupportCaseEvidenceV1: Sendable {
  public let caseID: String
  public let directory: URL
  public let relativeDirectory: String

  public init(caseID: String, directory: URL, relativeDirectory: String) {
    self.caseID = caseID
    self.directory = directory
    self.relativeDirectory = relativeDirectory
  }
}

/// All inputs are supplied by the caller for one gate invocation. A case is
/// current only when every retained correlation names `gateRunID`.
public struct CoreSupportGateInputV1: Sendable {
  public let gateRunID: UUID
  public let manifest: CoreConformanceCasesManifestV1
  public let ledger: CoreDivergenceLedgerV1
  public let surface: CoreSupportSurfaceV1
  public let evidence: [CoreSupportCaseEvidenceV1]
  public let prerequisiteAvailable: Bool

  public init(
    gateRunID: UUID,
    manifest: CoreConformanceCasesManifestV1,
    ledger: CoreDivergenceLedgerV1,
    surface: CoreSupportSurfaceV1,
    evidence: [CoreSupportCaseEvidenceV1],
    prerequisiteAvailable: Bool = true
  ) {
    self.gateRunID = gateRunID
    self.manifest = manifest
    self.ledger = ledger
    self.surface = surface
    self.evidence = evidence
    self.prerequisiteAvailable = prerequisiteAvailable
  }
}

/// Evaluates only the bounded surface declared in `CoreSupportSurfaceV1`.
/// It does not infer support from a passing graph or act as another checker.
public struct CoreSupportGateV1: Sendable {
  public init() {}

  /// Never throws for an evidence or register problem. Instead it returns a
  /// blocked report with stable reason codes so the caller can retain it.
  public func evaluate(_ input: CoreSupportGateInputV1) -> CoreSupportAdmissionV1 {
    let manifestByID = Dictionary(uniqueKeysWithValues: input.manifest.cases.map { ($0.id, $0) })
    let evidenceGroups = Dictionary(grouping: input.evidence, by: \.caseID)
    let evidenceByCaseID = evidenceGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    let registerIsValid: Bool
    do {
      try input.manifest.validate(ledger: input.ledger)
      try input.surface.validate(caseIDs: Set(manifestByID.keys), ledger: input.ledger)
      registerIsValid = evidenceGroups.values.allSatisfy { $0.count == 1 }
    } catch {
      registerIsValid = false
    }

    let observations = manifestByID.mapValues { declaredCase in
      inspect(
        declaredCase,
        evidence: evidenceByCaseID[declaredCase.id],
        gateRunID: input.gateRunID,
        prerequisiteAvailable: input.prerequisiteAvailable,
        expectsExactComparison: input.ledger.records.contains {
          $0.disposition == .resolved && $0.permanentRegressionCaseID == declaredCase.id
        })
    }
    let unexplained = unexplainedDivergenceCaseIDs(
      observations: observations, ledger: input.ledger)
    let retainedRegressionsAreCurrent = input.ledger.records.allSatisfy { record in
      guard let observation = observations[record.permanentRegressionCaseID], observation.reasons.isEmpty else {
        return false
      }
      if record.disposition == .resolved {
        return record.latestComparison.outcome == .exact && !observation.comparisonIsDifference
      }
      let current = record.latestComparison.outcome == .difference
        && observation.comparisonIsDifference
        && observation.differenceFingerprint == record.normalizedDifferenceFingerprint
      return current
    }

    let entries = input.surface.entries.map { entry in
      decision(
        for: entry,
        observations: observations,
        ledger: input.ledger,
        registerIsValid: registerIsValid,
        hasUnexplainedDivergence: !unexplained.isEmpty,
        retainedRegressionsAreCurrent: retainedRegressionsAreCurrent,
        gateRunID: input.gateRunID)
    }
    let reportEntries: [CoreSupportAdmissionEntryV1]
    if entries.isEmpty || !registerIsValid && input.surface.entries.isEmpty {
      reportEntries = [invalidRegisterEntry()]
    } else {
      reportEntries = entries
    }
    return try! CoreSupportAdmissionV1(gateRunID: input.gateRunID, entries: reportEntries)
  }

  private func invalidRegisterEntry() -> CoreSupportAdmissionEntryV1 {
    try! CoreSupportAdmissionEntryV1(
      supportID: "governance-register", decision: .blocked, reasonCodes: [.invalidRegister],
      mandatoryCaseIDs: ["governance-register"], divergenceIDs: [])
  }

  private func decision(
    for entry: CoreSupportSurfaceEntryV1,
    observations: [String: CaseObservation],
    ledger: CoreDivergenceLedgerV1,
    registerIsValid: Bool,
    hasUnexplainedDivergence: Bool,
    retainedRegressionsAreCurrent: Bool,
    gateRunID: UUID
  ) -> CoreSupportAdmissionEntryV1 {
    var reasons = Set<CoreSupportReasonCodeV1>()
    var evidence: [CoreEvidenceReferenceV1] = []
    var correlations: [CoreSupportCaseRunCorrelationV1] = []

    if !registerIsValid { reasons.insert(.invalidRegister) }
    if !entry.category.isSupportedByV1 { reasons.insert(.unsupportedCategory) }
    if hasUnexplainedDivergence { reasons.insert(.unexplainedDivergence) }
    if !retainedRegressionsAreCurrent { reasons.insert(.unresolvedDivergence) }
    for caseID in entry.mandatoryCaseIDs {
      guard let observation = observations[caseID] else {
        reasons.insert(.missingEvidence)
        continue
      }
      reasons.formUnion(observation.reasons)
      evidence.append(contentsOf: observation.references)
      if let correlation = observation.correlation { correlations.append(correlation) }
    }
    let related = ledger.records.filter {
      entry.mandatoryCaseIDs.contains($0.provenance.caseID)
        || entry.mandatoryCaseIDs.contains($0.permanentRegressionCaseID)
    }
    guard Set(related.map(\.id)).isSubset(of: Set(entry.linkedDivergenceIDs)) else {
      reasons.insert(.unexplainedDivergence)
      return try! CoreSupportAdmissionEntryV1(
        supportID: entry.id, decision: .blocked,
        reasonCodes: reasons.sorted { $0.rawValue < $1.rawValue },
        mandatoryCaseIDs: entry.mandatoryCaseIDs,
        divergenceIDs: entry.linkedDivergenceIDs,
        evidence: evidence, caseRunCorrelations: correlations)
    }
    let linked = ledger.records.filter { entry.linkedDivergenceIDs.contains($0.id) }
    if linked.contains(where: { $0.disposition != .resolved }) {
      reasons.insert(.unresolvedDivergence)
    }

    let decision: CoreSupportDecisionV1
    switch entry.requestedStatus {
    case .unsupported:
      decision = .unsupported
      reasons = [.explicitlyUnsupported]
      evidence = []
      correlations = []
    case .blocked:
      decision = .blocked
      reasons.insert(.declaredBlocked)
    case .requested:
      decision = reasons.isEmpty ? .admitted : .blocked
    }
    return try! CoreSupportAdmissionEntryV1(
      supportID: entry.id,
      decision: decision,
      reasonCodes: reasons.sorted { $0.rawValue < $1.rawValue },
      mandatoryCaseIDs: entry.mandatoryCaseIDs,
      divergenceIDs: entry.linkedDivergenceIDs,
      evidence: evidence,
      caseRunCorrelations: correlations)
  }

  private func unexplainedDivergenceCaseIDs(
    observations: [String: CaseObservation], ledger: CoreDivergenceLedgerV1
  ) -> Set<String> {
    let recordsByCaseID = Dictionary(grouping: ledger.records, by: \.permanentRegressionCaseID)
    return Set(observations.compactMap { caseID, observation in
      guard observation.comparisonIsDifference else { return nil }
      guard let record = recordsByCaseID[caseID]?.first,
            observation.differenceFingerprint == record.normalizedDifferenceFingerprint else {
        return caseID
      }
      return nil
    })
  }

  private func inspect(
    _ declaredCase: CoreConformanceCasesManifestV1.Entry,
    evidence: CoreSupportCaseEvidenceV1?,
    gateRunID: UUID,
    prerequisiteAvailable: Bool,
    expectsExactComparison: Bool
  ) -> CaseObservation {
    guard prerequisiteAvailable else {
      return CaseObservation(reasons: [.missingPrerequisite])
    }
    guard let evidence else { return CaseObservation(reasons: [.missingEvidence]) }
    let requiredFiles = [
      "case.json", "toolchain.json", "arguments.json", "correlations.json", "run.json", "swift.json",
      "tlc.json", "comparison.json", "tlc-process.json", "raw-artifacts.json", "graph-events.jsonl"
    ]
    guard requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: evidence.directory.appendingPathComponent($0).path) }) else {
      return CaseObservation(reasons: [.partialEvidence])
    }
    do {
      let caseJSON = try object(named: "case.json", in: evidence.directory)
      let toolchainJSON = try object(named: "toolchain.json", in: evidence.directory)
      let argumentsJSON = try object(named: "arguments.json", in: evidence.directory)
      let correlationsJSON = try object(named: "correlations.json", in: evidence.directory)
      let runJSON = try object(named: "run.json", in: evidence.directory)
      let comparisonJSON = try object(named: "comparison.json", in: evidence.directory)
      let swiftJSON = try object(named: "swift.json", in: evidence.directory)
      let tlcJSON = try object(named: "tlc.json", in: evidence.directory)

      var reasons = Set<CoreSupportReasonCodeV1>()
      let expectedCase = try declaredCaseContract(declaredCase)
      if !caseMatches(caseJSON, declaredCase, expectedCase)
        || !argumentsMatch(argumentsJSON, declaredCase) {
        reasons.insert(.manifestDigestMismatch)
      }
      if !toolchainMatches(toolchainJSON, declaredCase) { reasons.insert(.toolchainDigestMismatch) }
      let correlation = try correlation(
        caseID: declaredCase.id, gateRunID: gateRunID, correlations: correlationsJSON,
        run: runJSON, swift: swiftJSON, tlc: tlcJSON, comparison: comparisonJSON)
      guard let correlation else {
        reasons.insert(.foreignRun)
        return CaseObservation(reasons: reasons)
      }

      let expectedExact = expectsExactComparison || declaredCase.governance.expectedRegressionOutcome == .exact
      let completeGraphs = canonicalGraphsAreComplete(swiftJSON, tlcJSON, requireExhaustiveCompletion: expectedExact)
      let matchingExactGraphs = !expectedExact || canonicalGraphsAgree(swiftJSON, tlcJSON)
      let processJSON = try object(named: "tlc-process.json", in: evidence.directory)
      guard let processIsViolation = processLifecycle(
        processJSON, caseID: declaredCase.id, gateRunID: gateRunID
      ) else { throw EvidenceError.invalidJSON }
      let rawManifest = rawArtifactManifestIsComplete(
        try object(named: "raw-artifacts.json", in: evidence.directory),
        in: evidence.directory,
        isViolation: processIsViolation)
      let rawEvidence = try rawEvidenceMatchesCanonicalOutcome(
        in: evidence.directory, expectedCase: expectedCase, gateRunID: gateRunID,
        isViolation: processIsViolation, tlc: tlcJSON)
      guard completeGraphs, matchingExactGraphs, rawManifest, rawEvidence
      else { throw EvidenceError.invalidJSON }

      let exitCode = runJSON["exitCode"] as? Int
      guard let exitCode else { throw EvidenceError.invalidJSON }
      let computed = try comparisonMatchesCanonicalTruth(
        swift: swiftJSON, tlc: tlcJSON, comparison: comparisonJSON)
      if exitCode == Int(CoreConformanceExitCodeV1.failure.rawValue) {
        reasons.insert(.executionFailed)
      }
      if expectedExact && (exitCode != Int(CoreConformanceExitCodeV1.exact.rawValue)
        || computed.isDifference) {
        reasons.insert(.nonExactComparison)
      }
      if !expectedExact && (exitCode != Int(CoreConformanceExitCodeV1.semanticDifference.rawValue)
        || !computed.isDifference) {
        reasons.insert(.nonExactComparison)
      }
      let references = try references(in: evidence)
      return CaseObservation(
        reasons: reasons, references: references, correlation: correlation,
        comparisonIsDifference: computed.isDifference, differenceFingerprint: computed.fingerprint)
    } catch {
      return CaseObservation(reasons: [.partialEvidence])
    }
  }

  private func references(in evidence: CoreSupportCaseEvidenceV1) throws -> [CoreEvidenceReferenceV1] {
    try ["case.json", "toolchain.json", "run.json", "comparison.json"].map { file in
      try CoreEvidenceReferenceV1(
        path: evidence.relativeDirectory + "/" + file,
        sha256: SHA256V1.hex(try Data(contentsOf: evidence.directory.appendingPathComponent(file))))
    }
  }

  private func correlation(
    caseID: String,
    gateRunID: UUID,
    correlations: [String: Any],
    run: [String: Any],
    swift: [String: Any],
    tlc: [String: Any],
    comparison: [String: Any]
  ) throws -> CoreSupportCaseRunCorrelationV1? {
    let expectedRunID = gateRunID.uuidString.lowercased()
    let sources: [(String, [String: Any], String)] = [
      ("swift", correlations["swift"] as? [String: Any] ?? [:], "swift"),
      ("tlc", correlations["tlc"] as? [String: Any] ?? [:], "tlc"),
      ("runner", correlations["runner"] as? [String: Any] ?? [:], "runner"),
      ("swift", swift["correlation"] as? [String: Any] ?? [:], "swift"),
      ("tlc", tlc["correlation"] as? [String: Any] ?? [:], "tlc"),
      ("runner", run["correlation"] as? [String: Any] ?? [:], "runner"),
      ("runner", comparison["correlation"] as? [String: Any] ?? [:], "runner")
    ]
    guard sources.allSatisfy({ expected, object, _ in
      object["caseID"] as? String == caseID && object["engine"] as? String == expected
        && object["runID"] as? String == expectedRunID
    }) else { return nil }
    return try CoreSupportCaseRunCorrelationV1(
      caseID: caseID, gateRunID: gateRunID, swiftRunID: gateRunID, tlcRunID: gateRunID,
      comparisonRunID: gateRunID)
  }

  private func object(named file: String, in directory: URL) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent(file))) as? [String: Any] else {
      throw EvidenceError.invalidJSON
    }
    return object
  }

  private struct CaseObservation {
    let reasons: Set<CoreSupportReasonCodeV1>
    var references: [CoreEvidenceReferenceV1] = []
    var correlation: CoreSupportCaseRunCorrelationV1?
    var comparisonIsDifference = false
    var differenceFingerprint: String?
  }

  private enum EvidenceError: Error { case invalidJSON }
}
