import Foundation

public struct TemporalComparison: Equatable, Codable, Sendable {
  public static let schema = "TemporalComparison"

  public let schema: String
  public let caseID: String
  public let configuration: TemporalSymmetryConfiguration
  public let correlation: TemporalSymmetryCaseRunCorrelation
  public let outcome: TemporalSymmetryOutcome
  public let swiftResult: TemporalPropertyResult
  public let tlcResult: TemporalPropertyResult
  public let swiftEvidence: CoreEvidenceReference
  public let tlcEvidence: CoreEvidenceReference
  public let completeGraphEvidence: TemporalCompleteGraphEvidence?
  public let diagnosticCode: TemporalSymmetryDiagnosticCode

  public init(
    caseID: String,
    configuration: TemporalSymmetryConfiguration,
    correlation: TemporalSymmetryCaseRunCorrelation,
    outcome: TemporalSymmetryOutcome,
    swiftResult: TemporalPropertyResult,
    tlcResult: TemporalPropertyResult,
    swiftEvidence: CoreEvidenceReference,
    tlcEvidence: CoreEvidenceReference,
    completeGraphEvidence: TemporalCompleteGraphEvidence? = nil,
    diagnosticCode: TemporalSymmetryDiagnosticCode
  ) throws {
    self.schema = Self.schema
    self.caseID = caseID
    self.configuration = configuration
    self.correlation = correlation
    self.outcome = outcome
    self.swiftResult = swiftResult
    self.tlcResult = tlcResult
    self.swiftEvidence = swiftEvidence
    self.tlcEvidence = tlcEvidence
    self.completeGraphEvidence = completeGraphEvidence
    self.diagnosticCode = diagnosticCode
    try validate()
  }

  public func validate() throws {
    try configuration.validate()
    try swiftEvidence.validate()
    try tlcEvidence.validate()
    try completeGraphEvidence?.validate()
    try swiftResult.validate()
    try tlcResult.validate()
    guard !caseID.isEmpty, correlation.caseID == caseID, configuration.property != nil,
          !configuration.symmetryEnabled else {
      throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "temporal comparison")
    }
    if let declared = configuration.completeGraphPass {
      guard let evidence = completeGraphEvidence,
            evidence.configuration == declared.configuration else {
        throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "complete graph evidence")
      }
    } else if completeGraphEvidence != nil {
      throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "unexpected complete graph evidence")
    }
    switch outcome {
    case .exact:
      guard swiftResult.availability == .evaluated, tlcResult.availability == .evaluated,
            swiftResult.outcome == tlcResult.outcome,
            swiftResult.graphID == tlcResult.graphID,
            swiftResult.initialStateIDs == tlcResult.initialStateIDs,
            diagnosticCode == .exactAgreement else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "exact temporal result")
      }
    case .unavailable:
      guard swiftResult.availability == .unavailable || tlcResult.availability == .unavailable,
            diagnosticCode == .temporalEvidenceUnavailable else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "unavailable temporal result")
      }
    case .difference:
      let different = swiftResult.availability != tlcResult.availability
        || swiftResult.outcome != tlcResult.outcome
        || swiftResult.graphID != tlcResult.graphID
        || swiftResult.initialStateIDs != tlcResult.initialStateIDs
      guard different, diagnosticCode != .exactAgreement,
            diagnosticCode != .temporalEvidenceUnavailable else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "temporal difference diagnostic")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, caseID, configuration, correlation, outcome, swiftResult, tlcResult, swiftEvidence, tlcEvidence
    case completeGraphEvidence, diagnosticCode
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .schema) == Self.schema else {
      throw ConformanceGovernanceError.invalidSchema("TemporalComparison")
    }
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      configuration: container.decode(TemporalSymmetryConfiguration.self, forKey: .configuration),
      correlation: container.decode(TemporalSymmetryCaseRunCorrelation.self, forKey: .correlation),
      outcome: container.decode(TemporalSymmetryOutcome.self, forKey: .outcome),
      swiftResult: container.decode(TemporalPropertyResult.self, forKey: .swiftResult),
      tlcResult: container.decode(TemporalPropertyResult.self, forKey: .tlcResult),
      swiftEvidence: container.decode(CoreEvidenceReference.self, forKey: .swiftEvidence),
      tlcEvidence: container.decode(CoreEvidenceReference.self, forKey: .tlcEvidence),
      completeGraphEvidence: try container.decodeIfPresent(TemporalCompleteGraphEvidence.self, forKey: .completeGraphEvidence),
      diagnosticCode: container.decode(TemporalSymmetryDiagnosticCode.self, forKey: .diagnosticCode))
  }
}

public struct SymmetryOrbit: Equatable, Codable, Sendable {
  public let members: [String]
  public let semanticRepresentative: String
  public let swiftExecutableRepresentative: String
  public let tlcExecutableRepresentative: String
  public var size: Int { members.count }

  public init(
    members: [String],
    semanticRepresentative: String,
    swiftExecutableRepresentative: String,
    tlcExecutableRepresentative: String
  ) throws {
    guard !members.isEmpty, Set(members).count == members.count, members.allSatisfy({ !$0.isEmpty }),
          semanticRepresentative == members.sorted().first,
          members.contains(swiftExecutableRepresentative), members.contains(tlcExecutableRepresentative) else {
      throw ConformanceGovernanceError.invalidField(record: "orbit", field: "members or representative")
    }
    self.members = members.sorted()
    self.semanticRepresentative = semanticRepresentative
    self.swiftExecutableRepresentative = swiftExecutableRepresentative
    self.tlcExecutableRepresentative = tlcExecutableRepresentative
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case members, semanticRepresentative, swiftExecutableRepresentative, tlcExecutableRepresentative
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      members: container.decode([String].self, forKey: .members),
      semanticRepresentative: container.decode(String.self, forKey: .semanticRepresentative),
      swiftExecutableRepresentative: container.decode(String.self, forKey: .swiftExecutableRepresentative),
      tlcExecutableRepresentative: container.decode(String.self, forKey: .tlcExecutableRepresentative))
  }
}

public struct SymmetryExploration: Equatable, Codable, Sendable {
  public let engine: SymmetryExplorationEngine
  public let reduced: Bool
  public let runID: UUID
  public let graphID: String
  public let initialStateIDs: [String]
  public let stateIDs: [String]
  public let transitions: [SymmetryRawTransitionWitness]
  public let declaredConfigurationSHA256: String
  public let graphEvidence: CoreEvidenceReference
  public let invariantOutcome: SymmetryApplicableOutcome
  public let deadlockOutcome: SymmetryApplicableOutcome

  public init(
    engine: SymmetryExplorationEngine,
    reduced: Bool,
    runID: UUID,
    graphID: String,
    initialStateIDs: [String],
    stateIDs: [String],
    transitions: [SymmetryRawTransitionWitness],
    declaredConfigurationSHA256: String,
    graphEvidence: CoreEvidenceReference,
    invariantOutcome: SymmetryApplicableOutcome,
    deadlockOutcome: SymmetryApplicableOutcome
  ) throws {
    self.engine = engine
    self.reduced = reduced
    self.runID = runID
    self.graphID = graphID
    self.initialStateIDs = initialStateIDs.sorted()
    self.stateIDs = stateIDs.sorted()
    self.transitions = transitions.sorted()
    self.declaredConfigurationSHA256 = declaredConfigurationSHA256
    self.graphEvidence = graphEvidence
    self.invariantOutcome = invariantOutcome
    self.deadlockOutcome = deadlockOutcome
    try validate()
  }

  public func validate() throws {
    try graphEvidence.validate()
    guard !graphID.isEmpty, TLCReferencePin.isSHA256(declaredConfigurationSHA256), !initialStateIDs.isEmpty,
          Set(initialStateIDs).count == initialStateIDs.count,
          initialStateIDs.allSatisfy({ !$0.isEmpty }), !stateIDs.isEmpty,
          Set(stateIDs).count == stateIDs.count, stateIDs.allSatisfy({ !$0.isEmpty }),
          Set(initialStateIDs).isSubset(of: Set(stateIDs)),
          Set(transitions).count == transitions.count,
          transitions.allSatisfy({ $0.engine == engine && stateIDs.contains($0.sourceStateID) && stateIDs.contains($0.targetStateID) }) else {
      throw ConformanceGovernanceError.invalidField(record: "symmetry exploration", field: "graph or initial states")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case engine, reduced, runID, graphID, initialStateIDs, stateIDs, transitions
    case declaredConfigurationSHA256, graphEvidence, invariantOutcome, deadlockOutcome
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      engine: container.decode(SymmetryExplorationEngine.self, forKey: .engine),
      reduced: container.decode(Bool.self, forKey: .reduced),
      runID: container.decode(UUID.self, forKey: .runID),
      graphID: container.decode(String.self, forKey: .graphID),
      initialStateIDs: container.decode([String].self, forKey: .initialStateIDs),
      stateIDs: container.decode([String].self, forKey: .stateIDs),
      transitions: container.decode([SymmetryRawTransitionWitness].self, forKey: .transitions),
      declaredConfigurationSHA256: container.decode(String.self, forKey: .declaredConfigurationSHA256),
      graphEvidence: container.decode(CoreEvidenceReference.self, forKey: .graphEvidence),
      invariantOutcome: container.decode(SymmetryApplicableOutcome.self, forKey: .invariantOutcome),
      deadlockOutcome: container.decode(SymmetryApplicableOutcome.self, forKey: .deadlockOutcome))
  }
}

public struct SymmetryRawTransitionWitness: Hashable, Codable, Sendable, Comparable {
  public let engine: SymmetryExplorationEngine
  public let sourceStateID: String
  public let action: String
  public let targetStateID: String
  public let occurrences: Int

  public init(
    engine: SymmetryExplorationEngine,
    sourceStateID: String,
    action: String,
    targetStateID: String,
    occurrences: Int
  ) throws {
    guard !sourceStateID.isEmpty, !action.isEmpty, !targetStateID.isEmpty, occurrences > 0 else {
      throw ConformanceGovernanceError.invalidField(record: "raw transition", field: "witness")
    }
    self.engine = engine
    self.sourceStateID = sourceStateID
    self.action = action
    self.targetStateID = targetStateID
    self.occurrences = occurrences
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.engine != rhs.engine { return lhs.engine.rawValue < rhs.engine.rawValue }
    if lhs.sourceStateID != rhs.sourceStateID { return lhs.sourceStateID < rhs.sourceStateID }
    if lhs.action != rhs.action { return lhs.action < rhs.action }
    if lhs.targetStateID != rhs.targetStateID { return lhs.targetStateID < rhs.targetStateID }
    return lhs.occurrences < rhs.occurrences
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case engine, sourceStateID, action, targetStateID, occurrences }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      engine: container.decode(SymmetryExplorationEngine.self, forKey: .engine),
      sourceStateID: container.decode(String.self, forKey: .sourceStateID),
      action: container.decode(String.self, forKey: .action),
      targetStateID: container.decode(String.self, forKey: .targetStateID),
      occurrences: container.decode(Int.self, forKey: .occurrences))
  }
}

public struct SymmetryQuotientTransition: Hashable, Codable, Sendable, Comparable {
  public let sourceRepresentative: String
  public let action: String
  public let targetRepresentative: String

  public init(sourceRepresentative: String, action: String, targetRepresentative: String) throws {
    guard !sourceRepresentative.isEmpty, !action.isEmpty, !targetRepresentative.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: "quotient transition", field: "transition")
    }
    self.sourceRepresentative = sourceRepresentative
    self.action = action
    self.targetRepresentative = targetRepresentative
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.sourceRepresentative != rhs.sourceRepresentative {
      return lhs.sourceRepresentative < rhs.sourceRepresentative
    }
    if lhs.action != rhs.action { return lhs.action < rhs.action }
    return lhs.targetRepresentative < rhs.targetRepresentative
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case sourceRepresentative, action, targetRepresentative }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      sourceRepresentative: container.decode(String.self, forKey: .sourceRepresentative),
      action: container.decode(String.self, forKey: .action),
      targetRepresentative: container.decode(String.self, forKey: .targetRepresentative))
  }
}

public struct SymmetryOrbitComparison: Equatable, Codable, Sendable {
  public static let schema = "SymmetryOrbitComparison"

  public let schema: String
  public let caseID: String
  public let configuration: TemporalSymmetryConfiguration
  public let correlation: TemporalSymmetryCaseRunCorrelation
  public let outcome: TemporalSymmetryOutcome
  public let swiftRaw: SymmetryExploration
  public let swiftReduced: SymmetryExploration
  public let tlcRaw: SymmetryExploration
  public let tlcReduced: SymmetryExploration
  public let configurationEvidence: CoreEvidenceReference
  public let quotientEvidence: CoreEvidenceReference
  public let orbits: [SymmetryOrbit]
  public let rawTransitionWitnesses: [SymmetryRawTransitionWitness]
  public let quotientTransitions: [SymmetryQuotientTransition]
  public let diagnosticCode: TemporalSymmetryDiagnosticCode

  public init(
    caseID: String,
    configuration: TemporalSymmetryConfiguration,
    correlation: TemporalSymmetryCaseRunCorrelation,
    outcome: TemporalSymmetryOutcome,
    swiftRaw: SymmetryExploration,
    swiftReduced: SymmetryExploration,
    tlcRaw: SymmetryExploration,
    tlcReduced: SymmetryExploration,
    configurationEvidence: CoreEvidenceReference,
    quotientEvidence: CoreEvidenceReference,
    orbits: [SymmetryOrbit],
    rawTransitionWitnesses: [SymmetryRawTransitionWitness],
    quotientTransitions: [SymmetryQuotientTransition],
    diagnosticCode: TemporalSymmetryDiagnosticCode
  ) throws {
    self.schema = Self.schema
    self.caseID = caseID
    self.configuration = configuration
    self.correlation = correlation
    self.outcome = outcome
    self.swiftRaw = swiftRaw
    self.swiftReduced = swiftReduced
    self.tlcRaw = tlcRaw
    self.tlcReduced = tlcReduced
    self.configurationEvidence = configurationEvidence
    self.quotientEvidence = quotientEvidence
    self.orbits = orbits
    self.rawTransitionWitnesses = rawTransitionWitnesses
    self.quotientTransitions = quotientTransitions.sorted()
    self.diagnosticCode = diagnosticCode
    try validate()
  }

  public func validate() throws {
    try configuration.validate()
    try swiftRaw.validate()
    try swiftReduced.validate()
    try tlcRaw.validate()
    try tlcReduced.validate()
    try configurationEvidence.validate()
    try quotientEvidence.validate()
    let members = orbits.flatMap(\.members)
    guard !caseID.isEmpty, correlation.caseID == caseID, configuration.property == nil,
          configuration.symmetryEnabled, !orbits.isEmpty, Set(members).count == members.count else {
      throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "orbit comparison")
    }
    let explorations = [swiftRaw, swiftReduced, tlcRaw, tlcReduced]
    guard Set(explorations.map { "\($0.engine.rawValue):\($0.reduced)" }).count == 4,
          swiftRaw.engine == .swift, !swiftRaw.reduced,
          swiftReduced.engine == .swift, swiftReduced.reduced,
          tlcRaw.engine == .tlc, !tlcRaw.reduced,
          tlcReduced.engine == .tlc, tlcReduced.reduced else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "paired explorations")
    }
    guard swiftRaw.runID == correlation.swiftRunID,
          tlcRaw.runID == correlation.tlcRunID,
          Set([
            correlation.runID, correlation.comparisonRunID, swiftRaw.runID,
            swiftReduced.runID, tlcRaw.runID, tlcReduced.runID
          ]).count == 6 else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "exploration run correlation")
    }
    guard Set(explorations.map(\.declaredConfigurationSHA256)).count == 1 else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "configuration equivalence")
    }
    let rawStateIDs = Set(orbits.flatMap(\.members))
    let representatives = Set(orbits.map(\.semanticRepresentative))
    let orbitPartitionMatches = Set(swiftRaw.stateIDs) == rawStateIDs
      && Set(tlcRaw.stateIDs) == rawStateIDs
      && Set(swiftReduced.stateIDs) == representatives
      && Set(tlcReduced.stateIDs) == representatives
    let expectedRawWitnesses = Set(swiftRaw.transitions + tlcRaw.transitions)
    guard Set(rawTransitionWitnesses) == expectedRawWitnesses, !quotientTransitions.isEmpty,
          Set(quotientTransitions).count == quotientTransitions.count,
          quotientTransitions.allSatisfy({ transition in
            orbits.contains { $0.semanticRepresentative == transition.sourceRepresentative }
              && orbits.contains { $0.semanticRepresentative == transition.targetRepresentative }
          }) else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "orbit witnesses or quotient")
    }
    let quotient = Set(quotientTransitions)
    let quotientMatches = mappedQuotient(swiftRaw.transitions) == quotient
      && mappedQuotient(tlcRaw.transitions) == quotient
      && reducedRelation(swiftReduced) == quotient
      && reducedRelation(tlcReduced) == quotient
    let applicableOutcomesAgree = [swiftRaw.invariantOutcome, swiftReduced.invariantOutcome, tlcRaw.invariantOutcome, tlcReduced.invariantOutcome]
      .allSatisfy({ $0 == swiftRaw.invariantOutcome })
      && [swiftRaw.deadlockOutcome, swiftReduced.deadlockOutcome, tlcRaw.deadlockOutcome, tlcReduced.deadlockOutcome]
      .allSatisfy({ $0 == swiftRaw.deadlockOutcome })
    switch outcome {
    case .exact:
      guard orbitPartitionMatches else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "complete orbit partition")
      }
      guard quotientMatches else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "quotient completeness")
      }
      guard applicableOutcomesAgree, diagnosticCode == .exactAgreement else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "exact applicable outcomes")
      }
    case .difference:
      let diagnosticMatchesDifference: Bool
      switch diagnosticCode {
      case .orbitDifference:
        diagnosticMatchesDifference = !orbitPartitionMatches
      case .graphIdentityDifference:
        diagnosticMatchesDifference = !quotientMatches
      case .applicableOutcomeDifference, .propertyOutcomeDifference:
        diagnosticMatchesDifference = !applicableOutcomesAgree
      default:
        diagnosticMatchesDifference = false
      }
      guard diagnosticMatchesDifference else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "symmetry difference diagnostic")
      }
    case .unavailable:
      guard diagnosticCode == .orbitEvidenceUnavailable else {
        throw ConformanceGovernanceError.invalidField(record: caseID, field: "unavailable orbit result")
      }
    }
  }

  private func mappedQuotient(
    _ transitions: [SymmetryRawTransitionWitness]
  ) -> Set<SymmetryQuotientTransition>? {
    let orbitByMember = Dictionary(uniqueKeysWithValues: orbits.flatMap { orbit in
      orbit.members.map { ($0, orbit.semanticRepresentative) }
    })
    let mapped = transitions.compactMap { witness -> SymmetryQuotientTransition? in
      guard let source = orbitByMember[witness.sourceStateID], let target = orbitByMember[witness.targetStateID] else {
        return nil
      }
      return try? SymmetryQuotientTransition(
        sourceRepresentative: source, action: witness.action, targetRepresentative: target)
    }
    guard mapped.count == transitions.count else { return nil }
    return Set(mapped)
  }

  private func reducedRelation(_ exploration: SymmetryExploration) -> Set<SymmetryQuotientTransition>? {
    let representatives = Set(orbits.map(\.semanticRepresentative))
    let mapped = exploration.transitions.compactMap { transition -> SymmetryQuotientTransition? in
      guard representatives.contains(transition.sourceStateID), representatives.contains(transition.targetStateID) else {
        return nil
      }
      return try? SymmetryQuotientTransition(
        sourceRepresentative: transition.sourceStateID, action: transition.action, targetRepresentative: transition.targetStateID)
    }
    guard mapped.count == exploration.transitions.count else { return nil }
    return Set(mapped)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, caseID, configuration, correlation, outcome, swiftRaw, swiftReduced, tlcRaw, tlcReduced
    case configurationEvidence, quotientEvidence, orbits, rawTransitionWitnesses, quotientTransitions, diagnosticCode
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .schema) == Self.schema else {
      throw ConformanceGovernanceError.invalidSchema("SymmetryOrbitComparison")
    }
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      configuration: container.decode(TemporalSymmetryConfiguration.self, forKey: .configuration),
      correlation: container.decode(TemporalSymmetryCaseRunCorrelation.self, forKey: .correlation),
      outcome: container.decode(TemporalSymmetryOutcome.self, forKey: .outcome),
      swiftRaw: container.decode(SymmetryExploration.self, forKey: .swiftRaw),
      swiftReduced: container.decode(SymmetryExploration.self, forKey: .swiftReduced),
      tlcRaw: container.decode(SymmetryExploration.self, forKey: .tlcRaw),
      tlcReduced: container.decode(SymmetryExploration.self, forKey: .tlcReduced),
      configurationEvidence: container.decode(CoreEvidenceReference.self, forKey: .configurationEvidence),
      quotientEvidence: container.decode(CoreEvidenceReference.self, forKey: .quotientEvidence),
      orbits: container.decode([SymmetryOrbit].self, forKey: .orbits),
      rawTransitionWitnesses: container.decode([SymmetryRawTransitionWitness].self, forKey: .rawTransitionWitnesses),
      quotientTransitions: container.decode([SymmetryQuotientTransition].self, forKey: .quotientTransitions),
      diagnosticCode: container.decode(TemporalSymmetryDiagnosticCode.self, forKey: .diagnosticCode))
  }
}
