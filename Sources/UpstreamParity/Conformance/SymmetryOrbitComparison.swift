import Foundation

public enum SymmetryOrbitDifferenceKindV1: String, Codable, Sendable {
  case rawStateSet
  case reducedRepresentative
  case quotientTransition
  case invariantOutcome
  case deadlockOutcome
}

public struct SymmetryOrbitDifferenceV1: Equatable, Codable, Sendable {
  public let kind: SymmetryOrbitDifferenceKindV1
  public let detail: String

  public init(kind: SymmetryOrbitDifferenceKindV1, detail: String) throws {
    guard !detail.isEmpty else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "symmetry difference", field: "detail")
    }
    self.kind = kind
    self.detail = detail
  }
}

public enum SymmetryOrbitComparisonResultV1: Equatable, Sendable {
  case exact(SymmetryOrbitComparisonV1)
  case difference([SymmetryOrbitDifferenceV1])
}

public struct SymmetryOrbitComparisonInputV1: Sendable {
  public let caseID: String
  public let configuration: TemporalSymmetryConfigurationV1
  public let correlation: TemporalSymmetryCaseRunCorrelationV1
  public let swiftRaw: SymmetryExplorationV1
  public let swiftReduced: SymmetryExplorationV1
  public let tlcRaw: SymmetryExplorationV1
  public let tlcReduced: SymmetryExplorationV1
  public let swiftRawRun: CanonicalRunV1
  public let swiftReducedRun: CanonicalRunV1
  public let tlcRawRun: CanonicalRunV1
  public let tlcReducedRun: CanonicalRunV1
  public let configurationEvidence: CoreEvidenceReferenceV1
  public let quotientEvidence: CoreEvidenceReferenceV1
  public let permutations: [SymmetryPermutationV1]

  public init(
    caseID: String,
    configuration: TemporalSymmetryConfigurationV1,
    correlation: TemporalSymmetryCaseRunCorrelationV1,
    swiftRaw: SymmetryExplorationV1,
    swiftReduced: SymmetryExplorationV1,
    tlcRaw: SymmetryExplorationV1,
    tlcReduced: SymmetryExplorationV1,
    swiftRawRun: CanonicalRunV1,
    swiftReducedRun: CanonicalRunV1,
    tlcRawRun: CanonicalRunV1,
    tlcReducedRun: CanonicalRunV1,
    configurationEvidence: CoreEvidenceReferenceV1,
    quotientEvidence: CoreEvidenceReferenceV1,
    permutations: [SymmetryPermutationV1]
  ) throws {
    self.caseID = caseID
    self.configuration = configuration
    self.correlation = correlation
    self.swiftRaw = swiftRaw
    self.swiftReduced = swiftReduced
    self.tlcRaw = tlcRaw
    self.tlcReduced = tlcReduced
    self.swiftRawRun = swiftRawRun
    self.swiftReducedRun = swiftReducedRun
    self.tlcRawRun = tlcRawRun
    self.tlcReducedRun = tlcReducedRun
    self.configurationEvidence = configurationEvidence
    self.quotientEvidence = quotientEvidence
    self.permutations = permutations
    try validate()
  }

  public func validate() throws {
    try configuration.validate()
    try configurationEvidence.validate()
    try quotientEvidence.validate()
    guard !caseID.isEmpty, correlation.caseID == caseID, configuration.property == nil,
          configuration.symmetryEnabled, !permutations.isEmpty else {
      throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: caseID, field: "symmetry input")
    }
    let explorations = [swiftRaw, swiftReduced, tlcRaw, tlcReduced]
    guard Set(explorations.map { "\($0.engine.rawValue):\($0.reduced)" }).count == 4,
          swiftRaw.runID == correlation.swiftRunID,
          tlcRaw.runID == correlation.tlcRunID,
          Set([correlation.gateRunID, correlation.comparisonRunID, swiftRaw.runID, swiftReduced.runID,
               tlcRaw.runID, tlcReduced.runID]).count == 6,
          Set(explorations.map(\.declaredConfigurationSHA256)).count == 1 else {
      throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: caseID, field: "symmetry pair configuration")
    }
  }
}

public struct SymmetryOrbitComparatorV1: Sendable {
  public init() {}

  public func compare(_ input: SymmetryOrbitComparisonInputV1) throws -> SymmetryOrbitComparisonResultV1 {
    try validate(input.swiftRaw, against: input.swiftRawRun)
    try validate(input.swiftReduced, against: input.swiftReducedRun)
    try validate(input.tlcRaw, against: input.tlcRawRun)
    try validate(input.tlcReduced, against: input.tlcReducedRun)
    let swiftRawStates = Set(input.swiftRawRun.graph.states.keys)
    let tlcRawStates = Set(input.tlcRawRun.graph.states.keys)
    guard swiftRawStates == tlcRawStates else {
      return .difference([try SymmetryOrbitDifferenceV1(kind: .rawStateSet, detail: "Swift and TLC raw state sets differ")])
    }
    let derivation = try SymmetryOrbitDerivationV1(
      states: Array(input.swiftRawRun.graph.states.values), permutations: input.permutations)
    let swiftRepresentatives = try reducedRepresentatives(
      input.swiftReducedRun, engine: .swift, derivation: derivation)
    let tlcRepresentatives = try reducedRepresentatives(
      input.tlcReducedRun, engine: .tlc, derivation: derivation)
    let expectedQuotient = quotientTransitions(input.swiftRawRun, derivation: derivation)
    let tlcRawQuotient = quotientTransitions(input.tlcRawRun, derivation: derivation)
    let swiftReducedQuotient = quotientTransitions(input.swiftReducedRun, derivation: derivation)
    let tlcReducedQuotient = quotientTransitions(input.tlcReducedRun, derivation: derivation)

    var differences: [SymmetryOrbitDifferenceV1] = []
    if swiftRepresentatives != tlcRepresentatives {
      differences.append(try SymmetryOrbitDifferenceV1(
        kind: .reducedRepresentative, detail: "Swift and TLC reduced representatives differ by orbit"))
    }
    if expectedQuotient != tlcRawQuotient || expectedQuotient != swiftReducedQuotient
      || expectedQuotient != tlcReducedQuotient {
      differences.append(try SymmetryOrbitDifferenceV1(
        kind: .quotientTransition, detail: "Raw or reduced quotient transitions differ"))
    }
    if !invariantOutcomesAgree(input) {
      differences.append(try SymmetryOrbitDifferenceV1(
        kind: .invariantOutcome, detail: "Raw and reduced invariant outcomes differ"))
    }
    if !deadlockOutcomesAgree(input) {
      differences.append(try SymmetryOrbitDifferenceV1(
        kind: .deadlockOutcome, detail: "Raw and reduced deadlock outcomes differ"))
    }
    guard differences.isEmpty else { return .difference(differences) }

    let orbits = try derivation.orbits.map { members -> SymmetryOrbitV1 in
      let semantic = members[0].canonicalEncoding
      guard let swiftRepresentative = swiftRepresentatives[semantic], let tlcRepresentative = tlcRepresentatives[semantic] else {
        throw SymmetryOrbitAdapterErrorV1.incompleteOrbit(semantic)
      }
      return try SymmetryOrbitV1(
        members: members.map(\.canonicalEncoding), semanticRepresentative: semantic,
        swiftExecutableRepresentative: swiftRepresentative,
        tlcExecutableRepresentative: tlcRepresentative)
    }
    let rawWitnesses = rawWitnesses(input.swiftRawRun, engine: .swift) + rawWitnesses(input.tlcRawRun, engine: .tlc)
    let comparison = try SymmetryOrbitComparisonV1(
      caseID: input.caseID, configuration: input.configuration, correlation: input.correlation, outcome: .exact,
      swiftRaw: input.swiftRaw, swiftReduced: input.swiftReduced, tlcRaw: input.tlcRaw, tlcReduced: input.tlcReduced,
      configurationEvidence: input.configurationEvidence, quotientEvidence: input.quotientEvidence, orbits: orbits,
      rawTransitionWitnesses: rawWitnesses, quotientTransitions: expectedQuotient,
      diagnosticCode: .exactAgreement)
    return .exact(comparison)
  }

  private func reducedRepresentatives(
    _ run: CanonicalRunV1,
    engine: SymmetryExplorationEngineV1,
    derivation: SymmetryOrbitDerivationV1
  ) throws -> [String: String] {
    var representatives: [String: String] = [:]
    for state in run.graph.states.keys {
      guard let orbit = derivation.representativeForState[state] else {
        throw SymmetryOrbitAdapterErrorV1.reducedStateOutsideOrbit(engine: engine, stateID: state.canonicalEncoding)
      }
      let orbitID = orbit.canonicalEncoding
      guard representatives[orbitID] == nil else {
        throw SymmetryOrbitAdapterErrorV1.multipleReducedRepresentatives(engine: engine, representative: orbitID)
      }
      representatives[orbitID] = state.canonicalEncoding
    }
    for orbit in derivation.orbits {
      let orbitID = orbit[0].canonicalEncoding
      guard representatives[orbitID] != nil else {
        throw SymmetryOrbitAdapterErrorV1.missingReducedRepresentative(engine: engine, representative: orbitID)
      }
    }
    return representatives
  }

  private func validate(_ exploration: SymmetryExplorationV1, against run: CanonicalRunV1) throws {
    let stateIDs = Set(run.graph.states.keys.map(\.canonicalEncoding))
    let initialStateIDs = Set(run.graph.initialStateKeys.map(\.canonicalEncoding))
    let transitions = try Set(run.graph.edgeOccurrences.keys.map {
      try SymmetryRawTransitionWitnessV1(
        engine: exploration.engine, sourceStateID: $0.source.canonicalEncoding, action: $0.action,
        targetStateID: $0.target.canonicalEncoding)
    })
    guard Set(exploration.stateIDs) == stateIDs,
          Set(exploration.initialStateIDs) == initialStateIDs,
          Set(exploration.transitions) == transitions else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(
        record: exploration.graphID, field: "canonical graph evidence")
    }
  }

  private func quotientTransitions(
    _ run: CanonicalRunV1,
    derivation: SymmetryOrbitDerivationV1
  ) -> [SymmetryQuotientTransitionV1] {
    Set(run.graph.edgeOccurrences.keys.compactMap { edge in
      guard let source = derivation.representativeForState[edge.source],
            let target = derivation.representativeForState[edge.target] else { return nil }
      return try? SymmetryQuotientTransitionV1(
        sourceRepresentative: source.canonicalEncoding, action: edge.action, targetRepresentative: target.canonicalEncoding)
    }).sorted()
  }

  private func rawWitnesses(_ run: CanonicalRunV1, engine: SymmetryExplorationEngineV1) -> [SymmetryRawTransitionWitnessV1] {
    run.graph.edgeOccurrences.keys.compactMap { edge in
      try? SymmetryRawTransitionWitnessV1(
        engine: engine, sourceStateID: edge.source.canonicalEncoding, action: edge.action,
        targetStateID: edge.target.canonicalEncoding)
    }.sorted { $0.sourceStateID < $1.sourceStateID }
  }

  private func invariantOutcomesAgree(_ input: SymmetryOrbitComparisonInputV1) -> Bool {
    let outcomes = [input.swiftRaw.invariantOutcome, input.swiftReduced.invariantOutcome,
                    input.tlcRaw.invariantOutcome, input.tlcReduced.invariantOutcome]
    return outcomes.allSatisfy { $0 == outcomes[0] }
  }

  private func deadlockOutcomesAgree(_ input: SymmetryOrbitComparisonInputV1) -> Bool {
    let outcomes = [input.swiftRaw.deadlockOutcome, input.swiftReduced.deadlockOutcome,
                    input.tlcRaw.deadlockOutcome, input.tlcReduced.deadlockOutcome]
    return outcomes.allSatisfy { $0 == outcomes[0] }
  }
}
