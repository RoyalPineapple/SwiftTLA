import Foundation
import Testing
import UpstreamParity

struct SymmetryOrbitConformanceTests {
  @Test("A reduced representative outside its declared orbit is rejected")
  func reducedRepresentativeOutsideOrbitIsRejected() throws {
    let input = try fixture(reducedStates: [state("C")])
    #expect(throws: SymmetryOrbitAdapterError.reducedStateOutsideOrbit(engine: .swift, stateID: state("C").key.canonicalEncoding)) {
      _ = try SymmetryOrbitComparator().compare(input)
    }
  }

  @Test("Matched pinned raw and reduced graphs produce complete canonical orbit evidence")
  func matchedGraphsProduceExactOrbitEvidence() throws {
    let input = try fixture(reducedStates: [state("A")])
    let result = try SymmetryOrbitComparator().compare(input)
    guard case .exact(let comparison) = result else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.orbits.count == 1)
    #expect(comparison.orbits[0].members == [state("A").key.canonicalEncoding, state("B").key.canonicalEncoding].sorted())
    #expect(comparison.orbits[0].semanticRepresentative == state("A").key.canonicalEncoding)
    #expect(comparison.quotientTransitions.count == 1)
    #expect(comparison.rawTransitionWitnesses.count == 2)
  }

  @Test("Different executable representatives of the same orbit agree")
  func differentExecutableRepresentativesAgree() throws {
    let input = try fixture(reducedStates: [state("A")], tlcReducedStates: [state("B")])
    guard case .exact(let comparison) = try SymmetryOrbitComparator().compare(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.orbits[0].swiftExecutableRepresentative == state("A").key.canonicalEncoding)
    #expect(comparison.orbits[0].tlcExecutableRepresentative == state("B").key.canonicalEncoding)
  }

  @Test("Raw state-set differences produce structured comparison differences")
  func rawStateSetDifferenceIsStructured() throws {
    let rawStates = [state("A"), state("B")]
    let reducedStates = [state("A")]
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: "scope-2", runID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let input = try SymmetryOrbitComparisonInput(
      caseID: "scope-2", configuration: try TemporalSymmetryConfiguration(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true), correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, states: rawStates),
      swiftReduced: try exploration(.swift, true, UUID(), states: reducedStates),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, states: [state("A")]),
      tlcReduced: try exploration(.tlc, true, UUID(), states: reducedStates),
      swiftRawRun: try run(states: rawStates), swiftReducedRun: try run(states: reducedStates),
      tlcRawRun: try run(states: [state("A")]), tlcReducedRun: try run(states: reducedStates),
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutation(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])])
    let result = try SymmetryOrbitComparator().compare(input)
    guard case .difference(let differences) = result else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind) == [.rawStateSet])
  }

  @Test("Orbit derivation closes a generator group before partitioning states")
  func orbitDerivationUsesGeneratorClosure() throws {
    let derivation = try SymmetryOrbitDerivation(
      states: [state("A"), state("B"), state("C")],
      permutations: [try SymmetryPermutation(constantMapping: ["A": "B", "B": "C", "C": "A"])])
    #expect(derivation.group.count == 3)
    #expect(derivation.orbits.count == 1)
    #expect(derivation.orbits[0].count == 3)
  }

  @Test("Quotient projection deduplicates equivalent labeled raw edges")
  func quotientProjectionIsDeduplicated() throws {
    let rawStates = [state("A"), state("B")]
    let rawEdges = [
      CanonicalEdge(source: rawStates[0].key, action: "step", target: rawStates[1].key),
      CanonicalEdge(source: rawStates[1].key, action: "step", target: rawStates[0].key)
    ]
    let reducedStates = [state("A")]
    let reducedEdges = [CanonicalEdge(source: reducedStates[0].key, action: "step", target: reducedStates[0].key)]
    let swiftRawRun = try run(states: rawStates, edges: rawEdges)
    let tlcRawRun = try run(states: rawStates, edges: rawEdges)
    let swiftReducedRun = try run(states: reducedStates, edges: reducedEdges)
    let tlcReducedRun = try run(states: reducedStates, edges: reducedEdges)
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: "scope-2", runID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let input = try SymmetryOrbitComparisonInput(
      caseID: "scope-2", configuration: try TemporalSymmetryConfiguration(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true), correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, run: swiftRawRun),
      swiftReduced: try exploration(.swift, true, UUID(), run: swiftReducedRun),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, run: tlcRawRun),
      tlcReduced: try exploration(.tlc, true, UUID(), run: tlcReducedRun),
      swiftRawRun: swiftRawRun, swiftReducedRun: swiftReducedRun, tlcRawRun: tlcRawRun, tlcReducedRun: tlcReducedRun,
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutation(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])])
    guard case .exact(let comparison) = try SymmetryOrbitComparator().compare(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.quotientTransitions.count == 1)
  }

  @Test("Orbit evidence rejects colliding run identities")
  func orbitEvidenceRejectsCollidingRunIdentities() throws {
    let input = try fixture(reducedStates: [state("A")])
    let collidingSwiftReduced = try exploration(.swift, true, input.correlation.swiftRunID, states: [state("A")])
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: "scope-2", field: "symmetry pair configuration")) {
      _ = try SymmetryOrbitComparisonInput(
        caseID: input.caseID, configuration: input.configuration, correlation: input.correlation,
        swiftRaw: input.swiftRaw, swiftReduced: collidingSwiftReduced, tlcRaw: input.tlcRaw, tlcReduced: input.tlcReduced,
        swiftRawRun: input.swiftRawRun, swiftReducedRun: input.swiftReducedRun, tlcRawRun: input.tlcRawRun,
        tlcReducedRun: input.tlcReducedRun, configurationEvidence: input.configurationEvidence,
        quotientEvidence: input.quotientEvidence, permutations: input.permutations)
    }
  }

  private var digest: String { String(repeating: "a", count: 64) }

  private func state(_ member: String) -> CanonicalState {
    CanonicalState(bindings: ["members": .constant(member)])
  }

  private func run(states: [CanonicalState], edges: [CanonicalEdge]? = nil) throws -> CanonicalRun {
    let edges = edges ?? (states.count > 1
      ? [CanonicalEdge(source: states[0].key, action: "step", target: states[1].key)]
      : [CanonicalEdge(source: states[0].key, action: "step", target: states[0].key)])
    return try CanonicalRun(
      graph: CanonicalGraph(initialStates: [states[0]], states: states, edges: edges),
      observableActions: Set(edges.map(\.action)), outcome: .exhaustiveSuccess)
  }

  private func exploration(
    _ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID, states: [CanonicalState]
  ) throws -> SymmetryExploration {
    try exploration(engine, reduced, runID, run: try run(states: states))
  }

  private func exploration(
    _ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID, run: CanonicalRun
  ) throws -> SymmetryExploration {
    let transitions = try run.graph.edgeOccurrences.map { edge, occurrences in
      try SymmetryRawTransitionWitness(
        engine: engine, sourceStateID: edge.source.canonicalEncoding, action: edge.action,
        targetStateID: edge.target.canonicalEncoding, occurrences: occurrences)
    }
    return try SymmetryExploration(
      engine: engine, reduced: reduced, runID: runID, graphID: "\(engine.rawValue)-\(reduced)",
      initialStateIDs: run.graph.initialStateKeys.map(\.canonicalEncoding),
      stateIDs: run.graph.states.keys.map(\.canonicalEncoding),
      transitions: transitions,
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("\(engine.rawValue)-\(reduced).json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
  }

  private func fixture(
    reducedStates: [CanonicalState],
    tlcReducedStates: [CanonicalState]? = nil
  ) throws -> SymmetryOrbitComparisonInput {
    let rawStates = [state("A"), state("B")]
    let tlcReducedStates = tlcReducedStates ?? reducedStates
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: "scope-2", runID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    return try SymmetryOrbitComparisonInput(
      caseID: "scope-2", configuration: try TemporalSymmetryConfiguration(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true),
      correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, states: rawStates),
      swiftReduced: try exploration(.swift, true, UUID(), states: reducedStates),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, states: rawStates),
      tlcReduced: try exploration(.tlc, true, UUID(), states: tlcReducedStates),
      swiftRawRun: try run(states: rawStates), swiftReducedRun: try run(states: reducedStates),
      tlcRawRun: try run(states: rawStates), tlcReducedRun: try run(states: tlcReducedStates),
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutation(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])])
  }

  private func evidence(_ name: String) throws -> CoreEvidenceReference {
    try CoreEvidenceReference(path: "Verification/TemporalSymmetryConformance/\(name)", sha256: digest)
  }
}
