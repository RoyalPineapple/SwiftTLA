import Foundation
public enum TemporalSymmetrySupportRequest: String, Codable, Sendable {
  case requested
  case unsupported
  case blocked
}
public enum TemporalSymmetrySupportDecision: String, Codable, Sendable {
  case admitted
  case blocked
  case unsupported
}
public enum TemporalSymmetryAdmissionExitClass: String, Codable, Sendable {
  case success
  case blocked
  case unavailable
}
public enum TemporalSymmetryReasonCode: String, CaseIterable, Codable, Sendable {
  case invalidRegister
  case explicitlyUnsupported
  case declaredBlocked
  case missingPrerequisite
  case missingEvidence
  case partialEvidence
  case foreignRun
  case manifestDigestMismatch
  case toolchainDigestMismatch
  case configurationMismatch
  case executionFailed
  case nonExactComparison
  case missingTemporalWitness
  case missingOrbitEvidence
  case unresolvedDivergence
  case unexplainedDivergence
  case missingReportIdentity
  public var makesEvaluationUnavailable: Bool {
    switch self {
    case .invalidRegister, .missingPrerequisite, .missingEvidence, .partialEvidence, .foreignRun,
         .manifestDigestMismatch, .toolchainDigestMismatch, .configurationMismatch,
         .executionFailed, .missingTemporalWitness, .missingOrbitEvidence,
         .missingReportIdentity:
      true
    case .explicitlyUnsupported, .declaredBlocked, .nonExactComparison,
         .unresolvedDivergence, .unexplainedDivergence:
      false
    }
  }
}
/// The retention state of one P3 comparison. A comparison is only usable for
/// admission when its complete raw artifacts were retained by the runner.
public enum TemporalSymmetryEvidenceStatus: String, Codable, Sendable {
  case complete
  case partial
  case executionFailed
}
/// A comparison is deliberately typed by its conformance category. This keeps
/// a temporal result from being used as symmetry evidence, or vice versa.
public enum TemporalSymmetryComparisonEvidence: Sendable {
  case temporal(TemporalComparison)
  case symmetry(SymmetryOrbitComparison)
  public var caseID: String {
    switch self {
    case let .temporal(comparison): comparison.caseID
    case let .symmetry(comparison): comparison.caseID
    }
  }
  public var kind: TemporalSymmetryCaseKind {
    switch self {
    case .temporal: .temporal
    case .symmetry: .symmetry
    }
  }
  public var configuration: TemporalSymmetryConfiguration {
    switch self {
    case let .temporal(comparison): comparison.configuration
    case let .symmetry(comparison): comparison.configuration
    }
  }
  public var correlation: TemporalSymmetryCaseRunCorrelation {
    switch self {
    case let .temporal(comparison): comparison.correlation
    case let .symmetry(comparison): comparison.correlation
    }
  }
  public var outcome: TemporalSymmetryExpectedOutcome {
    switch self {
    case let .temporal(comparison): comparison.outcome
    case let .symmetry(comparison): comparison.outcome
    }
  }
}
/// The runner supplies one retained comparison record per case. The gate uses
/// the digest bindings and retention state here instead of guessing from a
/// successful process exit.
public struct TemporalSymmetryCaseEvidence: Sendable {
  public let comparison: TemporalSymmetryComparisonEvidence
  public let comparisonEvidence: CoreEvidenceReference
  public let manifestSHA256: String
  public let toolchainSHA256: String
  public let status: TemporalSymmetryEvidenceStatus
  public let normalizedDifferenceFingerprint: String?
  public init(
    comparison: TemporalSymmetryComparisonEvidence,
    comparisonEvidence: CoreEvidenceReference,
    manifestSHA256: String,
    toolchainSHA256: String,
    status: TemporalSymmetryEvidenceStatus,
    normalizedDifferenceFingerprint: String? = nil
  ) throws {
    try comparisonEvidence.validate()
    guard TLCReferencePin.isSHA256(manifestSHA256), TLCReferencePin.isSHA256(toolchainSHA256) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: comparison.caseID, field: "evidence digests")
    }
    let requiresFingerprint = comparison.outcome == .difference
    guard requiresFingerprint == (normalizedDifferenceFingerprint?.isEmpty == false) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: comparison.caseID, field: "normalizedDifferenceFingerprint")
    }
    self.comparison = comparison
    self.comparisonEvidence = comparisonEvidence
    self.manifestSHA256 = manifestSHA256
    self.toolchainSHA256 = toolchainSHA256
    self.status = status
    self.normalizedDifferenceFingerprint = normalizedDifferenceFingerprint
  }
}
/// All gate inputs describe exactly one report and one P3 invocation.
public struct TemporalSymmetryGateInput: Sendable {
  public let reportID: UUID
  public let gateRunID: UUID
  public let coreAdmission: TemporalSymmetryCoreAdmissionReference
  public let coreAdmissionContext: TemporalSymmetryCoreAdmissionContext
  public let cases: TemporalSymmetryCases
  public let ledger: TemporalSymmetryDivergenceLedger
  public let surface: TemporalSymmetrySupportSurface
  public let evidence: [TemporalSymmetryCaseEvidence]
  public let manifestSHA256: String
  public let toolchainSHA256: String
  public let prerequisiteAvailable: Bool
  public init(
    reportID: UUID = UUID(),
    gateRunID: UUID,
    coreAdmission: TemporalSymmetryCoreAdmissionReference,
    coreAdmissionContext: TemporalSymmetryCoreAdmissionContext,
    cases: TemporalSymmetryCases,
    ledger: TemporalSymmetryDivergenceLedger,
    surface: TemporalSymmetrySupportSurface,
    evidence: [TemporalSymmetryCaseEvidence],
    manifestSHA256: String,
    toolchainSHA256: String,
    prerequisiteAvailable: Bool = true
  ) {
    self.reportID = reportID
    self.gateRunID = gateRunID
    self.coreAdmission = coreAdmission
    self.coreAdmissionContext = coreAdmissionContext
    self.cases = cases
    self.ledger = ledger
    self.surface = surface
    self.evidence = evidence
    self.manifestSHA256 = manifestSHA256
    self.toolchainSHA256 = toolchainSHA256
    self.prerequisiteAvailable = prerequisiteAvailable
  }
}
/// Evaluates the declared finite P3 surface. It never converts a malformed,
/// stale, partial, or unaccounted result into an admitted support claim.
public struct TemporalSymmetrySupportGate: Sendable {
  public init() {}
  public func evaluate(_ input: TemporalSymmetryGateInput) -> TemporalSymmetryAdmission {
    let casesByID = Dictionary(uniqueKeysWithValues: input.cases.cases.map { ($0.id, $0) })
    let evidenceGroups = Dictionary(grouping: input.evidence, by: { $0.comparison.caseID })
    let evidenceByCaseID = evidenceGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    let registerIsValid: Bool
    do {
      try input.surface.validate(cases: input.cases, ledger: input.ledger)
      registerIsValid = evidenceGroups.values.allSatisfy { $0.count == 1 }
        && evidenceGroups.keys.allSatisfy { casesByID[$0] != nil }
        && TLCReferencePin.isSHA256(input.manifestSHA256)
        && TLCReferencePin.isSHA256(input.toolchainSHA256)
    } catch {
      registerIsValid = false
    }
    guard registerIsValid, !input.surface.entries.isEmpty else {
      return invalidRegisterReport(input)
    }
    let observations = casesByID.mapValues {
      inspect($0, evidence: evidenceByCaseID[$0.id], input: input)
    }
    let unexplainedCaseIDs = unexplainedDifferenceCaseIDs(observations: observations, ledger: input.ledger)
    let coreAdmissionReasons = coreAdmissionReasons(input)
    let entries = input.surface.entries.map {
      decision(
        for: $0,
        observations: observations,
        ledger: input.ledger,
        unexplainedCaseIDs: unexplainedCaseIDs,
        coreAdmissionReasons: coreAdmissionReasons,
        gateRunID: input.gateRunID)
    }
    let report = try! TemporalSymmetryAdmission(
      reportID: input.reportID,
      gateRunID: input.gateRunID,
      coreAdmission: input.coreAdmission,
      manifestSHA256: input.manifestSHA256,
      toolchainSHA256: input.toolchainSHA256,
      entries: entries,
      admittedBounds: Dictionary(uniqueKeysWithValues: input.surface.entries.compactMap { entry in
        entries.first(where: { $0.supportID == entry.id })?.decision == .admitted ? (entry.id, entry.finiteBounds) : nil
      }),
      unexplainedDivergenceCount: unexplainedCaseIDs.count,
      unexplainedDivergenceCaseIDs: unexplainedCaseIDs.sorted(),
      finalExitClass: exitClass(for: entries))
    try! report.validate(supportSurface: input.surface, cases: input.cases, ledger: input.ledger)
    return report
  }
  private func invalidRegisterReport(_ input: TemporalSymmetryGateInput) -> TemporalSymmetryAdmission {
    let entry = try! TemporalSymmetryAdmissionEntry(
      supportID: "governance-register",
      decision: .blocked,
      reasonCodes: [.invalidRegister],
      mandatoryCaseIDs: ["governance-register"],
      divergenceIDs: [])
    return try! TemporalSymmetryAdmission(
      reportID: input.reportID,
      gateRunID: input.gateRunID,
      coreAdmission: input.coreAdmission,
      manifestSHA256: validDigest(input.manifestSHA256),
      toolchainSHA256: validDigest(input.toolchainSHA256),
      entries: [entry],
      admittedBounds: [:],
      unexplainedDivergenceCount: 0,
      unexplainedDivergenceCaseIDs: [],
      finalExitClass: .unavailable)
  }
  private func inspect(
    _ declaredCase: TemporalSymmetryCase,
    evidence: TemporalSymmetryCaseEvidence?,
    input: TemporalSymmetryGateInput
  ) -> CaseObservation {
    guard input.prerequisiteAvailable else { return .init(reasons: [.missingPrerequisite]) }
    guard let evidence else { return .init(reasons: [.missingEvidence]) }
    var reasons = Set<TemporalSymmetryReasonCode>()
    if evidence.status == .partial { reasons.insert(.partialEvidence) }
    if evidence.status == .executionFailed { reasons.insert(.executionFailed) }
    if evidence.manifestSHA256 != input.manifestSHA256 { reasons.insert(.manifestDigestMismatch) }
    if evidence.toolchainSHA256 != input.toolchainSHA256 { reasons.insert(.toolchainDigestMismatch) }
    let comparison = evidence.comparison
    if comparison.caseID != declaredCase.id || comparison.kind != declaredCase.kind
      || comparison.configuration != declaredCase.configuration {
      reasons.insert(.configurationMismatch)
    }
    if comparison.correlation.gateRunID != input.gateRunID { reasons.insert(.foreignRun) }
    if comparison.outcome == .unavailable { reasons.insert(.partialEvidence) }
    if declaredCase.expectedOutcome != .exact || comparison.outcome != .exact {
      reasons.insert(.nonExactComparison)
    }
    if case let .temporal(temporal) = comparison,
       comparison.outcome == .exact,
       temporal.swiftResult.outcome == .violated && temporal.swiftResult.lasso == nil
         || temporal.tlcResult.outcome == .violated && temporal.tlcResult.lasso == nil {
      reasons.insert(.missingTemporalWitness)
    }
    if case let .symmetry(symmetry) = comparison,
       symmetry.orbits.isEmpty || symmetry.quotientTransitions.isEmpty {
      reasons.insert(.missingOrbitEvidence)
    }
    return .init(
      reasons: reasons,
      comparisonIsDifference: comparison.outcome == .difference,
      fingerprint: evidence.normalizedDifferenceFingerprint,
      reference: evidence.comparisonEvidence,
      correlation: comparison.correlation)
  }
  private func decision(
    for entry: TemporalSymmetrySupportSurfaceEntry,
    observations: [String: CaseObservation],
    ledger: TemporalSymmetryDivergenceLedger,
    unexplainedCaseIDs: Set<String>,
    coreAdmissionReasons: Set<TemporalSymmetryReasonCode>,
    gateRunID: UUID
  ) -> TemporalSymmetryAdmissionEntry {
    if entry.requestedStatus == .unsupported {
      return try! TemporalSymmetryAdmissionEntry(
        supportID: entry.id, decision: .unsupported, reasonCodes: [.explicitlyUnsupported],
        mandatoryCaseIDs: entry.mandatoryCaseIDs, divergenceIDs: entry.linkedDivergenceIDs)
    }
    var reasons = Set<TemporalSymmetryReasonCode>()
    var references: [CoreEvidenceReference] = []
    var correlations: [TemporalSymmetryCaseRunCorrelation] = []
    for caseID in entry.mandatoryCaseIDs {
      guard let observation = observations[caseID] else {
        reasons.insert(.missingEvidence)
        continue
      }
      reasons.formUnion(observation.reasons)
      if let reference = observation.reference { references.append(reference) }
      if let correlation = observation.correlation, correlation.gateRunID == gateRunID {
        correlations.append(correlation)
      }
    }
    if entry.requestedStatus == .requested, !unexplainedCaseIDs.isEmpty {
      reasons.insert(.unexplainedDivergence)
    }
    reasons.formUnion(coreAdmissionReasons)
    let linked = ledger.records.filter { entry.linkedDivergenceIDs.contains($0.id) }
    if linked.contains(where: { $0.disposition != .resolved || $0.latestComparison.outcome != .exact }) {
      reasons.insert(.unresolvedDivergence)
    }
    if entry.requestedStatus == .blocked { reasons.insert(.declaredBlocked) }
    let decision: TemporalSymmetrySupportDecision = reasons.isEmpty ? .admitted : .blocked
    return try! TemporalSymmetryAdmissionEntry(
      supportID: entry.id,
      decision: decision,
      reasonCodes: reasons.sorted { $0.rawValue < $1.rawValue },
      mandatoryCaseIDs: entry.mandatoryCaseIDs,
      divergenceIDs: entry.linkedDivergenceIDs,
      evidence: references,
      caseRunCorrelations: correlations)
  }
  private func unexplainedDifferenceCaseIDs(
    observations: [String: CaseObservation], ledger: TemporalSymmetryDivergenceLedger
  ) -> Set<String> {
    let recordsByRegressionCase = Dictionary(grouping: ledger.records, by: \.permanentRegressionCaseID)
    return Set(observations.compactMap { caseID, observation in
      guard observation.comparisonIsDifference else { return nil }
      guard let record = recordsByRegressionCase[caseID]?.first,
            observation.fingerprint == record.normalizedDifferenceFingerprint else {
        return caseID
      }
      return nil
    })
  }
  private func coreAdmissionReasons(_ input: TemporalSymmetryGateInput) -> Set<TemporalSymmetryReasonCode> {
    let core = input.coreAdmission
    let context = input.coreAdmissionContext
    var reasons = Set<TemporalSymmetryReasonCode>()
    if context.temporalSymmetryGateRunID != input.gateRunID {
      reasons.insert(.foreignRun)
    }
    if core.reportID != context.reportID {
      reasons.insert(.missingPrerequisite)
    }
    if core.gateRunID != context.coreGateRunID || core.report.path != context.reportPath {
      reasons.insert(.foreignRun)
    }
    if core.report.sha256 != context.reportSHA256 {
      reasons.insert(.manifestDigestMismatch)
    }
    return reasons
  }
  private func exitClass(for entries: [TemporalSymmetryAdmissionEntry]) -> TemporalSymmetryAdmissionExitClass {
    if entries.contains(where: { $0.reasonCodes.contains(where: \.makesEvaluationUnavailable) }) { return .unavailable }
    return entries.contains(where: { $0.decision == .blocked }) ? .blocked : .success
  }
  private func validDigest(_ value: String) -> String {
    TLCReferencePin.isSHA256(value) ? value : String(repeating: "0", count: 64)
  }
  private struct CaseObservation {
    let reasons: Set<TemporalSymmetryReasonCode>
    let comparisonIsDifference: Bool
    let fingerprint: String?
    let reference: CoreEvidenceReference?
    let correlation: TemporalSymmetryCaseRunCorrelation?
    init(
      reasons: Set<TemporalSymmetryReasonCode>,
      comparisonIsDifference: Bool = false,
      fingerprint: String? = nil,
      reference: CoreEvidenceReference? = nil,
      correlation: TemporalSymmetryCaseRunCorrelation? = nil
    ) {
      self.reasons = reasons
      self.comparisonIsDifference = comparisonIsDifference
      self.fingerprint = fingerprint
      self.reference = reference
      self.correlation = correlation
    }
  }
}
public enum TemporalSymmetryDeclaredReason: String, Codable, Sendable {
  case outsideDeclaredScope
  case combinedTemporalSymmetryUnsupported
  case awaitingRequiredEvidence
  case blockedByKnownDivergence
}
public struct TemporalSymmetrySupportSurfaceEntry: Equatable, Codable, Sendable {
  public let id: String
  public let behavior: String
  public let kind: TemporalSymmetryCaseKind
  public let finiteBounds: CoreFiniteBounds
  public let configuration: TemporalSymmetryConfiguration
  public let mandatoryCaseIDs: [String]
  public let requestedStatus: TemporalSymmetrySupportRequest
  public let linkedDivergenceIDs: [String]
  public let reason: TemporalSymmetryDeclaredReason?
  public init(
    id: String,
    behavior: String,
    kind: TemporalSymmetryCaseKind,
    finiteBounds: CoreFiniteBounds,
    configuration: TemporalSymmetryConfiguration,
    mandatoryCaseIDs: [String],
    requestedStatus: TemporalSymmetrySupportRequest,
    linkedDivergenceIDs: [String] = [],
    reason: TemporalSymmetryDeclaredReason? = nil
  ) throws {
    self.id = id
    self.behavior = behavior
    self.kind = kind
    self.finiteBounds = finiteBounds
    self.configuration = configuration
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.requestedStatus = requestedStatus
    self.linkedDivergenceIDs = linkedDivergenceIDs
    self.reason = reason
    try validate()
  }
  public func validate() throws {
    try finiteBounds.validate()
    try configuration.validate()
    guard !id.isEmpty, !behavior.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count,
          Set(linkedDivergenceIDs).count == linkedDivergenceIDs.count else {
      throw TemporalSymmetryGovernanceError.invalidField(record: id, field: "support entry")
    }
    if requestedStatus != .requested, reason == nil {
      throw TemporalSymmetryGovernanceError.invalidField(record: id, field: "reason")
    }
    switch kind {
    case .temporal:
      guard configuration.property != nil, !configuration.symmetryEnabled else {
        throw TemporalSymmetryGovernanceError.inconsistentReference(record: id, field: "temporal support")
      }
    case .symmetry:
      guard configuration.property == nil, configuration.symmetryEnabled else {
        throw TemporalSymmetryGovernanceError.inconsistentReference(record: id, field: "symmetry support")
      }
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, behavior, kind, finiteBounds, configuration, mandatoryCaseIDs, requestedStatus, linkedDivergenceIDs, reason
  }
  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      behavior: container.decode(String.self, forKey: .behavior),
      kind: container.decode(TemporalSymmetryCaseKind.self, forKey: .kind),
      finiteBounds: container.decode(CoreFiniteBounds.self, forKey: .finiteBounds),
      configuration: container.decode(TemporalSymmetryConfiguration.self, forKey: .configuration),
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      requestedStatus: container.decode(TemporalSymmetrySupportRequest.self, forKey: .requestedStatus),
      linkedDivergenceIDs: try container.decodeIfPresent([String].self, forKey: .linkedDivergenceIDs) ?? [],
      reason: try container.decodeIfPresent(TemporalSymmetryDeclaredReason.self, forKey: .reason))
  }
}
public struct TemporalSymmetrySupportSurface: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetrySupportSurface"
  public let schema: String
  public let entries: [TemporalSymmetrySupportSurfaceEntry]
  public init(entries: [TemporalSymmetrySupportSurfaceEntry]) throws {
    try self.init(schema: Self.schema, entries: entries)
  }
  public init(schema: String, entries: [TemporalSymmetrySupportSurfaceEntry]) throws {
    guard schema == Self.schema else { throw TemporalSymmetryGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for entry in entries {
      try entry.validate()
      guard ids.insert(entry.id).inserted else {
        throw TemporalSymmetryGovernanceError.duplicateID(kind: "support", id: entry.id)
      }
    }
    self.schema = schema
    self.entries = entries
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, entries }
  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      entries: container.decode([TemporalSymmetrySupportSurfaceEntry].self, forKey: .entries))
  }
  public func validate(cases: TemporalSymmetryCases, ledger: TemporalSymmetryDivergenceLedger) throws {
    let casesByID = Dictionary(uniqueKeysWithValues: cases.cases.map { ($0.id, $0) })
    try ledger.validate(cases: cases)
    let divergenceIDs = Set(ledger.records.map(\.id))
    for entry in entries {
      for caseID in entry.mandatoryCaseIDs {
        guard let item = casesByID[caseID] else { throw TemporalSymmetryGovernanceError.unknownCaseID(caseID) }
        guard item.kind == entry.kind, item.configuration == entry.configuration,
              item.finiteBounds == entry.finiteBounds else {
          throw TemporalSymmetryGovernanceError.inconsistentReference(record: entry.id, field: "mandatory case \(caseID)")
        }
      }
      for divergenceID in entry.linkedDivergenceIDs {
        guard let divergence = ledger.records.first(where: { $0.id == divergenceID }) else {
          throw TemporalSymmetryGovernanceError.unknownDivergenceID(divergenceID)
        }
        guard divergence.kind == entry.kind,
              entry.mandatoryCaseIDs.contains(divergence.provenance.caseID) else {
          throw TemporalSymmetryGovernanceError.inconsistentReference(
            record: entry.id, field: "linked divergence \(divergenceID)")
        }
      }
    }
    let linked = Set(entries.flatMap(\.linkedDivergenceIDs))
    guard divergenceIDs.isSubset(of: linked) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "support surface", field: "unlinked divergence")
    }
  }
}
public struct TemporalSymmetryCoreAdmissionReference: Equatable, Codable, Sendable {
  public let reportID: UUID
  public let gateRunID: UUID
  public let report: CoreEvidenceReference
  public init(reportID: UUID, gateRunID: UUID, report: CoreEvidenceReference) throws {
    self.reportID = reportID
    self.gateRunID = gateRunID
    self.report = report
    try report.validate()
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case reportID, gateRunID, report }
  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      reportID: container.decode(UUID.self, forKey: .reportID),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      report: container.decode(CoreEvidenceReference.self, forKey: .report))
  }
}
/// Binds the required core-admission artifact to the P3 invocation consuming
/// it. The runner obtains these values from the current core gate, rather than
/// accepting an arbitrary retained report reference.
public struct TemporalSymmetryCoreAdmissionContext: Equatable, Sendable {
  public let temporalSymmetryGateRunID: UUID
  public let reportID: UUID
  public let coreGateRunID: UUID
  public let reportPath: String
  public let reportSHA256: String
  public init(
    temporalSymmetryGateRunID: UUID,
    reportID: UUID,
    coreGateRunID: UUID,
    reportPath: String,
    reportSHA256: String
  ) throws {
    guard !reportPath.isEmpty, !reportPath.hasPrefix("/"), TLCReferencePin.isSHA256(reportSHA256) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "core admission", field: "current context")
    }
    self.temporalSymmetryGateRunID = temporalSymmetryGateRunID
    self.reportID = reportID
    self.coreGateRunID = coreGateRunID
    self.reportPath = reportPath
    self.reportSHA256 = reportSHA256
  }
}
public struct TemporalSymmetryAdmissionEntry: Equatable, Codable, Sendable {
  public let supportID: String
  public let decision: TemporalSymmetrySupportDecision
  public let reasonCodes: [TemporalSymmetryReasonCode]
  public let mandatoryCaseIDs: [String]
  public let divergenceIDs: [String]
  public let evidence: [CoreEvidenceReference]
  public let caseRunCorrelations: [TemporalSymmetryCaseRunCorrelation]
  public init(
    supportID: String,
    decision: TemporalSymmetrySupportDecision,
    reasonCodes: [TemporalSymmetryReasonCode],
    mandatoryCaseIDs: [String],
    divergenceIDs: [String],
    evidence: [CoreEvidenceReference] = [],
    caseRunCorrelations: [TemporalSymmetryCaseRunCorrelation] = []
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
          Set(divergenceIDs).count == divergenceIDs.count,
          Set(caseRunCorrelations.map(\.caseID)).count == caseRunCorrelations.count else {
      throw TemporalSymmetryGovernanceError.invalidField(record: supportID, field: "admission entry")
    }
    if decision == .admitted {
      guard reasonCodes.isEmpty, !evidence.isEmpty,
            Set(caseRunCorrelations.map(\.caseID)) == Set(mandatoryCaseIDs) else {
        throw TemporalSymmetryGovernanceError.invalidField(record: supportID, field: "admitted evidence")
      }
    } else if reasonCodes.isEmpty {
      throw TemporalSymmetryGovernanceError.invalidField(record: supportID, field: "reasonCodes")
    }
    try evidence.forEach { try $0.validate() }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case supportID, decision, reasonCodes, mandatoryCaseIDs, divergenceIDs, evidence, caseRunCorrelations
  }
  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      supportID: container.decode(String.self, forKey: .supportID),
      decision: container.decode(TemporalSymmetrySupportDecision.self, forKey: .decision),
      reasonCodes: container.decode([TemporalSymmetryReasonCode].self, forKey: .reasonCodes),
      mandatoryCaseIDs: container.decode([String].self, forKey: .mandatoryCaseIDs),
      divergenceIDs: container.decode([String].self, forKey: .divergenceIDs),
      evidence: container.decode([CoreEvidenceReference].self, forKey: .evidence),
      caseRunCorrelations: container.decode([TemporalSymmetryCaseRunCorrelation].self, forKey: .caseRunCorrelations))
  }
}
public struct TemporalSymmetryAdmission: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryAdmission"
  public static let authorityBoundary =
    "Published TLA+ semantics are authoritative; TLC is a pinned executable reference; "
      + "TLC source and tests are diagnostic evidence; no hidden checker or oracle is claimed."
  public let schema: String
  public let reportID: UUID
  public let gateRunID: UUID
  public let coreAdmission: TemporalSymmetryCoreAdmissionReference
  public let authority: String
  public let manifestSHA256: String
  public let toolchainSHA256: String
  public let entries: [TemporalSymmetryAdmissionEntry]
  public let admittedBounds: [String: CoreFiniteBounds]
  public let unexplainedDivergenceCount: Int
  public let unexplainedDivergenceCaseIDs: [String]
  public let finalExitClass: TemporalSymmetryAdmissionExitClass
  public init(
    reportID: UUID,
    gateRunID: UUID,
    coreAdmission: TemporalSymmetryCoreAdmissionReference,
    manifestSHA256: String,
    toolchainSHA256: String,
    entries: [TemporalSymmetryAdmissionEntry],
    admittedBounds: [String: CoreFiniteBounds],
    unexplainedDivergenceCount: Int,
    unexplainedDivergenceCaseIDs: [String] = [],
    finalExitClass: TemporalSymmetryAdmissionExitClass
  ) throws {
    try self.init(
      schema: Self.schema,
      reportID: reportID,
      gateRunID: gateRunID,
      coreAdmission: coreAdmission,
      authority: Self.authorityBoundary,
      manifestSHA256: manifestSHA256,
      toolchainSHA256: toolchainSHA256,
      entries: entries,
      admittedBounds: admittedBounds,
      unexplainedDivergenceCount: unexplainedDivergenceCount,
      unexplainedDivergenceCaseIDs: unexplainedDivergenceCaseIDs,
      finalExitClass: finalExitClass)
  }
  public init(
    schema: String,
    reportID: UUID,
    gateRunID: UUID,
    coreAdmission: TemporalSymmetryCoreAdmissionReference,
    authority: String,
    manifestSHA256: String,
    toolchainSHA256: String,
    entries: [TemporalSymmetryAdmissionEntry],
    admittedBounds: [String: CoreFiniteBounds],
    unexplainedDivergenceCount: Int,
    unexplainedDivergenceCaseIDs: [String] = [],
    finalExitClass: TemporalSymmetryAdmissionExitClass
  ) throws {
    guard schema == Self.schema, authority == Self.authorityBoundary else {
      throw TemporalSymmetryGovernanceError.invalidSchema(schema)
    }
    guard TLCReferencePin.isSHA256(manifestSHA256), TLCReferencePin.isSHA256(toolchainSHA256),
          unexplainedDivergenceCount >= 0,
          unexplainedDivergenceCaseIDs.count == unexplainedDivergenceCount,
          Set(unexplainedDivergenceCaseIDs).count == unexplainedDivergenceCaseIDs.count,
          unexplainedDivergenceCaseIDs.allSatisfy({ !$0.isEmpty }) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "report identity, digests, or divergence count")
    }
    guard !entries.isEmpty else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "entries")
    }
    var ids = Set<String>()
    for entry in entries {
      try entry.validate()
      guard entry.caseRunCorrelations.allSatisfy({ $0.gateRunID == gateRunID }), ids.insert(entry.supportID).inserted else {
        throw TemporalSymmetryGovernanceError.invalidField(record: entry.supportID, field: "correlations or duplicate support ID")
      }
    }
    let admittedSupportIDs = Set(entries.filter { $0.decision == .admitted }.map(\.supportID))
    guard Set(admittedBounds.keys) == admittedSupportIDs else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "admitted bounds")
    }
    try admittedBounds.values.forEach { try $0.validate() }
    let expected: TemporalSymmetryAdmissionExitClass
    if entries.contains(where: { $0.reasonCodes.contains(where: \.makesEvaluationUnavailable) }) {
      expected = .unavailable
    } else if entries.contains(where: { $0.decision == .blocked }) {
      expected = .blocked
    } else {
      expected = .success
    }
    guard finalExitClass == expected else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "finalExitClass")
    }
    self.schema = schema
    self.reportID = reportID
    self.gateRunID = gateRunID
    self.coreAdmission = coreAdmission
    self.authority = authority
    self.manifestSHA256 = manifestSHA256
    self.toolchainSHA256 = toolchainSHA256
    self.entries = entries
    self.admittedBounds = admittedBounds
    self.unexplainedDivergenceCount = unexplainedDivergenceCount
    self.unexplainedDivergenceCaseIDs = unexplainedDivergenceCaseIDs.sorted()
    self.finalExitClass = finalExitClass
  }
  public func validate(
    supportSurface: TemporalSymmetrySupportSurface,
    cases: TemporalSymmetryCases,
    ledger: TemporalSymmetryDivergenceLedger
  ) throws {
    try supportSurface.validate(cases: cases, ledger: ledger)
    let reportsByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.supportID, $0) })
    let supportIDs = Set(supportSurface.entries.map(\.id))
    guard Set(reportsByID.keys) == supportIDs else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "support entry coverage")
    }
    let casesByID = Dictionary(uniqueKeysWithValues: cases.cases.map { ($0.id, $0) })
    guard Set(unexplainedDivergenceCaseIDs).isSubset(of: Set(casesByID.keys)) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "admission", field: "unexplained divergence cases")
    }
    for support in supportSurface.entries {
      guard let entry = reportsByID[support.id],
            Set(entry.mandatoryCaseIDs) == Set(support.mandatoryCaseIDs),
            Set(entry.divergenceIDs) == Set(support.linkedDivergenceIDs),
            entry.caseRunCorrelations.allSatisfy({ support.mandatoryCaseIDs.contains($0.caseID) && $0.gateRunID == gateRunID }) else {
        throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "registered entry coverage")
      }
      switch support.requestedStatus {
      case .requested:
        guard entry.decision != .unsupported else {
          throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "requested entry downgraded")
        }
      case .unsupported:
        guard entry.decision == .unsupported else {
          throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "unsupported entry decision")
        }
      case .blocked:
        guard entry.decision == .blocked else {
          throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "blocked entry decision")
        }
      }
      if entry.decision == .admitted {
        guard unexplainedDivergenceCaseIDs.isEmpty || support.requestedStatus != .requested else {
          throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "global unexplained divergence")
        }
        guard admittedBounds[support.id] == support.finiteBounds,
              entry.evidence.count == support.mandatoryCaseIDs.count,
              Set(entry.caseRunCorrelations.map(\.caseID)) == Set(support.mandatoryCaseIDs),
              entry.mandatoryCaseIDs.allSatisfy({ casesByID[$0]?.kind == support.kind }) else {
          throw TemporalSymmetryGovernanceError.invalidField(record: support.id, field: "current admitted evidence")
        }
      }
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, reportID, gateRunID, coreAdmission, authority, manifestSHA256, toolchainSHA256, entries
    case admittedBounds, unexplainedDivergenceCount, unexplainedDivergenceCaseIDs, finalExitClass
  }
  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(String.self, forKey: .schema),
      reportID: container.decode(UUID.self, forKey: .reportID),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      coreAdmission: container.decode(TemporalSymmetryCoreAdmissionReference.self, forKey: .coreAdmission),
      authority: container.decode(String.self, forKey: .authority),
      manifestSHA256: container.decode(String.self, forKey: .manifestSHA256),
      toolchainSHA256: container.decode(String.self, forKey: .toolchainSHA256),
      entries: container.decode([TemporalSymmetryAdmissionEntry].self, forKey: .entries),
      admittedBounds: container.decode([String: CoreFiniteBounds].self, forKey: .admittedBounds),
      unexplainedDivergenceCount: container.decode(Int.self, forKey: .unexplainedDivergenceCount),
      unexplainedDivergenceCaseIDs: container.decode([String].self, forKey: .unexplainedDivergenceCaseIDs),
      finalExitClass: container.decode(TemporalSymmetryAdmissionExitClass.self, forKey: .finalExitClass))
  }
}
