import Testing
import UpstreamParity

struct SymmetryOrbitConformanceTests {
  @Test("A reduced representative outside its declared orbit is rejected")
  func reducedRepresentativeOutsideOrbitIsRejected() throws {
    let input = try fixture(reducedStates: [state("C")])
    #expect(throws: SymmetryOrbitAdapterError.reducedStateOutsideOrbit(
      source: .swift,
      stateID: state("C").key.canonicalEncoding
    )) {
      _ = try compareSymmetryOrbits(input)
    }
  }

  @Test("Matched raw and reduced graphs produce canonical orbit evidence")
  func matchedGraphsProduceExactOrbitEvidence() throws {
    let input = try fixture(reducedStates: [state("A")])
    guard case .exact(let comparison) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.caseID == "scope-2")
    #expect(comparison.orbits.count == 1)
    #expect(comparison.orbits[0].members == [
      state("A").key.canonicalEncoding,
      state("B").key.canonicalEncoding
    ].sorted())
    #expect(comparison.orbits[0].semanticRepresentative == state("A").key.canonicalEncoding)
    #expect(comparison.quotientTransitions.count == 1)
  }

  @Test("Different executable representatives of the same orbit agree")
  func differentExecutableRepresentativesAgree() throws {
    let input = try fixture(reducedStates: [state("A")], tlcReducedStates: [state("B")])
    guard case .exact(let comparison) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.orbits[0].swiftExecutableRepresentative == state("A").key.canonicalEncoding)
    #expect(comparison.orbits[0].tlcExecutableRepresentative == state("B").key.canonicalEncoding)
  }

  @Test("Raw graph differences produce structured comparison differences")
  func rawGraphDifferenceIsStructured() throws {
    let rawStates = [state("A"), state("B")]
    let reducedStates = [state("A")]
    let input = try comparisonInput(
      swiftRaw: run(states: rawStates),
      swiftReduced: run(states: reducedStates),
      tlcRaw: run(states: [state("A")]),
      tlcReduced: run(states: reducedStates)
    )
    guard case .difference(let differences) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind).contains(.rawGraph))
  }

  @Test("Raw edge differences produce structured comparison differences")
  func rawEdgeDifferenceIsStructured() throws {
    let states = [state("A"), state("B")]
    let swiftRaw = try run(states: states)
    let tlcRaw = try run(states: states, edges: [
      CanonicalEdge(source: states[1].key, action: "step", target: states[0].key)
    ])
    let input = try comparisonInput(
      swiftRaw: swiftRaw,
      swiftReduced: run(states: [state("A")]),
      tlcRaw: tlcRaw,
      tlcReduced: run(states: [state("A")])
    )
    guard case .difference(let differences) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind).contains(.rawGraph))
  }

  @Test("Incomplete exploration cannot produce exact orbit evidence")
  func incompleteExplorationIsStructured() throws {
    let states = [state("A"), state("B")]
    let input = try comparisonInput(
      swiftRaw: run(states: states, outcome: .incomplete(reason: "state limit")),
      swiftReduced: run(states: [state("A")]),
      tlcRaw: run(states: states),
      tlcReduced: run(states: [state("A")])
    )
    guard case .difference(let differences) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind) == [.incompleteRun])
  }

  @Test("Reduced initial states must represent the raw initial orbits")
  func reducedInitialStateDifferenceIsStructured() throws {
    let rawStates = [state("A"), state("B"), state("Z")]
    let input = try comparisonInput(
      swiftRaw: run(states: rawStates),
      swiftReduced: run(states: [state("Z"), state("A")]),
      tlcRaw: run(states: rawStates),
      tlcReduced: run(states: [state("A"), state("Z")])
    )
    guard case .difference(let differences) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind) == [.reducedInitialStates])
  }

  @Test("Raw and reduced graphs retain the same observable names")
  func observableNameDifferenceIsStructured() throws {
    let rawStates = [state("A"), state("B")]
    let reducedState = state("A")
    let input = try comparisonInput(
      swiftRaw: run(states: rawStates),
      swiftReduced: run(states: [reducedState], edges: [CanonicalEdge(
        source: reducedState.key,
        action: "other",
        target: reducedState.key
      )]),
      tlcRaw: run(states: rawStates),
      tlcReduced: run(states: [reducedState])
    )
    guard case .difference(let differences) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected a structured difference")
      return
    }
    #expect(differences.map(\.kind) == [.observableNames])
  }

  @Test("Orbit derivation closes a generator group before partitioning states")
  func orbitDerivationUsesGeneratorClosure() throws {
    let derivation = try SymmetryOrbitDerivation(
      states: [state("A"), state("B"), state("C")],
      permutations: [try SymmetryPermutation(constantMapping: ["A": "B", "B": "C", "C": "A"])],
      maximumPermutationCount: 3
    )
    #expect(derivation.orbits.count == 1)
    #expect(derivation.orbits[0].count == 3)
  }

  @Test("Orbit derivation stops at the declared permutation limit")
  func orbitDerivationEnforcesPermutationLimit() throws {
    #expect(throws: SymmetryOrbitAdapterError.permutationLimitExceeded(required: 3, limit: 2)) {
      _ = try SymmetryOrbitDerivation(
        states: [state("A"), state("B"), state("C")],
        permutations: [try SymmetryPermutation(
          constantMapping: ["A": "B", "B": "C", "C": "A"]
        )],
        maximumPermutationCount: 2
      )
    }
  }

  @Test("Orbit derivation rejects duplicate states")
  func orbitDerivationRejectsDuplicateStates() throws {
    let duplicate = state("A")
    #expect(throws: CanonicalGraphError.duplicateState(duplicate.key)) {
      _ = try SymmetryOrbitDerivation(
        states: [duplicate, duplicate],
        permutations: [try SymmetryPermutation(constantMapping: ["A": "A"])],
        maximumPermutationCount: 1
      )
    }
  }

  @Test("Quotient projection deduplicates equivalent labeled raw edges")
  func quotientProjectionIsDeduplicated() throws {
    let rawStates = [state("A"), state("B")]
    let rawEdges = [
      CanonicalEdge(source: rawStates[0].key, action: "step", target: rawStates[1].key),
      CanonicalEdge(source: rawStates[1].key, action: "step", target: rawStates[0].key)
    ]
    let reducedState = state("A")
    let reducedEdges = [CanonicalEdge(
      source: reducedState.key,
      action: "step",
      target: reducedState.key
    )]
    let input = try comparisonInput(
      swiftRaw: run(states: rawStates, edges: rawEdges),
      swiftReduced: run(states: [reducedState], edges: reducedEdges),
      tlcRaw: run(states: rawStates, edges: rawEdges),
      tlcReduced: run(states: [reducedState], edges: reducedEdges)
    )
    guard case .exact(let comparison) = try compareSymmetryOrbits(input) else {
      Issue.record("Expected exact orbit comparison")
      return
    }
    #expect(comparison.quotientTransitions.count == 1)
  }

  private func state(_ member: String) -> CanonicalState {
    CanonicalState(bindings: ["members": .constant(member)])
  }

  private func run(
    states: [CanonicalState],
    edges: [CanonicalEdge]? = nil,
    outcome: GraphRunOutcome = .exhaustiveSuccess
  ) throws -> CompletedGraphRun {
    let edges = edges ?? (states.count > 1
      ? [CanonicalEdge(source: states[0].key, action: "step", target: states[1].key)]
      : [CanonicalEdge(source: states[0].key, action: "step", target: states[0].key)])
    return try CompletedGraphRun(
      graph: CanonicalGraph(initialStates: [states[0]], states: states, edges: edges),
      observableActions: Set(edges.map(\.action)),
      outcome: outcome
    )
  }

  private func fixture(
    reducedStates: [CanonicalState],
    tlcReducedStates: [CanonicalState]? = nil
  ) throws -> SymmetryOrbitComparisonInput {
    let rawStates = [state("A"), state("B")]
    return try comparisonInput(
      swiftRaw: run(states: rawStates),
      swiftReduced: run(states: reducedStates),
      tlcRaw: run(states: rawStates),
      tlcReduced: run(states: tlcReducedStates ?? reducedStates)
    )
  }

  private func comparisonInput(
    swiftRaw: CompletedGraphRun,
    swiftReduced: CompletedGraphRun,
    tlcRaw: CompletedGraphRun,
    tlcReduced: CompletedGraphRun
  ) throws -> SymmetryOrbitComparisonInput {
    try SymmetryOrbitComparisonInput(
      caseID: "scope-2",
      swiftRaw: swiftRaw,
      swiftReduced: swiftReduced,
      tlcRaw: tlcRaw,
      tlcReduced: tlcReduced,
      permutations: [
        try SymmetryPermutation(constantMapping: ["A": "A", "B": "B"]),
        try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])
      ],
      maximumPermutationCount: 2
    )
  }
}
