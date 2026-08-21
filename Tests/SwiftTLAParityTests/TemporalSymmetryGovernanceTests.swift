import Foundation
import Testing
import UpstreamParity

struct TemporalSymmetryGovernanceTests {
  @Test("P3 governance rejects unknown nested fields and duplicate IDs")
  func rejectsUnknownNestedFieldsAndDuplicateIDs() throws {
    let item = try temporalCase()
    let data = try JSONEncoder().encode(try TemporalSymmetryCases(cases: [item]))
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var cases = try #require(object["cases"] as? [[String: Any]])
    var configuration = try #require(cases[0]["configuration"] as? [String: Any])
    configuration["unknownNestedField"] = true
    cases[0]["configuration"] = configuration
    object["cases"] = cases
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "decode", field: "unknown field unknownNestedField")) {
      _ = try JSONDecoder().decode(TemporalSymmetryCases.self, from: JSONSerialization.data(withJSONObject: object))
    }
    #expect(throws: ConformanceGovernanceError.duplicateID(kind: "case", id: item.id)) {
      _ = try TemporalSymmetryCases(cases: [item, item])
    }
  }

  @Test("P3 cross-register validation binds kind, exact bounds, and permanent regressions")
  func crossRegisterValidationIsFailClosed() throws {
    let source = try temporalCase(id: "source", expectedOutcome: .exact)
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let cases = try TemporalSymmetryCases(cases: [source, regression])
    let record = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedger(records: [record])
    let entry = try TemporalSymmetrySupportSurfaceEntry(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [record.id])
    try TemporalSymmetrySupportSurface(entries: [entry]).validate(cases: cases, ledger: ledger)

    let mismatchedBounds = try TemporalSymmetrySupportSurfaceEntry(
      id: "wrong-bounds", behavior: "bounded temporal", kind: .temporal,
      finiteBounds: try CoreFiniteBounds(summary: "four states", limits: ["states": 4]),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [record.id])
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: "wrong-bounds", field: "mandatory case source")) {
      try TemporalSymmetrySupportSurface(entries: [mismatchedBounds]).validate(cases: cases, ledger: ledger)
    }

    let wrongKind = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id, kind: .symmetry)
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: wrongKind.id, field: "kind, provenance, regression, or bounds")) {
      try TemporalSymmetryDivergenceLedger(records: [wrongKind]).validate(cases: cases)
    }

    #expect(throws: ConformanceGovernanceError.invalidField(record: "difference", field: "latestComparison")) {
      _ = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id, disposition: .resolved)
    }
  }

  @Test("P3 temporal comparison records both results and accepts a shared violation")
  func temporalComparisonRequiresLassoOnlyForAvailableViolation() throws {
    let runID = UUID()
    let lasso = try TemporalLassoWitness(prefixStateIDs: ["i"], cycleStateIDs: ["a", "a"])
    let result = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .available,
      traceEvidence: try evidence("trace.json"), lasso: lasso)
    let comparison = try TemporalComparison(
      caseID: "temporal", configuration: try temporalConfiguration(),
      correlation: try correlation("temporal", runID), outcome: .exact, swiftResult: result, tlcResult: result,
      swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
      enablednessEvidence: try evidence("enabled.json"),
      fairComponents: [try TemporalRecurrentComponent(stateIDs: ["a"], reasonCode: .accepting)],
      rejectedComponents: [], diagnosticCode: .exactAgreement)
    #expect(comparison.swiftResult.lasso == lasso)

    let satisfied = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .notApplicable)
    let TLCViolationWithoutTrace = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .unavailable)
    _ = try TemporalComparison(
      caseID: "temporal", configuration: try temporalConfiguration(),
      correlation: try correlation("temporal", runID), outcome: .difference,
      swiftResult: satisfied, tlcResult: TLCViolationWithoutTrace,
      swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
      enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
      diagnosticCode: .propertyOutcomeDifference)
  }

  @Test("P3 complete graph declarations require distinct correlated retained artifacts")
  func completeGraphEvidenceIsRequiredAndBound() throws {
    let runID = UUID()
    let configuration = try TemporalSymmetryConfiguration(
      property: "[] P", fairness: TemporalFairnessMode.none,
      completeGraphPass: try TemporalCompleteGraphPassDeclaration(configuration: try evidence("graph.cfg")))
    let result = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: "temporal", field: "complete graph evidence")) {
      _ = try TemporalComparison(
        caseID: "temporal", configuration: configuration, correlation: try correlation("temporal", runID),
        outcome: .exact, swiftResult: result, tlcResult: result,
        swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
        enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: .exactAgreement)
    }
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: "complete graph evidence", field: "run IDs")) {
      _ = try TemporalCompleteGraphEvidence(
        propertyRunID: runID, graphRunID: runID, arguments: [], fingerprintPolynomial: 1,
        operatingSystem: "macos", architecture: "arm64", environment: [:], sourceInput: try evidence("spec.tla"),
        configuration: try evidence("graph.cfg"), graphEvents: try evidence("graph-events.jsonl"),
        result: try evidence("graph-result.json"))
    }
  }

  @Test("P3 symmetry comparison requires complete paired evidence and canonical orbits")
  func symmetryComparisonRequiresCompleteOrbits() throws {
    #expect(throws: ConformanceGovernanceError.invalidField(record: "orbit", field: "members or representative")) {
      _ = try SymmetryOrbit(
        members: ["b", "a"], semanticRepresentative: "b", swiftExecutableRepresentative: "a",
        tlcExecutableRepresentative: "b")
    }
    let orbit = try SymmetryOrbit(
      members: ["b", "a"], semanticRepresentative: "a", swiftExecutableRepresentative: "b",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let comparison = try SymmetryOrbitComparison(
      caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
      outcome: .exact, swiftRaw: try exploration(.swift, false, correlation.swiftRunID), swiftReduced: try exploration(.swift, true, UUID()),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID), tlcReduced: try exploration(.tlc, true, UUID()),
      configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
      orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
      quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
      diagnosticCode: .exactAgreement)
    #expect(comparison.orbits[0].size == 2)
  }

  @Test("P3 unavailable reasons always produce the unavailable exit class")
  func unavailableReasonsMapToUnavailableExit() throws {
    let unavailable: [TemporalSymmetryReasonCode] = [
      .missingPrerequisite, .missingEvidence, .partialEvidence, .foreignRun, .manifestDigestMismatch,
      .toolchainDigestMismatch, .configurationMismatch, .executionFailed, .missingReportIdentity
    ]
    for reason in unavailable {
      let entry = try TemporalSymmetryAdmissionEntry(
        supportID: reason.rawValue, decision: .blocked, reasonCodes: [reason],
        mandatoryCaseIDs: ["temporal"], divergenceIDs: [])
      let report = try admission(runID: UUID(), entries: [entry])
      #expect(report.finalExitClass == .unavailable)
    }
  }

  @Test("P3 admission rejects a report with no identity")
  func admissionRequiresReportIdentity() throws {
    let entry = try TemporalSymmetryAdmissionEntry(
      supportID: "supported", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: ["temporal"], divergenceIDs: [],
      evidence: [try evidence("comparison.json")], caseRunCorrelations: [try correlation("temporal", UUID())])
    let runID = entry.caseRunCorrelations[0].gateRunID
    let report = try admission(runID: runID, entries: [entry], admittedBounds: ["supported": try bounds()])
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    object.removeValue(forKey: "reportID")
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(TemporalSymmetryAdmission.self, from: JSONSerialization.data(withJSONObject: object))
    }
  }

  @Test("P3 temporal evidence keeps unavailable evaluation distinct from a property result")
  func unavailableTemporalEvaluationIsFailClosed() throws {
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "temporal result", field: "unavailable evaluation")) {
      _ = try TemporalPropertyResult(
        availability: .unavailable, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
        traceAvailability: .unavailable)
    }
    let unavailable = try TemporalPropertyResult(
      availability: .unavailable, outcome: nil, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .unavailable)
    let satisfied = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "temporal", field: "unavailable temporal result")) {
      _ = try TemporalComparison(
        caseID: "temporal", configuration: try temporalConfiguration(), correlation: try correlation("temporal", UUID()),
        outcome: .unavailable, swiftResult: unavailable, tlcResult: satisfied,
        swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
        enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: .exactAgreement)
    }
  }

  @Test("P3 correlations and temporal diagnostics cannot be silently mismatched")
  func correlationsAndDiagnosticsAreStrict() throws {
    let id = UUID()
    #expect(throws: ConformanceGovernanceError.invalidField(record: "correlation", field: "caseID")) {
      _ = try TemporalSymmetryCaseRunCorrelation(
        caseID: "temporal", gateRunID: id, swiftRunID: id, tlcRunID: UUID(), comparisonRunID: UUID())
    }
    let result = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: ConformanceGovernanceError.invalidField(record: "temporal", field: "exact temporal result")) {
      _ = try TemporalComparison(
        caseID: "temporal", configuration: try temporalConfiguration(), correlation: try correlation("temporal", UUID()),
        outcome: .exact, swiftResult: result, tlcResult: result,
        swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
        enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: .propertyOutcomeDifference)
    }
  }

}

extension TemporalSymmetryGovernanceTests {
  @Test("P3 symmetry evidence requires a complete orbit partition and all graph relations")
  func symmetryEvidenceCannotOmitStatesOrTransitions() throws {
    let orbit = try SymmetryOrbit(
      members: ["a", "b"], semanticRepresentative: "a", swiftExecutableRepresentative: "a",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let swiftRaw = try exploration(.swift, false, correlation.swiftRunID)
    let swiftReduced = try exploration(.swift, true, UUID())
    let tlcRaw = try exploration(.tlc, false, correlation.tlcRunID)
    let tlcReduced = try exploration(.tlc, true, UUID())
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "symmetry", field: "orbit witnesses or quotient")) {
      _ = try SymmetryOrbitComparison(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: swiftRaw, swiftReduced: swiftReduced, tlcRaw: tlcRaw, tlcReduced: tlcReduced,
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift)],
        quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }
    let incompleteRaw = try SymmetryExploration(
      engine: .swift, reduced: false, runID: correlation.swiftRunID, graphID: "swift-raw", initialStateIDs: ["a"], stateIDs: ["a"],
      transitions: [try witness(.swift, source: "a", target: "a")], declaredConfigurationSHA256: digest,
      graphEvidence: try evidence("incomplete.json"), invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "symmetry", field: "complete orbit partition")) {
      _ = try SymmetryOrbitComparison(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: incompleteRaw, swiftReduced: swiftReduced, tlcRaw: tlcRaw, tlcReduced: tlcReduced,
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift, source: "a", target: "a"), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }
  }

  @Test("P3 symmetry comparisons require independent exploration runs and real differences")
  func symmetryRunCorrelationAndDifferenceDiagnosticAreStrict() throws {
    let orbit = try SymmetryOrbit(
      members: ["a", "b"], semanticRepresentative: "a", swiftExecutableRepresentative: "a",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let sharedReducedRun = UUID()
    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "symmetry", field: "exploration run correlation")) {
      _ = try SymmetryOrbitComparison(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: try exploration(.swift, false, correlation.swiftRunID),
        swiftReduced: try exploration(.swift, true, sharedReducedRun),
        tlcRaw: try exploration(.tlc, false, correlation.tlcRunID),
        tlcReduced: try exploration(.tlc, true, sharedReducedRun),
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }

    #expect(throws: ConformanceGovernanceError.invalidField(
      record: "symmetry", field: "symmetry difference diagnostic")) {
      _ = try SymmetryOrbitComparison(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .difference, swiftRaw: try exploration(.swift, false, correlation.swiftRunID),
        swiftReduced: try exploration(.swift, true, UUID()),
        tlcRaw: try exploration(.tlc, false, correlation.tlcRunID),
        tlcReduced: try exploration(.tlc, true, UUID()),
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .graphIdentityDifference)
    }

    let reducedRun = UUID()
    let changedReduced = try SymmetryExploration(
      engine: .swift, reduced: true, runID: reducedRun, graphID: "swift-reduced-difference", initialStateIDs: ["a"],
      stateIDs: ["a"], transitions: [try SymmetryRawTransitionWitness(engine: .swift, sourceStateID: "a", action: "other", targetStateID: "a", occurrences: 1)],
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("swift-reduced-difference.json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
    let structuredDifference = try SymmetryOrbitComparison(
      caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
      outcome: .difference, swiftRaw: try exploration(.swift, false, correlation.swiftRunID), swiftReduced: changedReduced,
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID), tlcReduced: try exploration(.tlc, true, UUID()),
      configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
      orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
      quotientTransitions: [try SymmetryQuotientTransition(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
      diagnosticCode: .graphIdentityDifference)
    #expect(structuredDifference.outcome == .difference)
  }

  @Test("P3 admission reports cover the support register exactly")
  func admissionCoveragePreventsEmptyOmittedDowngradedAndArbitraryEntries() throws {
    let source = try temporalCase(id: "source")
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let cases = try TemporalSymmetryCases(cases: [source, regression])
    let divergence = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedger(records: [divergence])
    let support = try TemporalSymmetrySupportSurfaceEntry(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [divergence.id])
    let surface = try TemporalSymmetrySupportSurface(entries: [support])
    #expect(throws: ConformanceGovernanceError.invalidField(record: "admission", field: "entries")) {
      _ = try admission(runID: UUID(), entries: [])
    }

    let admitted = try TemporalSymmetryAdmissionEntry(
      supportID: support.id, decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id], evidence: [try evidence("comparison.json")],
      caseRunCorrelations: [try correlation(source.id, UUID())])
    let report = try admission(
      runID: admitted.caseRunCorrelations[0].gateRunID, entries: [admitted], admittedBounds: [support.id: try bounds()])
    try report.validate(supportSurface: surface, cases: cases, ledger: ledger)

    let arbitrary = try TemporalSymmetryAdmissionEntry(
      supportID: "arbitrary", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id], evidence: [try evidence("comparison.json")],
      caseRunCorrelations: [try correlation(source.id, UUID())])
    let arbitraryReport = try admission(
      runID: arbitrary.caseRunCorrelations[0].gateRunID, entries: [arbitrary], admittedBounds: ["arbitrary": try bounds()])
    #expect(throws: ConformanceGovernanceError.invalidField(record: "admission", field: "support entry coverage")) {
      try arbitraryReport.validate(supportSurface: surface, cases: cases, ledger: ledger)
    }

    let downgraded = try TemporalSymmetryAdmissionEntry(
      supportID: support.id, decision: .unsupported, reasonCodes: [.explicitlyUnsupported], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id])
    let downgradedReport = try admission(runID: UUID(), entries: [downgraded])
    #expect(throws: ConformanceGovernanceError.invalidField(record: support.id, field: "requested entry downgraded")) {
      try downgradedReport.validate(supportSurface: surface, cases: cases, ledger: ledger)
    }
  }

  @Test("P3 support entries link divergences to their own kind and required provenance case")
  func divergenceLinksCannotPointOutsideMandatoryCases() throws {
    let source = try temporalCase(id: "source")
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let unrelated = try temporalCase(id: "unrelated")
    let cases = try TemporalSymmetryCases(cases: [source, regression, unrelated])
    let divergence = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedger(records: [divergence])
    let entry = try TemporalSymmetrySupportSurfaceEntry(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [unrelated.id], requestedStatus: .requested,
      linkedDivergenceIDs: [divergence.id])
    #expect(throws: ConformanceGovernanceError.inconsistentReference(
      record: entry.id, field: "linked divergence difference")) {
      try TemporalSymmetrySupportSurface(entries: [entry]).validate(cases: cases, ledger: ledger)
    }
  }

  private var digest: String { String(repeating: "a", count: 64) }

  private func bounds() throws -> CoreFiniteBounds {
    try CoreFiniteBounds(summary: "three states", limits: ["states": 3])
  }

  private func evidence(_ path: String) throws -> CoreEvidenceReference {
    try CoreEvidenceReference(path: "Verification/TemporalSymmetryConformance/\(path)", sha256: digest)
  }

  private func temporalConfiguration() throws -> TemporalSymmetryConfiguration {
    try TemporalSymmetryConfiguration(property: "[] P", fairness: TemporalFairnessMode.none)
  }

  private func symmetryConfiguration() throws -> TemporalSymmetryConfiguration {
    try TemporalSymmetryConfiguration(symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true)
  }

  private func correlation(_ caseID: String, _ gateRunID: UUID) throws -> TemporalSymmetryCaseRunCorrelation {
    try TemporalSymmetryCaseRunCorrelation(
      caseID: caseID, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
  }

  private func temporalCase(id: String = "temporal", expectedOutcome: TemporalSymmetryExpectedOutcome = .exact) throws -> TemporalSymmetryCase {
    try TemporalSymmetryCase(
      id: id, kind: .temporal, swiftSpec: "TemporalFixture",
      provenance: try CoreEvidenceProvenance(
        caseID: id, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge", bridgeSourceSHA256: digest,
        bridgeBinarySHA256: digest),
      finiteBounds: try bounds(), semanticCitations: ["TLA+ temporal logic"], sourceInput: try evidence("\(id).tla"),
      configuration: try temporalConfiguration(), expectedOutcome: expectedOutcome)
  }

  private func divergenceRecord(
    provenanceCaseID: String, regressionCaseID: String, kind: TemporalSymmetryCaseKind = .temporal,
    disposition: ConformanceDivergenceDisposition = .open
  ) throws -> TemporalSymmetryDivergenceRecord {
    try TemporalSymmetryDivergenceRecord(
      id: "difference", kind: kind,
      provenance: try CoreEvidenceProvenance(
        caseID: provenanceCaseID, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge", bridgeSourceSHA256: digest,
        bridgeBinarySHA256: digest),
      semanticCitations: ["TLA+ temporal logic"], reproducer: try bounds(), originalEvidence: try evidence("original.json"),
      permanentRegressionCaseID: regressionCaseID, classification: .swiftTLADefect, disposition: disposition,
      normalizedDifferenceDigest: "difference", latestComparison: try TemporalSymmetryDivergenceComparison(
        evidence: try evidence("latest.json"), outcome: .difference, normalizedDifferenceDigest: "difference"))
  }

  private func exploration(_ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID) throws -> SymmetryExploration {
    let states = reduced ? ["a"] : ["a", "b"]
    let transition = reduced
      ? try witness(engine, source: "a", target: "a")
      : try witness(engine, source: "a", target: "b")
    return try SymmetryExploration(
      engine: engine, reduced: reduced, runID: runID, graphID: "\(engine.rawValue)-\(reduced)", initialStateIDs: ["a"],
      stateIDs: states, transitions: [transition],
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("\(engine.rawValue)-\(reduced).json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
  }

  private func witness(
    _ engine: SymmetryExplorationEngine, source: String = "a", target: String = "b"
  ) throws -> SymmetryRawTransitionWitness {
    try SymmetryRawTransitionWitness(engine: engine, sourceStateID: source, action: "step", targetStateID: target, occurrences: 1)
  }

  private func admission(
    runID: UUID, entries: [TemporalSymmetryAdmissionEntry], admittedBounds: [String: CoreFiniteBounds] = [:]
  ) throws -> TemporalSymmetryAdmission {
    try TemporalSymmetryAdmission(
      reportID: UUID(), gateRunID: runID,
      coreAdmission: try TemporalSymmetryCoreAdmissionReference(
        reportID: UUID(), gateRunID: UUID(), report: try evidence("core-admission.json")),
      manifestSHA256: digest, toolchainSHA256: digest, entries: entries, admittedBounds: admittedBounds,
      unexplainedDivergenceCount: 0,
      finalExitClass: entries.contains { $0.reasonCodes.contains(where: \.makesEvaluationUnavailable) }
        ? .unavailable
        : (entries.contains { $0.decision == .blocked } ? .blocked : .success))
  }
}
