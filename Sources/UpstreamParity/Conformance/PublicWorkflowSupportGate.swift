import Foundation

public enum PublicWorkflowSupportRequest: String, Codable, Sendable { case requested, unsupported, blocked }
public enum PublicWorkflowSupportDecision: String, Codable, Sendable { case admitted, blocked, unsupported, unavailable }
public enum PublicWorkflowAdmissionExitClass: String, Codable, Sendable { case success, blocked, unavailable }

public enum PublicWorkflowReasonCode: String, CaseIterable, Codable, Sendable {
  case invalidRegister
  case explicitlyUnsupported
  case declaredBlocked
  case missingPrerequisite
  case missingEvidence
  case partialEvidence
  case foreignRun
  case staleEvidence
  case mixedRunEvidence
  case incompletePins
  case nonExactComparison
  case unsupportedPlatform
  case platformValidationFailed
  case unresolvedDivergence
  case unexplainedDivergence
  case executionFailed
  case nonCIExecution
}

public enum PublicWorkflowPrerequisiteCategory: String, Codable, Sendable { case core, temporalSymmetry }

public struct PublicWorkflowSupportSurfaceEntry: Equatable, Codable, Sendable {
  public let id: String
  public let behavior: String
  public let category: PublicWorkflowCaseCategory
  public let finiteBounds: CoreFiniteBounds
  public let mandatoryCaseIDs: [String]
  public let requestedStatus: PublicWorkflowSupportRequest
  public let releaseClaim: String
  public let linkedDivergenceIDs: [String]
  public let requiredPlatforms: [String]
  public let prerequisiteCategories: [PublicWorkflowPrerequisiteCategory]
  public let reason: String?

  public init(
    id: String, behavior: String, category: PublicWorkflowCaseCategory, finiteBounds: CoreFiniteBounds,
    mandatoryCaseIDs: [String], requestedStatus: PublicWorkflowSupportRequest, releaseClaim: String,
    linkedDivergenceIDs: [String] = [], requiredPlatforms: [String] = [],
    prerequisiteCategories: [PublicWorkflowPrerequisiteCategory] = [], reason: String? = nil
  ) throws {
    self.id = id
    self.behavior = behavior
    self.category = category
    self.finiteBounds = finiteBounds
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.requestedStatus = requestedStatus
    self.releaseClaim = releaseClaim
    self.linkedDivergenceIDs = linkedDivergenceIDs
    self.requiredPlatforms = requiredPlatforms
    self.prerequisiteCategories = prerequisiteCategories
    self.reason = reason
    try validate()
  }

  public func validate() throws {
    try finiteBounds.validate()
    guard !id.isEmpty, !behavior.isEmpty, !releaseClaim.isEmpty, !mandatoryCaseIDs.isEmpty,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count,
          Set(linkedDivergenceIDs).count == linkedDivergenceIDs.count,
          Set(requiredPlatforms).count == requiredPlatforms.count,
          requiredPlatforms.allSatisfy({ !$0.isEmpty }),
          Set(prerequisiteCategories).count == prerequisiteCategories.count else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "support entry")
    }
    if requestedStatus != .requested, reason?.isEmpty != false {
      throw ConformanceGovernanceError.invalidField(record: id, field: "reason")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, behavior, category, finiteBounds, mandatoryCaseIDs, requestedStatus, releaseClaim
    case linkedDivergenceIDs, requiredPlatforms, prerequisiteCategories, reason
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(id: try container.decode(String.self, forKey: .id), behavior: try container.decode(String.self, forKey: .behavior), category: try container.decode(PublicWorkflowCaseCategory.self, forKey: .category), finiteBounds: try container.decode(CoreFiniteBounds.self, forKey: .finiteBounds), mandatoryCaseIDs: try container.decode([String].self, forKey: .mandatoryCaseIDs), requestedStatus: try container.decode(PublicWorkflowSupportRequest.self, forKey: .requestedStatus), releaseClaim: try container.decode(String.self, forKey: .releaseClaim), linkedDivergenceIDs: try container.decodeIfPresent([String].self, forKey: .linkedDivergenceIDs) ?? [], requiredPlatforms: try container.decodeIfPresent([String].self, forKey: .requiredPlatforms) ?? [], prerequisiteCategories: try container.decodeIfPresent([PublicWorkflowPrerequisiteCategory].self, forKey: .prerequisiteCategories) ?? [], reason: try container.decodeIfPresent(String.self, forKey: .reason))
  }
}

public struct PublicWorkflowSupportSurface: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowSupportSurface"
  public let schema: String
  public let entries: [PublicWorkflowSupportSurfaceEntry]

  public init(entries: [PublicWorkflowSupportSurfaceEntry]) throws { try self.init(schema: Self.schema, entries: entries) }

  public init(schema: String, entries: [PublicWorkflowSupportSurfaceEntry]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for entry in entries {
      try entry.validate()
      guard ids.insert(entry.id).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "support", id: entry.id)
      }
    }
    self.schema = schema
    self.entries = entries
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, entries }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), entries: try container.decode([PublicWorkflowSupportSurfaceEntry].self, forKey: .entries))
  }

  public func validate(cases: PublicWorkflowCases, ledger: PublicWorkflowDivergenceLedger) throws {
    let caseIDs = Set(cases.cases.map(\.id))
    try ledger.validate(caseIDs: caseIDs)
    let divergenceIDs = Set(ledger.records.map(\.id))
    for entry in entries {
      for caseID in entry.mandatoryCaseIDs where !caseIDs.contains(caseID) {
        throw ConformanceGovernanceError.unknownCaseID(caseID)
      }
      for caseID in entry.mandatoryCaseIDs {
        guard let record = cases.cases.first(where: { $0.id == caseID }),
              record.category == entry.category, record.finiteBounds == entry.finiteBounds else {
          throw ConformanceGovernanceError.inconsistentReference(record: entry.id, field: "case category or bounds")
        }
      }
      for divergenceID in entry.linkedDivergenceIDs where !divergenceIDs.contains(divergenceID) {
        throw ConformanceGovernanceError.unknownDivergenceID(divergenceID)
      }
    }
    guard divergenceIDs.isSubset(of: Set(entries.flatMap(\.linkedDivergenceIDs))) else {
      throw ConformanceGovernanceError.invalidField(record: "support surface", field: "unlinked divergence")
    }
  }
}

public struct PublicWorkflowAdmissionEntry: Equatable, Codable, Sendable {
  public let supportID: String
  public let decision: PublicWorkflowSupportDecision
  public let reasonCodes: [PublicWorkflowReasonCode]
  public let mandatoryCaseIDs: [String]
  public let divergenceIDs: [String]
  public let evidence: [PublicWorkflowCaseEvidence]
  public let platformEvidence: [PublicWorkflowPlatformEvidence]

  public init(
    supportID: String, decision: PublicWorkflowSupportDecision, reasonCodes: [PublicWorkflowReasonCode],
    mandatoryCaseIDs: [String], divergenceIDs: [String], evidence: [PublicWorkflowCaseEvidence] = [],
    platformEvidence: [PublicWorkflowPlatformEvidence] = []
  ) throws {
    self.supportID = supportID
    self.decision = decision
    self.reasonCodes = reasonCodes
    self.mandatoryCaseIDs = mandatoryCaseIDs
    self.divergenceIDs = divergenceIDs
    self.evidence = evidence
    self.platformEvidence = platformEvidence
    try validate()
  }

  public func validate() throws {
    guard !supportID.isEmpty, !mandatoryCaseIDs.isEmpty, Set(reasonCodes).count == reasonCodes.count,
          Set(mandatoryCaseIDs).count == mandatoryCaseIDs.count, Set(divergenceIDs).count == divergenceIDs.count else {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "admission entry")
    }
    try evidence.forEach { try $0.validate() }
    try platformEvidence.forEach { try $0.validate() }
    if decision == .admitted {
      guard reasonCodes.isEmpty, Set(evidence.map(\.caseID)) == Set(mandatoryCaseIDs),
            evidence.allSatisfy({ $0.status == .complete && $0.outcome == .exact }),
            Set(evidence.map(\.correlation.caseID)).count == evidence.count,
            platformEvidence.allSatisfy({ $0.status == .succeeded }) else {
        throw ConformanceGovernanceError.invalidField(record: supportID, field: "admitted evidence")
      }
    } else if reasonCodes.isEmpty {
      throw ConformanceGovernanceError.invalidField(record: supportID, field: "reasonCodes")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case supportID, decision, reasonCodes, mandatoryCaseIDs, divergenceIDs, evidence, platformEvidence }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(supportID: try container.decode(String.self, forKey: .supportID), decision: try container.decode(PublicWorkflowSupportDecision.self, forKey: .decision), reasonCodes: try container.decode([PublicWorkflowReasonCode].self, forKey: .reasonCodes), mandatoryCaseIDs: try container.decode([String].self, forKey: .mandatoryCaseIDs), divergenceIDs: try container.decode([String].self, forKey: .divergenceIDs), evidence: try container.decodeIfPresent([PublicWorkflowCaseEvidence].self, forKey: .evidence) ?? [], platformEvidence: try container.decodeIfPresent([PublicWorkflowPlatformEvidence].self, forKey: .platformEvidence) ?? [])
  }
}

public struct PublicWorkflowAdmission: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowAdmission"
  public let schema: String
  public let reportID: UUID
  public let gateRunID: UUID
  public let entries: [PublicWorkflowAdmissionEntry]
  public let admittedBounds: [String: CoreFiniteBounds]
  public let unexplainedDivergenceCount: Int

  public init(gateRunID: UUID, entries: [PublicWorkflowAdmissionEntry], admittedBounds: [String: CoreFiniteBounds] = [:], unexplainedDivergenceCount: Int = 0) throws {
    try self.init(schema: Self.schema, reportID: UUID(), gateRunID: gateRunID, entries: entries, admittedBounds: admittedBounds, unexplainedDivergenceCount: unexplainedDivergenceCount)
  }

  public init(schema: String, reportID: UUID, gateRunID: UUID, entries: [PublicWorkflowAdmissionEntry], admittedBounds: [String: CoreFiniteBounds], unexplainedDivergenceCount: Int) throws {
    guard schema == Self.schema, !entries.isEmpty, unexplainedDivergenceCount >= 0 else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "report")
    }
    var ids = Set<String>()
    for entry in entries {
      try entry.validate()
      guard ids.insert(entry.supportID).inserted else { throw ConformanceGovernanceError.duplicateID(kind: "admission", id: entry.supportID) }
      if entry.decision == .admitted {
        guard let bounds = admittedBounds[entry.supportID] else { throw ConformanceGovernanceError.invalidField(record: entry.supportID, field: "admitted bounds") }
        try bounds.validate()
      }
    }
    guard Set(admittedBounds.keys).isSubset(of: ids) else { throw ConformanceGovernanceError.invalidField(record: "admission", field: "admitted bounds") }
    self.schema = schema
    self.reportID = reportID
    self.gateRunID = gateRunID
    self.entries = entries
    self.admittedBounds = admittedBounds
    self.unexplainedDivergenceCount = unexplainedDivergenceCount
  }

  public var finalExitClass: PublicWorkflowAdmissionExitClass {
    if entries.contains(where: { $0.decision == .unavailable }) { return .unavailable }
    if entries.contains(where: { $0.reasonCodes.contains(.missingEvidence) || $0.reasonCodes.contains(.partialEvidence) || $0.reasonCodes.contains(.foreignRun) || $0.reasonCodes.contains(.staleEvidence) || $0.reasonCodes.contains(.mixedRunEvidence) || $0.reasonCodes.contains(.incompletePins) }) { return .unavailable }
    return entries.contains(where: { $0.decision == .blocked }) || unexplainedDivergenceCount > 0 ? .blocked : .success
  }

  public func validate(supportSurface: PublicWorkflowSupportSurface, cases: PublicWorkflowCases, ledger: PublicWorkflowDivergenceLedger) throws {
    try supportSurface.validate(cases: cases, ledger: ledger)
    let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.supportID, $0) })
    let caseIDs = Set(cases.cases.map(\.id))
    let divergenceIDs = Set(ledger.records.map(\.id))
    let derivedUnexplainedCount = ledger.unexplainedRecords.count
    guard unexplainedDivergenceCount == derivedUnexplainedCount else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "unexplained divergence count")
    }
    guard Set(entriesByID.keys) == Set(supportSurface.entries.map(\.id)) else {
      throw ConformanceGovernanceError.invalidField(record: "admission", field: "support entry coverage")
    }
    for support in supportSurface.entries {
      guard let entry = entriesByID[support.id], Set(entry.mandatoryCaseIDs) == Set(support.mandatoryCaseIDs), Set(entry.divergenceIDs) == Set(support.linkedDivergenceIDs) else {
        throw ConformanceGovernanceError.inconsistentReference(record: support.id, field: "admission")
      }
      guard Set(entry.mandatoryCaseIDs).isSubset(of: caseIDs), Set(entry.divergenceIDs).isSubset(of: divergenceIDs) else {
        throw ConformanceGovernanceError.inconsistentReference(record: support.id, field: "references")
      }
      switch support.requestedStatus {
      case .requested:
        guard entry.decision != .unsupported else {
          throw ConformanceGovernanceError.invalidField(record: support.id, field: "requested entry downgraded")
        }
      case .unsupported:
        guard entry.decision == .unsupported, entry.reasonCodes == [.explicitlyUnsupported] else {
          throw ConformanceGovernanceError.invalidField(record: support.id, field: "unsupported support state")
        }
      case .blocked:
        guard entry.decision == .blocked, entry.reasonCodes == [.declaredBlocked] else {
          throw ConformanceGovernanceError.invalidField(record: support.id, field: "blocked support state")
        }
      }
      if entry.decision == .admitted {
        guard derivedUnexplainedCount == 0,
              admittedBounds[support.id] == support.finiteBounds,
              entry.evidence.allSatisfy({ evidence in
                guard let declaration = cases.cases.first(where: { $0.id == evidence.caseID }) else { return false }
                return evidence.execution.authority == .candidate && evidence.correlation.gateRunID == gateRunID
                  && evidence.fixtureBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: evidence.correlation.fixtureRunID, evidence: evidence.fixture)
                  && evidence.comparisonBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: evidence.correlation.comparisonRunID, evidence: evidence.comparison)
                  && evidence.provenanceBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: evidence.correlation.comparisonRunID, evidence: evidence.provenance)
              }),
              entry.platformEvidence.allSatisfy({ platform in
                guard support.mandatoryCaseIDs.contains(platform.correlation.caseID),
                      let declaration = cases.cases.first(where: { $0.id == platform.correlation.caseID }) else { return false }
                return platform.execution.authority == .candidate && platform.correlation.gateRunID == gateRunID
                  && platform.fixtureBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: platform.correlation.platformRunID, evidence: platform.fixture)
                  && platform.stdoutBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: platform.correlation.platformRunID, evidence: platform.stdout)
                  && platform.stderrBinding.matches(declaration, gateRunID: gateRunID,
                    expectedRunID: platform.correlation.platformRunID, evidence: platform.stderr)
              }),
              Set(entry.platformEvidence.map(\.platform)).isSuperset(of: Set(support.requiredPlatforms)) else {
          throw ConformanceGovernanceError.invalidField(record: support.id, field: "correlated hosted workflow evidence")
        }
      } else {
        try validateReasonCodes(entry, support: support, hasUnexplainedDivergence: derivedUnexplainedCount > 0)
      }
    }
  }

  private func validateReasonCodes(
    _ entry: PublicWorkflowAdmissionEntry, support: PublicWorkflowSupportSurfaceEntry,
    hasUnexplainedDivergence: Bool
  ) throws {
    let supportedReasons: Set<PublicWorkflowReasonCode>
    switch entry.decision {
    case .admitted:
      return
    case .unsupported:
      supportedReasons = support.requestedStatus == .unsupported ? [.explicitlyUnsupported] : []
    case .blocked:
      var reasons: Set<PublicWorkflowReasonCode> = []
      if support.requestedStatus == .blocked { reasons.insert(.declaredBlocked) }
      if hasUnexplainedDivergence { reasons.insert(.unexplainedDivergence) }
      if entry.evidence.contains(where: { $0.outcome == .difference }) { reasons.insert(.nonExactComparison) }
      if entry.divergenceIDs.isEmpty == false { reasons.insert(.unresolvedDivergence) }
      supportedReasons = reasons
    case .unavailable:
      var reasons: Set<PublicWorkflowReasonCode> = []
      if entry.evidence.isEmpty { reasons.insert(.missingEvidence) }
      if entry.evidence.contains(where: { $0.status == .partial }) { reasons.insert(.partialEvidence) }
      if entry.evidence.contains(where: { $0.status == .unavailable }) { reasons.insert(.missingEvidence) }
      if entry.evidence.contains(where: { $0.execution.authority == .diagnostic }) { reasons.insert(.nonCIExecution) }
      if entry.platformEvidence.contains(where: { $0.status == .unavailable }) { reasons.insert(.unsupportedPlatform) }
      if entry.platformEvidence.contains(where: { $0.status == .failed }) { reasons.insert(.platformValidationFailed) }
      if entry.platformEvidence.contains(where: { $0.execution.authority == .diagnostic }) { reasons.insert(.nonCIExecution) }
      supportedReasons = reasons
    }
    guard Set(entry.reasonCodes).isSubset(of: supportedReasons), !supportedReasons.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: entry.supportID, field: "unbacked reason codes")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, reportID, gateRunID, entries, admittedBounds, unexplainedDivergenceCount }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), reportID: try container.decode(UUID.self, forKey: .reportID), gateRunID: try container.decode(UUID.self, forKey: .gateRunID), entries: try container.decode([PublicWorkflowAdmissionEntry].self, forKey: .entries), admittedBounds: try container.decodeIfPresent([String: CoreFiniteBounds].self, forKey: .admittedBounds) ?? [:], unexplainedDivergenceCount: try container.decode(Int.self, forKey: .unexplainedDivergenceCount))
  }
}
