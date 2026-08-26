import Foundation

package enum SymmetryOrbitDifferenceKind: String, Codable, Sendable {
  case rawStateSet
  case quotientTransition
  case invariantOutcome
  case deadlockOutcome
}

package struct SymmetryOrbitDifference: Equatable, Codable, Sendable {
  package let kind: SymmetryOrbitDifferenceKind
  package let detail: String

  package init(kind: SymmetryOrbitDifferenceKind, detail: String) throws {
    guard !detail.isEmpty else {
      throw EvidenceFormatError.invalidField(record: "symmetry difference", field: "detail")
    }
    self.kind = kind
    self.detail = detail
  }
}

package enum SymmetryOrbitComparisonResult: Equatable, Sendable {
  case exact(SymmetryOrbitComparison)
  case difference([SymmetryOrbitDifference])
}

package struct SymmetryOrbitComparisonInput: Sendable {
  package let caseID: String
  package let configuration: TemporalSymmetryConfiguration
  package let correlation: TemporalSymmetryCaseOutcomeCorrelation
  package let swiftRaw: SymmetryExploration
  package let swiftReduced: SymmetryExploration
  package let tlcRaw: SymmetryExploration
  package let tlcReduced: SymmetryExploration
  package let swiftRawRun: CompletedGraphRun
  package let swiftReducedRun: CompletedGraphRun
  package let tlcRawRun: CompletedGraphRun
  package let tlcReducedRun: CompletedGraphRun
  package let configurationEvidence: RetainedFileReference
  package let quotientEvidence: RetainedFileReference
  package let permutations: [SymmetryPermutation]

  package init(
    caseID: String,
    configuration: TemporalSymmetryConfiguration,
    correlation: TemporalSymmetryCaseOutcomeCorrelation,
    swiftRaw: SymmetryExploration,
    swiftReduced: SymmetryExploration,
    tlcRaw: SymmetryExploration,
    tlcReduced: SymmetryExploration,
    swiftRawRun: CompletedGraphRun,
    swiftReducedRun: CompletedGraphRun,
    tlcRawRun: CompletedGraphRun,
    tlcReducedRun: CompletedGraphRun,
    configurationEvidence: RetainedFileReference,
    quotientEvidence: RetainedFileReference,
    permutations: [SymmetryPermutation]
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

  package func validate() throws {
    try configuration.validate()
    try configurationEvidence.validate()
    try quotientEvidence.validate()
    guard !caseID.isEmpty, correlation.caseID == caseID, configuration.property == nil,
          configuration.symmetryEnabled, !permutations.isEmpty else {
      throw EvidenceFormatError.inconsistentReference(record: caseID, field: "symmetry input")
    }
    let explorations = [swiftRaw, swiftReduced, tlcRaw, tlcReduced]
    guard Set(explorations.map { "\($0.engine.rawValue):\($0.reduced)" }).count == 4,
          swiftRaw.runID == correlation.swiftRunID,
          tlcRaw.runID == correlation.tlcRunID,
          Set([correlation.runID, correlation.comparisonRunID, swiftRaw.runID, swiftReduced.runID,
               tlcRaw.runID, tlcReduced.runID]).count == 6,
          Set(explorations.map(\.declaredConfigurationSHA256)).count == 1 else {
      throw EvidenceFormatError.inconsistentReference(record: caseID, field: "symmetry pair configuration")
    }
  }
}

package struct SymmetryOrbitComparator: Sendable {
  package init() {}

  package func compare(_ input: SymmetryOrbitComparisonInput) throws -> SymmetryOrbitComparisonResult {
    try validate(input.swiftRaw, against: input.swiftRawRun)
    try validate(input.swiftReduced, against: input.swiftReducedRun)
    try validate(input.tlcRaw, against: input.tlcRawRun)
    try validate(input.tlcReduced, against: input.tlcReducedRun)
    let swiftRawStates = Set(input.swiftRawRun.graph.states.keys)
    let tlcRawStates = Set(input.tlcRawRun.graph.states.keys)
    guard swiftRawStates == tlcRawStates else {
      return .difference([try SymmetryOrbitDifference(kind: .rawStateSet, detail: "Swift and TLC raw state sets differ")])
    }
    let derivation = try SymmetryOrbitDerivation(
      states: Array(input.swiftRawRun.graph.states.values), permutations: input.permutations)
    let swiftRepresentatives = try reducedRepresentatives(
      input.swiftReducedRun, engine: .swift, derivation: derivation)
    let tlcRepresentatives = try reducedRepresentatives(
      input.tlcReducedRun, engine: .tlc, derivation: derivation)
    let expectedQuotient = quotientTransitions(input.swiftRawRun, derivation: derivation)
    let tlcRawQuotient = quotientTransitions(input.tlcRawRun, derivation: derivation)
    let swiftReducedQuotient = quotientTransitions(input.swiftReducedRun, derivation: derivation)
    let tlcReducedQuotient = quotientTransitions(input.tlcReducedRun, derivation: derivation)

    var differences: [SymmetryOrbitDifference] = []
    if expectedQuotient != tlcRawQuotient || expectedQuotient != swiftReducedQuotient
      || expectedQuotient != tlcReducedQuotient {
      differences.append(try SymmetryOrbitDifference(
        kind: .quotientTransition, detail: "Raw or reduced quotient transitions differ"))
    }
    if !invariantOutcomesAgree(input) {
      differences.append(try SymmetryOrbitDifference(
        kind: .invariantOutcome, detail: "Raw and reduced invariant outcomes differ"))
    }
    if !deadlockOutcomesAgree(input) {
      differences.append(try SymmetryOrbitDifference(
        kind: .deadlockOutcome, detail: "Raw and reduced deadlock outcomes differ"))
    }
    guard differences.isEmpty else { return .difference(differences) }

    let orbits = try derivation.orbits.map { members -> SymmetryOrbit in
      let semantic = members[0].canonicalEncoding
      guard let swiftRepresentative = swiftRepresentatives[semantic], let tlcRepresentative = tlcRepresentatives[semantic] else {
        throw SymmetryOrbitAdapterError.incompleteOrbit(semantic)
      }
      return try SymmetryOrbit(
        members: members.map(\.canonicalEncoding), semanticRepresentative: semantic,
        swiftExecutableRepresentative: swiftRepresentative,
        tlcExecutableRepresentative: tlcRepresentative)
    }
    let rawWitnesses = rawWitnesses(input.swiftRawRun, engine: .swift) + rawWitnesses(input.tlcRawRun, engine: .tlc)
    let comparison = try SymmetryOrbitComparison(
      caseID: input.caseID, configuration: input.configuration, correlation: input.correlation, outcome: .exact,
      swiftRaw: input.swiftRaw, swiftReduced: input.swiftReduced, tlcRaw: input.tlcRaw, tlcReduced: input.tlcReduced,
      configurationEvidence: input.configurationEvidence, quotientEvidence: input.quotientEvidence, orbits: orbits,
      rawTransitionWitnesses: rawWitnesses, quotientTransitions: expectedQuotient,
      diagnosticCode: .exactAgreement)
    return .exact(comparison)
  }

  private func reducedRepresentatives(
    _ run: CompletedGraphRun,
    engine: SymmetryExplorationEngine,
    derivation: SymmetryOrbitDerivation
  ) throws -> [String: String] {
    var representatives: [String: String] = [:]
    for state in run.graph.states.keys {
      guard let orbit = derivation.representativeForState[state] else {
        throw SymmetryOrbitAdapterError.reducedStateOutsideOrbit(engine: engine, stateID: state.canonicalEncoding)
      }
      let orbitID = orbit.canonicalEncoding
      guard representatives[orbitID] == nil else {
        throw SymmetryOrbitAdapterError.multipleReducedRepresentatives(engine: engine, representative: orbitID)
      }
      representatives[orbitID] = state.canonicalEncoding
    }
    for orbit in derivation.orbits {
      let orbitID = orbit[0].canonicalEncoding
      guard representatives[orbitID] != nil else {
        throw SymmetryOrbitAdapterError.missingReducedRepresentative(engine: engine, representative: orbitID)
      }
    }
    return representatives
  }

  private func validate(_ exploration: SymmetryExploration, against run: CompletedGraphRun) throws {
    let stateIDs = Set(run.graph.states.keys.map(\.canonicalEncoding))
    let initialStateIDs = Set(run.graph.initialStateKeys.map(\.canonicalEncoding))
    let transitions = try Set(run.graph.edgeOccurrences.map {
      try SymmetryRawTransitionWitness(
        engine: exploration.engine, sourceStateID: $0.key.source.canonicalEncoding, action: $0.key.action,
        targetStateID: $0.key.target.canonicalEncoding, occurrences: $0.value)
    })
    guard Set(exploration.stateIDs) == stateIDs,
          Set(exploration.initialStateIDs) == initialStateIDs,
          Set(exploration.transitions) == transitions else {
      throw EvidenceFormatError.invalidField(
        record: exploration.graphID, field: "canonical graph evidence")
    }
  }

  private func quotientTransitions(
    _ run: CompletedGraphRun,
    derivation: SymmetryOrbitDerivation
  ) -> [SymmetryQuotientTransition] {
    Set(run.graph.edgeOccurrences.keys.compactMap { edge in
      guard let source = derivation.representativeForState[edge.source],
            let target = derivation.representativeForState[edge.target] else { return nil }
      return try? SymmetryQuotientTransition(
        sourceRepresentative: source.canonicalEncoding, action: edge.action, targetRepresentative: target.canonicalEncoding)
    }).sorted()
  }

  private func rawWitnesses(_ run: CompletedGraphRun, engine: SymmetryExplorationEngine) -> [SymmetryRawTransitionWitness] {
    run.graph.edgeOccurrences.compactMap { edge, occurrences in
      try? SymmetryRawTransitionWitness(
        engine: engine, sourceStateID: edge.source.canonicalEncoding, action: edge.action,
        targetStateID: edge.target.canonicalEncoding, occurrences: occurrences)
    }.sorted { $0.sourceStateID < $1.sourceStateID }
  }

  private func invariantOutcomesAgree(_ input: SymmetryOrbitComparisonInput) -> Bool {
    let outcomes = [input.swiftRaw.invariantOutcome, input.swiftReduced.invariantOutcome,
                    input.tlcRaw.invariantOutcome, input.tlcReduced.invariantOutcome]
    return outcomes.allSatisfy { $0 == outcomes[0] }
  }

  private func deadlockOutcomesAgree(_ input: SymmetryOrbitComparisonInput) -> Bool {
    let outcomes = [input.swiftRaw.deadlockOutcome, input.swiftReduced.deadlockOutcome,
                    input.tlcRaw.deadlockOutcome, input.tlcReduced.deadlockOutcome]
    return outcomes.allSatisfy { $0 == outcomes[0] }
  }
}
