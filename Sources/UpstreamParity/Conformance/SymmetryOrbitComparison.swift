import Foundation
import SwiftTLA

package struct SymmetryOrbit: Equatable, Encodable, Sendable {
  package let members: [String]
  package let semanticRepresentative: String
  package let tlcExecutableRepresentative: String

  package init(
    members: [String],
    semanticRepresentative: String,
    tlcExecutableRepresentative: String
  ) throws {
    let orderedMembers = members.sorted()
    guard orderedMembers.isEmpty == false,
          Set(orderedMembers).count == orderedMembers.count,
          orderedMembers.allSatisfy({ $0.isEmpty == false }),
          semanticRepresentative == orderedMembers.first,
          orderedMembers.contains(tlcExecutableRepresentative) else {
      throw EvidenceFormatError.invalidField(record: "orbit", field: "members or representative")
    }
    self.members = orderedMembers
    self.semanticRepresentative = semanticRepresentative
    self.tlcExecutableRepresentative = tlcExecutableRepresentative
  }
}

package struct SymmetryQuotientTransition: Hashable, Encodable, Sendable, Comparable {
  package let sourceRepresentative: String
  package let action: String
  package let targetRepresentative: String

  package init(sourceRepresentative: String, action: String, targetRepresentative: String) throws {
    guard sourceRepresentative.isEmpty == false,
          action.isEmpty == false,
          targetRepresentative.isEmpty == false else {
      throw EvidenceFormatError.invalidField(record: "quotient transition", field: "transition")
    }
    self.sourceRepresentative = sourceRepresentative
    self.action = action
    self.targetRepresentative = targetRepresentative
  }

  package static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.sourceRepresentative != rhs.sourceRepresentative {
      return lhs.sourceRepresentative < rhs.sourceRepresentative
    }
    if lhs.action != rhs.action { return lhs.action < rhs.action }
    return lhs.targetRepresentative < rhs.targetRepresentative
  }
}

package struct SymmetryOrbitComparison: Equatable, Encodable, Sendable {
  package static let schema = "SymmetryOrbitComparison.v2"

  package let schema: String
  package let caseID: String
  package let orbits: [SymmetryOrbit]
  package let quotientTransitions: [SymmetryQuotientTransition]

  package init(
    caseID: String,
    orbits: [SymmetryOrbit],
    quotientTransitions: [SymmetryQuotientTransition]
  ) throws {
    let members = orbits.flatMap(\.members)
    let representatives = Set(orbits.map(\.semanticRepresentative))
    let orderedTransitions = quotientTransitions.sorted()
    guard caseID.isEmpty == false,
          orbits.isEmpty == false,
          Set(members).count == members.count,
          Set(orderedTransitions).count == orderedTransitions.count,
          orderedTransitions.allSatisfy({
            representatives.contains($0.sourceRepresentative)
              && representatives.contains($0.targetRepresentative)
          }) else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "orbit comparison")
    }
    schema = Self.schema
    self.caseID = caseID
    self.orbits = orbits.sorted { $0.semanticRepresentative < $1.semanticRepresentative }
    self.quotientTransitions = orderedTransitions
  }
}

package enum SymmetryOrbitDifferenceKind: String, Encodable, Sendable {
  case incompleteRun
  case rawGraph
  case variableNames
  case undeclaredAction
  case unsoundSymmetry
  case reducedInitialStates
  case quotientTransition
  case checkOutcome
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
  package let swiftRaw: GraphRun
  package let tlcRaw: GraphRun
  package let tlcReduced: GraphRun
  package let renderedActions: [RenderedAction]
  package let permutations: [SymmetryPermutation]
  package let maximumPermutationCount: Int

  package init(
    caseID: String,
    swiftRaw: GraphRun,
    tlcRaw: GraphRun,
    tlcReduced: GraphRun,
    renderedActions: [RenderedAction],
    permutations: [SymmetryPermutation],
    maximumPermutationCount: Int
  ) throws {
    guard caseID.isEmpty == false,
          permutations.isEmpty == false,
          maximumPermutationCount > 0 else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "symmetry comparison input")
    }
    self.caseID = caseID
    self.swiftRaw = swiftRaw
    self.tlcRaw = tlcRaw
    self.tlcReduced = tlcReduced
    self.renderedActions = renderedActions
    self.permutations = permutations
    self.maximumPermutationCount = maximumPermutationCount
  }
}

package func compareSymmetryOrbits(
  _ input: SymmetryOrbitComparisonInput
) throws -> SymmetryOrbitComparisonResult {
  let runs = [input.swiftRaw, input.tlcRaw, input.tlcReduced]
  guard runs.allSatisfy({ run in
    guard run.isComplete else { return false }
    switch run.outcome {
    case .noViolation: return true
    case .deadlock(let state): return !run.graph.edges.contains { $0.source == state }
    default: return false
    }
  }) else {
    return .difference([SymmetryOrbitDifference(
      kind: .incompleteRun,
      detail: "The generated Swift and raw and reduced TLC explorations must complete exhaustively"
    )])
  }

  let deadlocks = runs.map { run in
    if case .deadlock = run.outcome { return true }
    return false
  }
  guard deadlocks.allSatisfy({ $0 == deadlocks[0] }) else {
    return .difference([SymmetryOrbitDifference(kind: .checkOutcome,
      detail: "Generated Swift and raw and reduced TLC deadlock results differ")])
  }

  let rawComparison = compareFiniteGraphs(tlc: input.tlcRaw, swift: input.swiftRaw)
  guard rawComparison.matches else {
    return .difference(rawComparison.differences.map { difference in
      SymmetryOrbitDifference(
        kind: .rawGraph,
        detail: difference.failureReport.whatFailed
      )
    })
  }

  let variableNames = input.swiftRaw.graph.variableNames
  let declaredActions = Set(input.renderedActions.map(\.renderedName))
  guard runs.allSatisfy({ $0.graph.variableNames == variableNames }) else {
    return .difference([SymmetryOrbitDifference(
      kind: .variableNames,
      detail: "Generated Swift and raw and reduced TLC graphs declare different variables"
    )])
  }
  let undeclaredActions = Set(runs.flatMap { run in
    run.graph.observedActions.subtracting(declaredActions)
  })
  guard undeclaredActions.isEmpty else {
    return .difference([SymmetryOrbitDifference(
      kind: .undeclaredAction,
      detail: "Graph actions are absent from the rendered action plan: \(undeclaredActions.sorted().joined(separator: ", "))"
    )])
  }

  let derivation = try SymmetryOrbitDerivation(
    states: Array(input.swiftRaw.graph.states.values),
    permutations: input.permutations,
    maximumPermutationCount: input.maximumPermutationCount
  )
  let actionPlan = try SymmetryActionPlan(input.renderedActions)
  if let difference = try symmetryInvariantDifference(
    input.swiftRaw.graph, generators: input.permutations, actionPlan: actionPlan
  ) {
    return .difference([difference])
  }
  let tlcRepresentatives = try reducedRepresentatives(input.tlcReduced, derivation: derivation)

  let rawInitialRepresentatives = try initialRepresentatives(input.swiftRaw, derivation: derivation)
  let tlcInitialRepresentatives = try initialRepresentatives(input.tlcReduced, derivation: derivation)
  guard rawInitialRepresentatives == tlcInitialRepresentatives else {
    return .difference([SymmetryOrbitDifference(
      kind: .reducedInitialStates,
      detail: "The raw and reduced TLC graphs have different initial symmetry orbits"
    )])
  }

  let expectedQuotient = try quotientTransitions(
    input.swiftRaw, derivation: derivation, actionPlan: actionPlan)
  let reducedQuotient = try quotientTransitions(input.tlcReduced, derivation: derivation, actionPlan: actionPlan)
  guard reducedQuotient == expectedQuotient else {
    return .difference([SymmetryOrbitDifference(
      kind: .quotientTransition,
      detail: "The reduced TLC quotient transitions differ from the generated Swift graph"
    )])
  }

  let orbits = try derivation.orbits.map { members -> SymmetryOrbit in
    let semantic = members[0].canonicalEncoding
    guard let tlcRepresentative = tlcRepresentatives[semantic] else {
      throw SymmetryOrbitError.incompleteOrbit(semantic)
    }
    return try SymmetryOrbit(
      members: members.map(\.canonicalEncoding),
      semanticRepresentative: semantic,
      tlcExecutableRepresentative: tlcRepresentative
    )
  }
  return .exact(try SymmetryOrbitComparison(
    caseID: input.caseID,
    orbits: orbits,
    quotientTransitions: expectedQuotient
  ))
}

private func symmetryInvariantDifference(
  _ graph: CanonicalGraph,
  generators: [SymmetryPermutation],
  actionPlan: SymmetryActionPlan
) throws -> SymmetryOrbitDifference? {
  let edges = graph.edges
  // Preservation under every generator implies preservation under their closed group.
  for permutation in generators {
    for key in graph.initialStateKeys {
      guard let state = graph.states[key] else { throw SymmetryOrbitError.incompleteOrbit(key.canonicalEncoding) }
      let transformed = try permutation.apply(state).key
      guard graph.initialStateKeys.contains(transformed) else {
        return SymmetryOrbitDifference(kind: .unsoundSymmetry,
          detail: "Declared symmetry maps initial state \(key) to non-initial state \(transformed)")
      }
    }
    for edge in edges {
      guard let source = graph.states[edge.source], let target = graph.states[edge.target] else {
        throw SymmetryOrbitError.incompleteOrbit(edge.canonicalEncoding)
      }
      let transformed = CanonicalEdge(
        source: try permutation.apply(source).key,
        action: try actionPlan.transformedAction(edge.action, by: permutation),
        target: try permutation.apply(target).key
      )
      guard edges.contains(transformed) else {
        return SymmetryOrbitDifference(kind: .unsoundSymmetry,
          detail: "Declared symmetry does not preserve transition \(edge.canonicalEncoding): missing \(transformed.canonicalEncoding)")
      }
    }
  }
  return nil
}

private func reducedRepresentatives(
  _ run: GraphRun,
  derivation: SymmetryOrbitDerivation
) throws -> [String: String] {
  var representatives: [String: String] = [:]
  for state in run.graph.states.keys {
    guard let orbit = derivation.representativeForState[state] else {
      throw SymmetryOrbitError.reducedStateOutsideOrbit(
        stateID: state.canonicalEncoding
      )
    }
    let orbitID = orbit.canonicalEncoding
    guard representatives[orbitID] == nil else {
      throw SymmetryOrbitError.multipleReducedRepresentatives(
        representative: orbitID
      )
    }
    representatives[orbitID] = state.canonicalEncoding
  }
  for orbit in derivation.orbits {
    let orbitID = orbit[0].canonicalEncoding
    guard representatives[orbitID] != nil else {
      throw SymmetryOrbitError.missingReducedRepresentative(
        representative: orbitID
      )
    }
  }
  return representatives
}

private func initialRepresentatives(
  _ run: GraphRun,
  derivation: SymmetryOrbitDerivation
) throws -> Set<CanonicalStateKey> {
  try Set(run.graph.initialStateKeys.map { state in
    guard let representative = derivation.representativeForState[state] else {
      throw SymmetryOrbitError.incompleteOrbit(state.canonicalEncoding)
    }
    return representative
  })
}

private func quotientTransitions(
  _ run: GraphRun,
  derivation: SymmetryOrbitDerivation,
  actionPlan: SymmetryActionPlan
) throws -> [SymmetryQuotientTransition] {
  try Set(run.graph.edges.map { edge in
    guard let source = derivation.representativeForState[edge.source],
          let target = derivation.representativeForState[edge.target],
          let sourceState = run.graph.states[edge.source] else {
      throw SymmetryOrbitError.incompleteOrbit(edge.source.canonicalEncoding)
    }
    return try SymmetryQuotientTransition(
      sourceRepresentative: source.canonicalEncoding,
      action: actionPlan.representative(
        for: edge.action,
        from: sourceState,
        sourceRepresentative: source,
        group: derivation.group
      ),
      targetRepresentative: target.canonicalEncoding
    )
  }).sorted()
}

private struct SymmetryActionCall: Hashable {
  let sourceName: String
  let arguments: [CanonicalValue]
}

private struct SymmetryActionPlan {
  private let calls: [String: SymmetryActionCall]
  private let renderedNames: [SymmetryActionCall: String]

  init(_ actions: [RenderedAction]) throws {
    var calls: [String: SymmetryActionCall] = [:]
    var renderedNames: [SymmetryActionCall: String] = [:]
    for action in actions {
      let call = SymmetryActionCall(
        sourceName: action.sourceName,
        arguments: try action.arguments.map(CanonicalValue.init)
      )
      guard calls.updateValue(call, forKey: action.renderedName) == nil else {
        throw SymmetryOrbitError.duplicateRenderedAction(action.renderedName)
      }
      guard renderedNames.updateValue(action.renderedName, forKey: call) == nil else {
        throw SymmetryOrbitError.duplicateActionCall
      }
    }
    self.calls = calls
    self.renderedNames = renderedNames
  }

  func representative(
    for action: String,
    from source: CanonicalState,
    sourceRepresentative: CanonicalStateKey,
    group: [SymmetryPermutation]
  ) throws -> String {
    var candidates: [String] = []
    for permutation in group where try permutation.apply(source).key == sourceRepresentative {
      candidates.append(try transformedAction(action, by: permutation))
    }
    guard let representative = candidates.min(by: canonicalBytes) else {
      throw SymmetryOrbitError.incompleteOrbit(source.key.canonicalEncoding)
    }
    return representative
  }

  func transformedAction(_ action: String, by permutation: SymmetryPermutation) throws -> String {
    guard let call = calls[action] else { throw SymmetryOrbitError.undeclaredAction(action) }
    let transformed = SymmetryActionCall(
      sourceName: call.sourceName,
      arguments: try call.arguments.map(permutation.apply)
    )
    guard let renderedName = renderedNames[transformed] else {
      throw SymmetryOrbitError.actionPlanNotClosed(action: action)
    }
    return renderedName
  }
}
