import Foundation

package enum SymmetryOrbitDifferenceKind: String, Encodable, Sendable {
  case incompleteRun
  case rawGraph
  case observableNames
  case reducedInitialStates
  case quotientTransition
}

package struct SymmetryOrbitDifference: Equatable, Encodable, Sendable {
  package let kind: SymmetryOrbitDifferenceKind
  package let detail: String
}

package enum SymmetryOrbitComparisonResult: Equatable, Sendable {
  case exact(SymmetryOrbitComparison)
  case difference([SymmetryOrbitDifference])
}

package struct SymmetryOrbitComparisonInput: Sendable {
  package let caseID: String
  package let swiftRaw: CompletedGraphRun
  package let swiftReduced: CompletedGraphRun
  package let tlcRaw: CompletedGraphRun
  package let tlcReduced: CompletedGraphRun
  package let permutations: [SymmetryPermutation]

  package init(
    caseID: String,
    swiftRaw: CompletedGraphRun,
    swiftReduced: CompletedGraphRun,
    tlcRaw: CompletedGraphRun,
    tlcReduced: CompletedGraphRun,
    permutations: [SymmetryPermutation]
  ) throws {
    guard caseID.isEmpty == false, permutations.isEmpty == false else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "symmetry comparison input")
    }
    self.caseID = caseID
    self.swiftRaw = swiftRaw
    self.swiftReduced = swiftReduced
    self.tlcRaw = tlcRaw
    self.tlcReduced = tlcReduced
    self.permutations = permutations
  }
}

package func compareSymmetryOrbits(
  _ input: SymmetryOrbitComparisonInput
) throws -> SymmetryOrbitComparisonResult {
  let runs = [input.swiftRaw, input.swiftReduced, input.tlcRaw, input.tlcReduced]
  guard runs.allSatisfy(\.isPassEligible) else {
    return .difference([SymmetryOrbitDifference(
      kind: .incompleteRun,
      detail: "Every raw and reduced SwiftTLA and TLC exploration must complete exhaustively"
    )])
  }

  let rawComparison = compareFiniteGraphs(expected: input.tlcRaw, actual: input.swiftRaw)
  guard rawComparison.isConformant else {
    return .difference(rawComparison.differences.map { difference in
      SymmetryOrbitDifference(
        kind: .rawGraph,
        detail: "SwiftTLA and TLC raw graphs differ in \(difference.category.rawValue)"
      )
    })
  }

  let variableNames = input.swiftRaw.graph.variableNames
  let observableActions = input.swiftRaw.observableActions
  guard runs.allSatisfy({
    $0.graph.variableNames == variableNames && $0.observableActions == observableActions
  }) else {
    return .difference([SymmetryOrbitDifference(
      kind: .observableNames,
      detail: "Raw and reduced SwiftTLA and TLC graphs declare different observable names"
    )])
  }

  let derivation = try SymmetryOrbitDerivation(
    states: Array(input.swiftRaw.graph.states.values),
    permutations: input.permutations
  )
  let swiftRepresentatives = try reducedRepresentatives(
    input.swiftReduced, engine: .swift, derivation: derivation
  )
  let tlcRepresentatives = try reducedRepresentatives(
    input.tlcReduced, engine: .tlc, derivation: derivation
  )

  let rawInitialRepresentatives = try initialRepresentatives(input.swiftRaw, derivation: derivation)
  let swiftInitialRepresentatives = try initialRepresentatives(input.swiftReduced, derivation: derivation)
  let tlcInitialRepresentatives = try initialRepresentatives(input.tlcReduced, derivation: derivation)
  guard rawInitialRepresentatives == swiftInitialRepresentatives,
        rawInitialRepresentatives == tlcInitialRepresentatives else {
    return .difference([SymmetryOrbitDifference(
      kind: .reducedInitialStates,
      detail: "Raw and reduced SwiftTLA and TLC graphs have different initial symmetry orbits"
    )])
  }

  let expectedQuotient = try quotientTransitions(input.swiftRaw, derivation: derivation)
  let quotients = try [
    quotientTransitions(input.tlcRaw, derivation: derivation),
    quotientTransitions(input.swiftReduced, derivation: derivation),
    quotientTransitions(input.tlcReduced, derivation: derivation)
  ]
  guard quotients.allSatisfy({ $0 == expectedQuotient }) else {
    return .difference([SymmetryOrbitDifference(
      kind: .quotientTransition,
      detail: "Raw or reduced SwiftTLA and TLC quotient transitions differ"
    )])
  }

  let orbits = try derivation.orbits.map { members -> SymmetryOrbit in
    let semantic = members[0].canonicalEncoding
    guard let swiftRepresentative = swiftRepresentatives[semantic],
          let tlcRepresentative = tlcRepresentatives[semantic] else {
      throw SymmetryOrbitAdapterError.incompleteOrbit(semantic)
    }
    return try SymmetryOrbit(
      members: members.map(\.canonicalEncoding),
      semanticRepresentative: semantic,
      swiftExecutableRepresentative: swiftRepresentative,
      tlcExecutableRepresentative: tlcRepresentative
    )
  }
  return .exact(try SymmetryOrbitComparison(
    caseID: input.caseID,
    orbits: orbits,
    quotientTransitions: expectedQuotient
  ))
}

private func reducedRepresentatives(
  _ run: CompletedGraphRun,
  engine: SymmetryExplorationEngine,
  derivation: SymmetryOrbitDerivation
) throws -> [String: String] {
  var representatives: [String: String] = [:]
  for state in run.graph.states.keys {
    guard let orbit = derivation.representativeForState[state] else {
      throw SymmetryOrbitAdapterError.reducedStateOutsideOrbit(
        engine: engine,
        stateID: state.canonicalEncoding
      )
    }
    let orbitID = orbit.canonicalEncoding
    guard representatives[orbitID] == nil else {
      throw SymmetryOrbitAdapterError.multipleReducedRepresentatives(
        engine: engine,
        representative: orbitID
      )
    }
    representatives[orbitID] = state.canonicalEncoding
  }
  for orbit in derivation.orbits {
    let orbitID = orbit[0].canonicalEncoding
    guard representatives[orbitID] != nil else {
      throw SymmetryOrbitAdapterError.missingReducedRepresentative(
        engine: engine,
        representative: orbitID
      )
    }
  }
  return representatives
}

private func initialRepresentatives(
  _ run: CompletedGraphRun,
  derivation: SymmetryOrbitDerivation
) throws -> Set<CanonicalStateKey> {
  try Set(run.graph.initialStateKeys.map { state in
    guard let representative = derivation.representativeForState[state] else {
      throw SymmetryOrbitAdapterError.incompleteOrbit(state.canonicalEncoding)
    }
    return representative
  })
}

private func quotientTransitions(
  _ run: CompletedGraphRun,
  derivation: SymmetryOrbitDerivation
) throws -> [SymmetryQuotientTransition] {
  try Set(run.graph.edgeOccurrences.keys.map { edge in
    guard let source = derivation.representativeForState[edge.source],
          let target = derivation.representativeForState[edge.target] else {
      throw SymmetryOrbitAdapterError.incompleteOrbit(edge.source.canonicalEncoding)
    }
    return try SymmetryQuotientTransition(
      sourceRepresentative: source.canonicalEncoding,
      action: edge.action,
      targetRepresentative: target.canonicalEncoding
    )
  }).sorted()
}
