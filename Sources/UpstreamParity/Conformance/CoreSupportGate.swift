import Foundation
public enum CoreSupportCategory: String, Codable, Sendable {
  case stateSpace
  case transitionRelation
  case invariantSafety
  case temporal
  case symmetry
  case parser
  case annotation
  case generatedBehavior
  case platform
  public var isSupportedBy: Bool {
    switch self {
    case .stateSpace, .transitionRelation, .invariantSafety: true
    case .temporal, .symmetry, .parser, .annotation, .generatedBehavior, .platform: false
    }
  }
}
public enum CoreSupportRequest: String, Codable, Sendable {
  case requested
  case unsupported
  case blocked
}
public enum CoreSupportDecision: String, Codable, Sendable {
  case admitted
  case blocked
  case unsupported
}
public enum CoreSupportAdmissionExitClass: String, Codable, Sendable {
  case success
  case blocked
}
public enum CoreSupportReasonCode: String, CaseIterable, Codable, Sendable {
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
}
public struct CoreConformanceCaseGovernance: Equatable, Codable, Sendable {
  public let finiteBounds: CoreFiniteBounds
  public let semanticCitations: [String]
  public init(
    finiteBounds: CoreFiniteBounds,
    semanticCitations: [String]
  ) throws {
    self.finiteBounds = finiteBounds
    self.semanticCitations = semanticCitations
    try validate()
  }
  public func validate() throws {
    try finiteBounds.validate()
    guard !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
      throw ConformanceGovernanceError.invalidField(record: "case", field: "semanticCitations")
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case finiteBounds, semanticCitations
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      finiteBounds: container.decode(CoreFiniteBounds.self, forKey: .finiteBounds),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations))
  }
}
public struct CoreSupportSurfaceEntry: Equatable, Codable, Sendable {
  public let id: String
  public let behavior: String
  public let category: CoreSupportCategory
  public let finiteBounds: CoreFiniteBounds
  public let relation: CanonicalSchema
  public let mandatoryCaseIDs: [String]
  public let requestedStatus: CoreSupportRequest
  public let reason: String?
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case behavior
    case category
    case finiteBounds
    case relation
    case mandatoryCaseIDs
    case requestedStatus
    case reason
  }
  public init(
    id: String,
    behavior: String,
    category: CoreSupportCategory,
    finiteBounds: CoreFiniteBounds,
    relation: CanonicalSchema = .exactFiniteTLCGraph,
    mandatoryCaseIDs: [String],
    requestedStatus: CoreSupportRequest,
    reason: String? = nil
  ) throws {
    self.id = id
    self.behavior = behavior
    self.category = category
    self.finiteBounds = finiteBounds
    self.relation = relation
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.requestedStatus = requestedStatus
    self.reason = reason
    try validate()
  }
  public func validate() throws {
    try finiteBounds.validate()
    guard !id.isEmpty, !behavior.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "support entry")
    }
    guard category.isSupportedBy else {
      throw ConformanceGovernanceError.unsupportedCategory(category.rawValue)
    }
    guard relation == .exactFiniteTLCGraph else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "relation")
    }
    if requestedStatus != .requested, reason?.isEmpty != false {
      throw ConformanceGovernanceError.invalidField(record: id, field: "reason")
    }
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    let relation = try CanonicalSchema(validating: container.decode(String.self, forKey: .relation))
    try self.init(
      id: container.decode(String.self, forKey: .id),
      behavior: container.decode(String.self, forKey: .behavior),
      category: container.decode(CoreSupportCategory.self, forKey: .category),
      finiteBounds: container.decode(CoreFiniteBounds.self, forKey: .finiteBounds),
      relation: relation,
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      requestedStatus: container.decode(CoreSupportRequest.self, forKey: .requestedStatus),
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
    try container.encodeIfPresent(reason, forKey: .reason)
  }
}
public struct CoreSupportSurface: Equatable, Codable, Sendable {
  public static let schema = "CoreSupportSurface"
  public let schema: String
  public let entries: [CoreSupportSurfaceEntry]
  public init(entries: [CoreSupportSurfaceEntry]) throws {
    try self.init(schema: Self.schema, entries: entries)
  }
  public init(schema: String, entries: [CoreSupportSurfaceEntry]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var identifiers = Set<String>()
    for entry in entries {
      try entry.validate()
      guard identifiers.insert(entry.id).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "support", id: entry.id)
      }
    }
    self.schema = schema
    self.entries = entries
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, entries }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      entries: container.decode([CoreSupportSurfaceEntry].self, forKey: .entries))
  }
  public func validate(caseIDs: Set<String>) throws {
    for entry in entries {
      for caseID in entry.mandatoryCaseIDs where !caseIDs.contains(caseID) {
        throw ConformanceGovernanceError.unknownCaseID(caseID)
      }
    }
  }
}
public struct CoreSupportAdmissionEntry: Equatable, Codable, Sendable {
  public let supportID: String
  public let decision: CoreSupportDecision
  public let reasonCodes: [CoreSupportReasonCode]
  public let mandatoryCaseIDs: [String]
  public let evidence: [CoreEvidenceReference]
  public let caseRunCorrelations: [CoreSupportCaseRunCorrelation]
  public init(
    supportID: String,
    decision: CoreSupportDecision,
    reasonCodes: [CoreSupportReasonCode],
    mandatoryCaseIDs: [String],
    evidence: [CoreEvidenceReference] = [],
    caseRunCorrelations: [CoreSupportCaseRunCorrelation] = []
  ) throws {
    self.supportID = supportID
    self.decision = decision
    self.reasonCodes = reasonCodes
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.evidence = evidence
    self.caseRunCorrelations = caseRunCorrelations
    try validate()
  }
  public func validate() throws {
    guard !supportID.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(reasonCodes).count == reasonCodes.count,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count else {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "admission entry")
    }
    if decision == .admitted, !reasonCodes.isEmpty {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "reasonCodes")
    }
    if decision != .admitted, reasonCodes.isEmpty {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "reasonCodes")
    }
    try evidence.forEach { try $0.validate() }
    try caseRunCorrelations.forEach { try $0.validate() }
    let correlatedCases = Set(caseRunCorrelations.map(\.caseID))
    guard correlatedCases.count == caseRunCorrelations.count else {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "caseRunCorrelations")
    }
    if decision == .admitted {
      guard !evidence.isEmpty, correlatedCases == Set(mandatoryCaseIDs) else {
        throw ConformanceGovernanceError.invalidField(record: supportID, field: "evidence or caseRunCorrelations")
      }
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case supportID, decision, reasonCodes, mandatoryCaseIDs, evidence, caseRunCorrelations
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      supportID: container.decode(String.self, forKey: .supportID),
      decision: container.decode(CoreSupportDecision.self, forKey: .decision),
      reasonCodes: container.decode([CoreSupportReasonCode].self, forKey: .reasonCodes),
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      evidence: container.decode([CoreEvidenceReference].self, forKey: .evidence),
      caseRunCorrelations: container.decode(
        [CoreSupportCaseRunCorrelation].self, forKey: .caseRunCorrelations))
  }
}
public struct CoreSupportCaseRunCorrelation: Equatable, Codable, Sendable {
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
      throw ConformanceGovernanceError.invalidField(record: "caseRunCorrelation", field: "caseID")
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, gateRunID, swiftRunID, tlcRunID, comparisonRunID
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      swiftRunID: container.decode(UUID.self, forKey: .swiftRunID),
      tlcRunID: container.decode(UUID.self, forKey: .tlcRunID),
      comparisonRunID: container.decode(UUID.self, forKey: .comparisonRunID))
  }
}
public struct CoreSupportAdmissionCounts: Equatable, Codable, Sendable {
  public let admitted: Int
  public let blocked: Int
  public let unsupported: Int
  public let missing: Int
  public let stale: Int
  public let failing: Int
  public let nonExact: Int
  public init(entries: [CoreSupportAdmissionEntry]) {
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
    nonExact = entries.reduce(into: 0) { count, entry in
      if entry.reasonCodes.contains(.nonExactComparison) { count += 1 }
    }
  }
  private init(
    admitted: Int,
    blocked: Int,
    unsupported: Int,
    missing: Int,
    stale: Int,
    failing: Int,
    nonExact: Int
  ) throws {
    guard [admitted, blocked, unsupported, missing, stale, failing, nonExact].allSatisfy({ $0 >= 0 }) else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "counts")
    }
    self.admitted = admitted
    self.blocked = blocked
    self.unsupported = unsupported
    self.missing = missing
    self.stale = stale
    self.failing = failing
    self.nonExact = nonExact
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case admitted, blocked, unsupported, missing, stale, failing, nonExact
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      admitted: container.decode(Int.self, forKey: .admitted),
      blocked: container.decode(Int.self, forKey: .blocked),
      unsupported: container.decode(Int.self, forKey: .unsupported),
      missing: container.decode(Int.self, forKey: .missing),
      stale: container.decode(Int.self, forKey: .stale),
      failing: container.decode(Int.self, forKey: .failing),
      nonExact: container.decode(Int.self, forKey: .nonExact))
  }
}
public struct CoreSupportAdmission: Equatable, Codable, Sendable {
  public static let schema = "CoreSupportAdmission"
  public static let authorityBoundary =
    "Published TLA+ semantics are authoritative; TLC is a pinned executable reference; "
    + "TLC source and tests are diagnostic evidence; no hidden checker or oracle is claimed."
  public let schema: String
  public let gateRunID: UUID
  public let authority: String
  public let entries: [CoreSupportAdmissionEntry]
  public let counts: CoreSupportAdmissionCounts
  public let finalExitClass: CoreSupportAdmissionExitClass
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, gateRunID, authority, entries, counts, finalExitClass
  }
  public init(gateRunID: UUID, entries: [CoreSupportAdmissionEntry]) throws {
    try self.init(schema: Self.schema, gateRunID: gateRunID, authority: Self.authorityBoundary, entries: entries)
  }
  public init(schema: String, gateRunID: UUID, authority: String, entries: [CoreSupportAdmissionEntry]) throws {
    guard schema == Self.schema, authority == Self.authorityBoundary else {
      throw ConformanceGovernanceError.invalidSchema(schema)
    }
    var identifiers = Set<String>()
    for entry in entries {
      try entry.validate()
      guard entry.caseRunCorrelations.allSatisfy({ $0.gateRunID == gateRunID }) else {
        throw ConformanceGovernanceError.invalidField(record: entry.supportID, field: "caseRunCorrelations")
      }
      guard identifiers.insert(entry.supportID).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "admission", id: entry.supportID)
      }
    }
    self.schema = schema
    self.gateRunID = gateRunID
    self.authority = authority
    self.entries = entries
    self.counts = CoreSupportAdmissionCounts(entries: entries)
    self.finalExitClass = !entries.contains { $0.decision == .blocked }
      ? .success
      : .blocked
  }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    let entries = try container.decode([CoreSupportAdmissionEntry].self, forKey: .entries)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      authority: container.decode(String.self, forKey: .authority),
      entries: entries)
    let reportedCounts = try container.decode(CoreSupportAdmissionCounts.self, forKey: .counts)
    guard reportedCounts == counts else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "counts")
    }
    let reportedExitClass = try container.decode(CoreSupportAdmissionExitClass.self, forKey: .finalExitClass)
    guard reportedExitClass == finalExitClass else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "finalExitClass")
    }
  }
}
/// The evidence produced for one case during the admission invocation.
/// `relativeDirectory` is retained in the report; `directory` is only used to
/// inspect the invocation's evidence files.
public struct CoreSupportCaseEvidence: Sendable {
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
public struct CoreSupportGateInput: Sendable {
  public let gateRunID: UUID
  public let referencePin: TLCReferencePin
  public let manifest: CoreConformanceCasesManifest
  public let surface: CoreSupportSurface
  public let evidence: [CoreSupportCaseEvidence]
  public let prerequisiteAvailable: Bool
  public init(
    gateRunID: UUID,
    referencePin: TLCReferencePin,
    manifest: CoreConformanceCasesManifest,
    surface: CoreSupportSurface,
    evidence: [CoreSupportCaseEvidence],
    prerequisiteAvailable: Bool = true
  ) {
    self.gateRunID = gateRunID
    self.referencePin = referencePin
    self.manifest = manifest
    self.surface = surface
    self.evidence = evidence
    self.prerequisiteAvailable = prerequisiteAvailable
  }
}
/// Evaluates only the bounded surface declared in `CoreSupportSurface`.
/// It does not infer support from a passing graph or act as another checker.
public struct CoreSupportGate: Sendable {
  public init() {}
  public func evaluate(_ input: CoreSupportGateInput) throws -> CoreSupportAdmission {
    let manifestByID = Dictionary(uniqueKeysWithValues: input.manifest.cases.map { ($0.id, $0) })
    let evidenceGroups = Dictionary(grouping: input.evidence, by: \.caseID)
    let evidenceByCaseID = evidenceGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    let registerIsValid: Bool
    do {
      try input.manifest.validate()
      try input.surface.validate(caseIDs: Set(manifestByID.keys))
      registerIsValid = evidenceGroups.values.allSatisfy { $0.count == 1 }
    } catch {
      registerIsValid = false
    }
    let observations = manifestByID.mapValues { declaredCase in
      inspect(
        declaredCase,
        referencePin: input.referencePin,
        evidence: evidenceByCaseID[declaredCase.id],
        gateRunID: input.gateRunID,
        prerequisiteAvailable: input.prerequisiteAvailable)
    }
    let entries = try input.surface.entries.map { entry in
      try decision(
        for: entry,
        observations: observations,
        registerIsValid: registerIsValid,
        gateRunID: input.gateRunID)
    }
    let reportEntries: [CoreSupportAdmissionEntry]
    if entries.isEmpty || !registerIsValid && input.surface.entries.isEmpty {
      reportEntries = [try invalidRegisterEntry()]
    } else {
      reportEntries = entries
    }
    return try CoreSupportAdmission(gateRunID: input.gateRunID, entries: reportEntries)
  }
  private func invalidRegisterEntry() throws -> CoreSupportAdmissionEntry {
    try CoreSupportAdmissionEntry(
      supportID: "governance-register", decision: .blocked, reasonCodes: [.invalidRegister],
      mandatoryCaseIDs: ["governance-register"])
  }
  private func decision(
    for entry: CoreSupportSurfaceEntry,
    observations: [String: CaseObservation],
    registerIsValid: Bool,
    gateRunID: UUID
  ) throws -> CoreSupportAdmissionEntry {
    var reasons = Set<CoreSupportReasonCode>()
    var evidence: [CoreEvidenceReference] = []
    var correlations: [CoreSupportCaseRunCorrelation] = []
    if !registerIsValid { reasons.insert(.invalidRegister) }
    if !entry.category.isSupportedBy { reasons.insert(.unsupportedCategory) }
    for caseID in entry.mandatoryCaseIDs {
      guard let observation = observations[caseID] else {
        reasons.insert(.missingEvidence)
        continue
      }
      reasons.formUnion(observation.reasons)
      evidence.append(contentsOf: observation.references)
      if let correlation = observation.correlation { correlations.append(correlation) }
    }
    let decision: CoreSupportDecision
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
    return try CoreSupportAdmissionEntry(
      supportID: entry.id,
      decision: decision,
      reasonCodes: reasons.sorted { $0.rawValue < $1.rawValue },
      mandatoryCaseIDs: entry.mandatoryCaseIDs,
      evidence: evidence,
      caseRunCorrelations: correlations)
  }
  private func inspect(
    _ declaredCase: CoreConformanceCasesManifest.Entry,
    referencePin: TLCReferencePin,
    evidence: CoreSupportCaseEvidence?,
    gateRunID: UUID,
    prerequisiteAvailable: Bool
  ) -> CaseObservation {
    guard prerequisiteAvailable else {
      return CaseObservation(reasons: [.missingPrerequisite])
    }
    guard let evidence else { return CaseObservation(reasons: [.missingEvidence]) }
    let requiredFiles = [
      "run.json", "core-decision.json",
      "tlc-process.json", "raw-artifacts.json", "graph-events.jsonl"
    ]
    guard requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: evidence.directory.appendingPathComponent($0).path) }) else {
      return CaseObservation(reasons: [.partialEvidence])
    }
    do {
      let processJSON = try object(named: "tlc-process.json", in: evidence.directory)
      guard let requestJSON = processJSON["request"] as? [String: Any],
            let caseJSON = requestJSON["case"] as? [String: Any],
            let toolchainJSON = requestJSON["toolchain"] as? [String: Any],
            let argumentsJSON = requestJSON["arguments"] as? [String]
      else { throw EvidenceError.invalidJSON }
      let runJSON = try object(named: "run.json", in: evidence.directory)
      let decision = try CanonicalConformanceEvidence.read(from: evidence.directory)
      var reasons = Set<CoreSupportReasonCode>()
      guard decision.evidence.comparison.expectedReceipt.maximumStateLimit == declaredCase.maximumStateLimit,
            decision.evidence.comparison.actualReceipt.maximumStateLimit == declaredCase.maximumStateLimit
      else { throw EvidenceError.invalidJSON }
      let expectedCase = try declaredCaseContract(declaredCase, referencePin: referencePin)
      if !caseMatches(caseJSON, declaredCase, expectedCase)
        || argumentsJSON != declaredCase.arguments {
        reasons.insert(.manifestDigestMismatch)
      }
      if !toolchainMatches(toolchainJSON, declaredCase, referencePin: referencePin) {
        reasons.insert(.toolchainDigestMismatch)
      }
      let correlation = try correlation(
        caseID: declaredCase.id, gateRunID: gateRunID,
        process: processJSON, run: runJSON, decision: decision.evidence)
      guard let correlation else {
        reasons.insert(.foreignRun)
        return CaseObservation(reasons: reasons)
      }
      let completeGraphs = canonicalRunsAreComplete(
        decision.swiftRun, decision.tlcRun, requireExhaustiveCompletion: true)
      guard let processIsViolation = processLifecycle(
        processJSON, caseID: declaredCase.id, gateRunID: gateRunID
      ) else { throw EvidenceError.invalidJSON }
      let rawManifest = rawArtifactManifestIsComplete(
        try object(named: "raw-artifacts.json", in: evidence.directory),
        in: evidence.directory,
        isViolation: processIsViolation)
      let rawEvidence = try rawEvidenceMatchesCanonicalOutcome(
        in: evidence.directory, expectedCase: expectedCase, gateRunID: gateRunID,
        isViolation: processIsViolation, tlc: decision.tlcRun)
      guard completeGraphs, rawManifest, rawEvidence
      else { throw EvidenceError.invalidJSON }
      let exitCode = runJSON["exitCode"] as? Int
      guard let exitCode else { throw EvidenceError.invalidJSON }
      if exitCode == Int(CoreConformanceExitCode.failure.rawValue) {
        reasons.insert(.executionFailed)
      }
      if exitCode != Int(CoreConformanceExitCode.exact.rawValue) || !decision.comparison.isConformant {
        reasons.insert(.nonExactComparison)
      }
      let references = try references(in: evidence, decision: decision.evidence)
      return CaseObservation(
        reasons: reasons, references: references, correlation: correlation)
    } catch {
      return CaseObservation(reasons: [.partialEvidence])
    }
  }
  private func references(
    in evidence: CoreSupportCaseEvidence,
    decision: CanonicalConformanceEvidence
  ) throws -> [CoreEvidenceReference] {
    let retainedGraphRecords = [decision.swift.run] + decision.swift.chunks
      + [decision.tlc.run] + decision.tlc.chunks
    let graphReferences = try retainedGraphRecords.map {
      try CoreEvidenceReference(
        path: evidence.relativeDirectory + "/" + $0.path,
        sha256: $0.sha256)
    }
    let attestationReferences = try [
      "core-decision.json", "tlc-process.json", "run.json", "raw-artifacts.json", "graph-events.jsonl"
    ].map { file in
      try CoreEvidenceReference(
        path: evidence.relativeDirectory + "/" + file,
        sha256: SHA256.hex(try Data(contentsOf: evidence.directory.appendingPathComponent(file))))
    }
    return attestationReferences + graphReferences
  }
  private func correlation(
    caseID: String,
    gateRunID: UUID,
    process: [String: Any],
    run: [String: Any],
    decision: CanonicalConformanceEvidence
  ) throws -> CoreSupportCaseRunCorrelation? {
    let expectedRunID = gateRunID.uuidString.lowercased()
    let processCorrelation = (process["request"] as? [String: Any])?["correlation"] as? [String: Any] ?? [:]
    let sources: [(String, [String: Any], String)] = [
      ("tlc", processCorrelation, "tlc"),
      ("runner", run["correlation"] as? [String: Any] ?? [:], "runner")
    ]
    guard sources.allSatisfy({ expected, object, _ in
      object["caseID"] as? String == caseID && object["engine"] as? String == expected
        && object["runID"] as? String == expectedRunID
    }),
      decision.correlation.matches(caseID: caseID, runID: gateRunID, engine: .runner)
    else { return nil }
    return try CoreSupportCaseRunCorrelation(
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
    let reasons: Set<CoreSupportReasonCode>
    var references: [CoreEvidenceReference] = []
    var correlation: CoreSupportCaseRunCorrelation?
  }
  private enum EvidenceError: Error { case invalidJSON }
}
