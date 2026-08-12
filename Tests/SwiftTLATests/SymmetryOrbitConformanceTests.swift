import Foundation
import Testing
import UpstreamParity

struct SymmetryOrbitConformanceTests {
  @Test("A reduced representative outside its declared orbit is rejected")
  func reducedRepresentativeOutsideOrbitIsRejected() throws {
    let input = try fixture(reducedStates: [state("C")])
    #expect(throws: SymmetryOrbitAdapterErrorV1.reducedStateOutsideOrbit(engine: .swift, stateID: state("C").key.canonicalEncoding)) {
      _ = try SymmetryOrbitComparatorV1().compare(input)
    }
  }

  @Test("Matched pinned raw and reduced graphs produce complete canonical orbit evidence")
  func matchedGraphsProduceExactOrbitEvidence() throws {
    let input = try fixture(reducedStates: [state("A")])
    let result = try SymmetryOrbitComparatorV1().compare(input)
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

  @Test("Raw state-set differences produce structured comparison differences")
  func rawStateSetDifferenceIsStructured() throws {
    let rawStates = [state("A"), state("B")]
    let reducedStates = [state("A")]
    let correlation = try TemporalSymmetryCaseRunCorrelationV1(
      caseID: "scope-2", gateRunID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let input = try SymmetryOrbitComparisonInputV1(
      caseID: "scope-2", configuration: try TemporalSymmetryConfigurationV1(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true), correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, states: rawStates),
      swiftReduced: try exploration(.swift, true, UUID(), states: reducedStates),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, states: [state("A")]),
      tlcReduced: try exploration(.tlc, true, UUID(), states: reducedStates),
      swiftRawRun: try run(states: rawStates), swiftReducedRun: try run(states: reducedStates),
      tlcRawRun: try run(states: [state("A")]), tlcReducedRun: try run(states: reducedStates),
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutationV1(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutationV1(constantMapping: ["A": "B", "B": "A"])])
    let result = try SymmetryOrbitComparatorV1().compare(input)
    guard case .difference(let differences) = result else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind) == [.rawStateSet])
  }

  @Test("Orbit derivation closes a generator group before partitioning states")
  func orbitDerivationUsesGeneratorClosure() throws {
    let derivation = try SymmetryOrbitDerivationV1(
      states: [state("A"), state("B"), state("C")],
      permutations: [try SymmetryPermutationV1(constantMapping: ["A": "B", "B": "C", "C": "A"])])
    #expect(derivation.group.count == 3)
    #expect(derivation.orbits.count == 1)
    #expect(derivation.orbits[0].count == 3)
  }

  @Test("Quotient projection deduplicates equivalent labeled raw edges")
  func quotientProjectionIsDeduplicated() throws {
    let rawStates = [state("A"), state("B")]
    let rawEdges = [
      CanonicalEdgeV1(source: rawStates[0].key, action: "step", target: rawStates[1].key),
      CanonicalEdgeV1(source: rawStates[1].key, action: "step", target: rawStates[0].key)
    ]
    let reducedStates = [state("A")]
    let reducedEdges = [CanonicalEdgeV1(source: reducedStates[0].key, action: "step", target: reducedStates[0].key)]
    let swiftRawRun = try run(states: rawStates, edges: rawEdges)
    let tlcRawRun = try run(states: rawStates, edges: rawEdges)
    let swiftReducedRun = try run(states: reducedStates, edges: reducedEdges)
    let tlcReducedRun = try run(states: reducedStates, edges: reducedEdges)
    let correlation = try TemporalSymmetryCaseRunCorrelationV1(
      caseID: "scope-2", gateRunID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let input = try SymmetryOrbitComparisonInputV1(
      caseID: "scope-2", configuration: try TemporalSymmetryConfigurationV1(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true), correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, run: swiftRawRun),
      swiftReduced: try exploration(.swift, true, UUID(), run: swiftReducedRun),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, run: tlcRawRun),
      tlcReduced: try exploration(.tlc, true, UUID(), run: tlcReducedRun),
      swiftRawRun: swiftRawRun, swiftReducedRun: swiftReducedRun, tlcRawRun: tlcRawRun, tlcReducedRun: tlcReducedRun,
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutationV1(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutationV1(constantMapping: ["A": "B", "B": "A"])])
    guard case .exact(let comparison) = try SymmetryOrbitComparatorV1().compare(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.quotientTransitions.count == 1)
  }

  @Test("Orbit evidence rejects colliding run identities and invalid TLC provenance")
  func orbitEvidenceRejectsInvalidRunCorrelation() throws {
    let input = try fixture(reducedStates: [state("A")])
    let collidingSwiftReduced = try exploration(.swift, true, input.correlation.swiftRunID, states: [state("A")])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: "scope-2", field: "symmetry pair configuration")) {
      _ = try SymmetryOrbitComparisonInputV1(
        caseID: input.caseID, configuration: input.configuration, correlation: input.correlation,
        swiftRaw: input.swiftRaw, swiftReduced: collidingSwiftReduced, tlcRaw: input.tlcRaw, tlcReduced: input.tlcReduced,
        swiftRawRun: input.swiftRawRun, swiftReducedRun: input.swiftReducedRun, tlcRawRun: input.tlcRawRun,
        tlcReducedRun: input.tlcReducedRun, configurationEvidence: input.configurationEvidence,
        quotientEvidence: input.quotientEvidence, permutations: input.permutations)
    }
    let identifier = UUID()
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "scope-2", field: "TLC raw/reduced run correlation")) {
      _ = try PinnedSymmetryTLCCorrelationV1(
        caseID: "scope-2", gateRunID: identifier, comparisonRunID: UUID(), rawRunID: identifier, reducedRunID: UUID())
    }
  }

  private var digest: String { String(repeating: "a", count: 64) }

  private func state(_ member: String) -> CanonicalStateV1 {
    CanonicalStateV1(bindings: ["members": .constant(member)])
  }

  private func run(states: [CanonicalStateV1], edges: [CanonicalEdgeV1]? = nil) throws -> CanonicalRunV1 {
    let edges = edges ?? (states.count > 1
      ? [CanonicalEdgeV1(source: states[0].key, action: "step", target: states[1].key)]
      : [CanonicalEdgeV1(source: states[0].key, action: "step", target: states[0].key)])
    return try CanonicalRunV1(
      graph: CanonicalGraphV1(initialStates: [states[0]], states: states, edges: edges),
      observableActions: Set(edges.map(\.action)), outcome: .exhaustiveSuccess)
  }

  private func exploration(
    _ engine: SymmetryExplorationEngineV1, _ reduced: Bool, _ runID: UUID, states: [CanonicalStateV1]
  ) throws -> SymmetryExplorationV1 {
    try exploration(engine, reduced, runID, run: try run(states: states))
  }

  private func exploration(
    _ engine: SymmetryExplorationEngineV1, _ reduced: Bool, _ runID: UUID, run: CanonicalRunV1
  ) throws -> SymmetryExplorationV1 {
    let transitions = run.graph.edgeOccurrences.keys.map {
      try! SymmetryRawTransitionWitnessV1(
        engine: engine, sourceStateID: $0.source.canonicalEncoding, action: $0.action,
        targetStateID: $0.target.canonicalEncoding)
    }
    return try SymmetryExplorationV1(
      engine: engine, reduced: reduced, runID: runID, graphID: "\(engine.rawValue)-\(reduced)",
      initialStateIDs: run.graph.initialStateKeys.map(\.canonicalEncoding),
      stateIDs: run.graph.states.keys.map(\.canonicalEncoding),
      transitions: transitions,
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("\(engine.rawValue)-\(reduced).json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
  }

  private func fixture(reducedStates: [CanonicalStateV1]) throws -> SymmetryOrbitComparisonInputV1 {
    let rawStates = [state("A"), state("B")]
    let correlation = try TemporalSymmetryCaseRunCorrelationV1(
      caseID: "scope-2", gateRunID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    return try SymmetryOrbitComparisonInputV1(
      caseID: "scope-2", configuration: try TemporalSymmetryConfigurationV1(
        symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true),
      correlation: correlation,
      swiftRaw: try exploration(.swift, false, correlation.swiftRunID, states: rawStates),
      swiftReduced: try exploration(.swift, true, UUID(), states: reducedStates),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID, states: rawStates),
      tlcReduced: try exploration(.tlc, true, UUID(), states: reducedStates),
      swiftRawRun: try run(states: rawStates), swiftReducedRun: try run(states: reducedStates),
      tlcRawRun: try run(states: rawStates), tlcReducedRun: try run(states: reducedStates),
      configurationEvidence: try evidence("config.json"), quotientEvidence: try evidence("quotient.json"),
      permutations: [try SymmetryPermutationV1(constantMapping: ["A": "A", "B": "B"]),
                     try SymmetryPermutationV1(constantMapping: ["A": "B", "B": "A"])])
  }

  private func evidence(_ name: String) throws -> CoreEvidenceReferenceV1 {
    try CoreEvidenceReferenceV1(path: "Verification/TemporalSymmetryConformance/\(name)", sha256: digest)
  }
}
