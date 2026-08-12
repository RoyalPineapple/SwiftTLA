import Foundation
import Testing
import UpstreamParity

struct TemporalSymmetryGovernanceTests {
  @Test("P3 governance rejects unknown nested fields and duplicate IDs")
  func rejectsUnknownNestedFieldsAndDuplicateIDs() throws {
    let item = try temporalCase()
    let data = try JSONEncoder().encode(try TemporalSymmetryCasesV1(cases: [item]))
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var cases = try #require(object["cases"] as? [[String: Any]])
    var configuration = try #require(cases[0]["configuration"] as? [String: Any])
    configuration["unknownNestedField"] = true
    cases[0]["configuration"] = configuration
    object["cases"] = cases
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "decode", field: "unknown field unknownNestedField")) {
      _ = try JSONDecoder().decode(TemporalSymmetryCasesV1.self, from: JSONSerialization.data(withJSONObject: object))
    }
    #expect(throws: TemporalSymmetryGovernanceErrorV1.duplicateID(kind: "case", id: item.id)) {
      _ = try TemporalSymmetryCasesV1(cases: [item, item])
    }
  }

  @Test("P3 cross-register validation binds kind, exact bounds, and permanent regressions")
  func crossRegisterValidationIsFailClosed() throws {
    let source = try temporalCase(id: "source", expectedOutcome: .exact)
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let cases = try TemporalSymmetryCasesV1(cases: [source, regression])
    let record = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedgerV1(records: [record])
    let entry = try TemporalSymmetrySupportSurfaceEntryV1(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [record.id])
    try TemporalSymmetrySupportSurfaceV1(entries: [entry]).validate(cases: cases, ledger: ledger)

    let mismatchedBounds = try TemporalSymmetrySupportSurfaceEntryV1(
      id: "wrong-bounds", behavior: "bounded temporal", kind: .temporal,
      finiteBounds: try CoreFiniteBoundsV1(summary: "four states", limits: ["states": 4]),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [record.id])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: "wrong-bounds", field: "mandatory case source")) {
      try TemporalSymmetrySupportSurfaceV1(entries: [mismatchedBounds]).validate(cases: cases, ledger: ledger)
    }

    let wrongKind = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id, kind: .symmetry)
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: wrongKind.id, field: "kind, provenance, regression, or bounds")) {
      try TemporalSymmetryDivergenceLedgerV1(records: [wrongKind]).validate(cases: cases)
    }

    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "difference", field: "latestComparison")) {
      _ = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id, disposition: .resolved)
    }
  }

  @Test("P3 temporal comparison records both results and accepts a shared violation")
  func temporalComparisonRequiresLassoOnlyForAvailableViolation() throws {
    let runID = UUID()
    let lasso = try TemporalLassoWitnessV1(prefixStateIDs: ["i"], cycleStateIDs: ["a", "a"])
    let result = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .available,
      traceEvidence: try evidence("trace.json"), lasso: lasso)
    let comparison = try TemporalComparisonV1(
      caseID: "temporal", configuration: try temporalConfiguration(),
      correlation: try correlation("temporal", runID), outcome: .exact, swiftResult: result, tlcResult: result,
      swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
      enablednessEvidence: try evidence("enabled.json"),
      fairComponents: [try TemporalRecurrentComponentV1(stateIDs: ["a"], reasonCode: .accepting)],
      rejectedComponents: [], diagnosticCode: .exactAgreement)
    #expect(comparison.swiftResult.lasso == lasso)

    let satisfied = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .notApplicable)
    let TLCViolationWithoutTrace = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"], traceAvailability: .unavailable)
    _ = try TemporalComparisonV1(
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
    let configuration = try TemporalSymmetryConfigurationV1(
      property: "[] P", fairness: TemporalFairnessModeV1.none,
      completeGraphPass: try TemporalCompleteGraphPassDeclarationV1(configuration: try evidence("graph.cfg")))
    let result = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: "temporal", field: "complete graph evidence")) {
      _ = try TemporalComparisonV1(
        caseID: "temporal", configuration: configuration, correlation: try correlation("temporal", runID),
        outcome: .exact, swiftResult: result, tlcResult: result,
        swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
        enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: .exactAgreement)
    }
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: "complete graph evidence", field: "run IDs")) {
      _ = try TemporalCompleteGraphEvidenceV1(
        propertyRunID: runID, graphRunID: runID, arguments: [], fingerprintPolynomial: 1,
        operatingSystem: "macos", architecture: "arm64", environment: [:], sourceInput: try evidence("spec.tla"),
        configuration: try evidence("graph.cfg"), graphEvents: try evidence("graph-events.jsonl"),
        result: try evidence("graph-result.json"))
    }
  }

  @Test("P3 symmetry comparison requires complete paired evidence and canonical orbits")
  func symmetryComparisonRequiresCompleteOrbits() throws {
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "orbit", field: "members or representative")) {
      _ = try SymmetryOrbitV1(
        members: ["b", "a"], semanticRepresentative: "b", swiftExecutableRepresentative: "a",
        tlcExecutableRepresentative: "b")
    }
    let orbit = try SymmetryOrbitV1(
      members: ["b", "a"], semanticRepresentative: "a", swiftExecutableRepresentative: "b",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let comparison = try SymmetryOrbitComparisonV1(
      caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
      outcome: .exact, swiftRaw: try exploration(.swift, false, correlation.swiftRunID), swiftReduced: try exploration(.swift, true, UUID()),
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID), tlcReduced: try exploration(.tlc, true, UUID()),
      configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
      orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
      quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
      diagnosticCode: .exactAgreement)
    #expect(comparison.orbits[0].size == 2)
  }

  @Test("P3 unavailable reasons always produce the unavailable exit class")
  func unavailableReasonsMapToUnavailableExit() throws {
    let unavailable: [TemporalSymmetryReasonCodeV1] = [
      .missingPrerequisite, .missingEvidence, .partialEvidence, .foreignRun, .manifestDigestMismatch,
      .toolchainDigestMismatch, .configurationMismatch, .executionFailed, .missingReportIdentity
    ]
    for reason in unavailable {
      let entry = try TemporalSymmetryAdmissionEntryV1(
        supportID: reason.rawValue, decision: .blocked, reasonCodes: [reason],
        mandatoryCaseIDs: ["temporal"], divergenceIDs: [])
      let report = try admission(runID: UUID(), entries: [entry])
      #expect(report.finalExitClass == .unavailable)
    }
  }

  @Test("P3 admission rejects a report with no identity")
  func admissionRequiresReportIdentity() throws {
    let entry = try TemporalSymmetryAdmissionEntryV1(
      supportID: "supported", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: ["temporal"], divergenceIDs: [],
      evidence: [try evidence("comparison.json")], caseRunCorrelations: [try correlation("temporal", UUID())])
    let runID = entry.caseRunCorrelations[0].gateRunID
    let report = try admission(runID: runID, entries: [entry], admittedBounds: ["supported": try bounds()])
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    object.removeValue(forKey: "reportID")
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(TemporalSymmetryAdmissionV1.self, from: JSONSerialization.data(withJSONObject: object))
    }
  }

  @Test("P3 temporal evidence keeps unavailable evaluation distinct from a property result")
  func unavailableTemporalEvaluationIsFailClosed() throws {
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "temporal result", field: "unavailable evaluation")) {
      _ = try TemporalPropertyResultV1(
        availability: .unavailable, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
        traceAvailability: .unavailable)
    }
    let unavailable = try TemporalPropertyResultV1(
      availability: .unavailable, outcome: nil, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .unavailable)
    let satisfied = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "temporal", field: "unavailable temporal result")) {
      _ = try TemporalComparisonV1(
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
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "correlation", field: "caseID")) {
      _ = try TemporalSymmetryCaseRunCorrelationV1(
        caseID: "temporal", gateRunID: id, swiftRunID: id, tlcRunID: UUID(), comparisonRunID: UUID())
    }
    let result = try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
      traceAvailability: .notApplicable)
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal", field: "exact temporal result")) {
      _ = try TemporalComparisonV1(
        caseID: "temporal", configuration: try temporalConfiguration(), correlation: try correlation("temporal", UUID()),
        outcome: .exact, swiftResult: result, tlcResult: result,
        swiftEvidence: try evidence("swift.json"), tlcEvidence: try evidence("tlc.json"),
        enablednessEvidence: try evidence("enabled.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: .propertyOutcomeDifference)
    }
  }

  @Test("P3 symmetry evidence requires a complete orbit partition and all graph relations")
  func symmetryEvidenceCannotOmitStatesOrTransitions() throws {
    let orbit = try SymmetryOrbitV1(
      members: ["a", "b"], semanticRepresentative: "a", swiftExecutableRepresentative: "a",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let swiftRaw = try exploration(.swift, false, correlation.swiftRunID)
    let swiftReduced = try exploration(.swift, true, UUID())
    let tlcRaw = try exploration(.tlc, false, correlation.tlcRunID)
    let tlcReduced = try exploration(.tlc, true, UUID())
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "symmetry", field: "orbit witnesses or quotient")) {
      _ = try SymmetryOrbitComparisonV1(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: swiftRaw, swiftReduced: swiftReduced, tlcRaw: tlcRaw, tlcReduced: tlcReduced,
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift)],
        quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }
    let incompleteRaw = try SymmetryExplorationV1(
      engine: .swift, reduced: false, runID: correlation.swiftRunID, graphID: "swift-raw", initialStateIDs: ["a"], stateIDs: ["a"],
      transitions: [try witness(.swift, source: "a", target: "a")], declaredConfigurationSHA256: digest,
      graphEvidence: try evidence("incomplete.json"), invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "symmetry", field: "complete orbit partition")) {
      _ = try SymmetryOrbitComparisonV1(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: incompleteRaw, swiftReduced: swiftReduced, tlcRaw: tlcRaw, tlcReduced: tlcReduced,
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift, source: "a", target: "a"), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }
  }

  @Test("P3 symmetry comparisons require independent exploration runs and real differences")
  func symmetryRunCorrelationAndDifferenceDiagnosticAreStrict() throws {
    let orbit = try SymmetryOrbitV1(
      members: ["a", "b"], semanticRepresentative: "a", swiftExecutableRepresentative: "a",
      tlcExecutableRepresentative: "a")
    let correlation = try correlation("symmetry", UUID())
    let sharedReducedRun = UUID()
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "symmetry", field: "exploration run correlation")) {
      _ = try SymmetryOrbitComparisonV1(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .exact, swiftRaw: try exploration(.swift, false, correlation.swiftRunID),
        swiftReduced: try exploration(.swift, true, sharedReducedRun),
        tlcRaw: try exploration(.tlc, false, correlation.tlcRunID),
        tlcReduced: try exploration(.tlc, true, sharedReducedRun),
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .exactAgreement)
    }

    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(
      record: "symmetry", field: "symmetry difference diagnostic")) {
      _ = try SymmetryOrbitComparisonV1(
        caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
        outcome: .difference, swiftRaw: try exploration(.swift, false, correlation.swiftRunID),
        swiftReduced: try exploration(.swift, true, UUID()),
        tlcRaw: try exploration(.tlc, false, correlation.tlcRunID),
        tlcReduced: try exploration(.tlc, true, UUID()),
        configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
        orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
        quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
        diagnosticCode: .graphIdentityDifference)
    }

    let reducedRun = UUID()
    let changedReduced = try SymmetryExplorationV1(
      engine: .swift, reduced: true, runID: reducedRun, graphID: "swift-reduced-difference", initialStateIDs: ["a"],
      stateIDs: ["a"], transitions: [try SymmetryRawTransitionWitnessV1(engine: .swift, sourceStateID: "a", action: "other", targetStateID: "a")],
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("swift-reduced-difference.json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
    let structuredDifference = try SymmetryOrbitComparisonV1(
      caseID: "symmetry", configuration: try symmetryConfiguration(), correlation: correlation,
      outcome: .difference, swiftRaw: try exploration(.swift, false, correlation.swiftRunID), swiftReduced: changedReduced,
      tlcRaw: try exploration(.tlc, false, correlation.tlcRunID), tlcReduced: try exploration(.tlc, true, UUID()),
      configurationEvidence: try evidence("configuration.json"), quotientEvidence: try evidence("quotient.json"),
      orbits: [orbit], rawTransitionWitnesses: [try witness(.swift), try witness(.tlc)],
      quotientTransitions: [try SymmetryQuotientTransitionV1(sourceRepresentative: "a", action: "step", targetRepresentative: "a")],
      diagnosticCode: .graphIdentityDifference)
    #expect(structuredDifference.outcome == .difference)
  }

  @Test("P3 admission reports cover the support register exactly")
  func admissionCoveragePreventsEmptyOmittedDowngradedAndArbitraryEntries() throws {
    let source = try temporalCase(id: "source")
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let cases = try TemporalSymmetryCasesV1(cases: [source, regression])
    let divergence = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedgerV1(records: [divergence])
    let support = try TemporalSymmetrySupportSurfaceEntryV1(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [source.id], requestedStatus: .requested,
      linkedDivergenceIDs: [divergence.id])
    let surface = try TemporalSymmetrySupportSurfaceV1(entries: [support])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "admission", field: "entries")) {
      _ = try admission(runID: UUID(), entries: [])
    }

    let admitted = try TemporalSymmetryAdmissionEntryV1(
      supportID: support.id, decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id], evidence: [try evidence("comparison.json")],
      caseRunCorrelations: [try correlation(source.id, UUID())])
    let report = try admission(
      runID: admitted.caseRunCorrelations[0].gateRunID, entries: [admitted], admittedBounds: [support.id: try bounds()])
    try report.validate(supportSurface: surface, cases: cases, ledger: ledger)

    let arbitrary = try TemporalSymmetryAdmissionEntryV1(
      supportID: "arbitrary", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id], evidence: [try evidence("comparison.json")],
      caseRunCorrelations: [try correlation(source.id, UUID())])
    let arbitraryReport = try admission(
      runID: arbitrary.caseRunCorrelations[0].gateRunID, entries: [arbitrary], admittedBounds: ["arbitrary": try bounds()])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: "admission", field: "support entry coverage")) {
      try arbitraryReport.validate(supportSurface: surface, cases: cases, ledger: ledger)
    }

    let downgraded = try TemporalSymmetryAdmissionEntryV1(
      supportID: support.id, decision: .unsupported, reasonCodes: [.explicitlyUnsupported], mandatoryCaseIDs: [source.id],
      divergenceIDs: [divergence.id])
    let downgradedReport = try admission(runID: UUID(), entries: [downgraded])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.invalidField(record: support.id, field: "requested entry downgraded")) {
      try downgradedReport.validate(supportSurface: surface, cases: cases, ledger: ledger)
    }
  }

  @Test("P3 support entries link divergences to their own kind and required provenance case")
  func divergenceLinksCannotPointOutsideMandatoryCases() throws {
    let source = try temporalCase(id: "source")
    let regression = try temporalCase(id: "regression", expectedOutcome: .difference)
    let unrelated = try temporalCase(id: "unrelated")
    let cases = try TemporalSymmetryCasesV1(cases: [source, regression, unrelated])
    let divergence = try divergenceRecord(provenanceCaseID: source.id, regressionCaseID: regression.id)
    let ledger = try TemporalSymmetryDivergenceLedgerV1(records: [divergence])
    let entry = try TemporalSymmetrySupportSurfaceEntryV1(
      id: "scope", behavior: "bounded temporal", kind: .temporal, finiteBounds: try bounds(),
      configuration: try temporalConfiguration(), mandatoryCaseIDs: [unrelated.id], requestedStatus: .requested,
      linkedDivergenceIDs: [divergence.id])
    #expect(throws: TemporalSymmetryGovernanceErrorV1.inconsistentReference(
      record: entry.id, field: "linked divergence difference")) {
      try TemporalSymmetrySupportSurfaceV1(entries: [entry]).validate(cases: cases, ledger: ledger)
    }
  }

  private var digest: String { String(repeating: "a", count: 64) }

  private func bounds() throws -> CoreFiniteBoundsV1 {
    try CoreFiniteBoundsV1(summary: "three states", limits: ["states": 3])
  }

  private func evidence(_ path: String) throws -> CoreEvidenceReferenceV1 {
    try CoreEvidenceReferenceV1(path: "Verification/TemporalSymmetryConformance/\(path)", sha256: digest)
  }

  private func temporalConfiguration() throws -> TemporalSymmetryConfigurationV1 {
    try TemporalSymmetryConfigurationV1(property: "[] P", fairness: TemporalFairnessModeV1.none)
  }

  private func symmetryConfiguration() throws -> TemporalSymmetryConfigurationV1 {
    try TemporalSymmetryConfigurationV1(symmetryCollection: "members", symmetryScope: 2, symmetryEnabled: true)
  }

  private func correlation(_ caseID: String, _ gateRunID: UUID) throws -> TemporalSymmetryCaseRunCorrelationV1 {
    try TemporalSymmetryCaseRunCorrelationV1(
      caseID: caseID, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
  }

  private func temporalCase(id: String = "temporal", expectedOutcome: TemporalSymmetryExpectedOutcomeV1 = .exact) throws -> TemporalSymmetryCaseV1 {
    try TemporalSymmetryCaseV1(
      id: id, kind: .temporal, swiftSpec: "TemporalFixture",
      provenance: try CoreDivergenceProvenanceV1(
        caseID: id, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge", bridgeSourceSHA256: digest,
        bridgeBinarySHA256: digest),
      finiteBounds: try bounds(), semanticCitations: ["TLA+ temporal logic"], sourceInput: try evidence("\(id).tla"),
      configuration: try temporalConfiguration(), expectedOutcome: expectedOutcome)
  }

  private func divergenceRecord(
    provenanceCaseID: String, regressionCaseID: String, kind: TemporalSymmetryCaseKindV1 = .temporal,
    disposition: TemporalSymmetryDivergenceDispositionV1 = .open
  ) throws -> TemporalSymmetryDivergenceRecordV1 {
    try TemporalSymmetryDivergenceRecordV1(
      id: "difference", kind: kind,
      provenance: try CoreDivergenceProvenanceV1(
        caseID: provenanceCaseID, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge", bridgeSourceSHA256: digest,
        bridgeBinarySHA256: digest),
      semanticCitations: ["TLA+ temporal logic"], reproducer: try bounds(), originalEvidence: try evidence("original.json"),
      permanentRegressionCaseID: regressionCaseID, classification: .swiftTLADefect, disposition: disposition,
      normalizedDifferenceFingerprint: "difference", latestComparison: try TemporalSymmetryDivergenceComparisonV1(
        evidence: try evidence("latest.json"), outcome: .difference, normalizedDifferenceFingerprint: "difference"))
  }

  private func exploration(_ engine: SymmetryExplorationEngineV1, _ reduced: Bool, _ runID: UUID) throws -> SymmetryExplorationV1 {
    let states = reduced ? ["a"] : ["a", "b"]
    let transition = reduced
      ? try witness(engine, source: "a", target: "a")
      : try witness(engine, source: "a", target: "b")
    return try SymmetryExplorationV1(
      engine: engine, reduced: reduced, runID: runID, graphID: "\(engine.rawValue)-\(reduced)", initialStateIDs: ["a"],
      stateIDs: states, transitions: [transition],
      declaredConfigurationSHA256: digest, graphEvidence: try evidence("\(engine.rawValue)-\(reduced).json"),
      invariantOutcome: .satisfied, deadlockOutcome: .notApplicable)
  }

  private func witness(
    _ engine: SymmetryExplorationEngineV1, source: String = "a", target: String = "b"
  ) throws -> SymmetryRawTransitionWitnessV1 {
    try SymmetryRawTransitionWitnessV1(engine: engine, sourceStateID: source, action: "step", targetStateID: target)
  }

  private func admission(
    runID: UUID, entries: [TemporalSymmetryAdmissionEntryV1], admittedBounds: [String: CoreFiniteBoundsV1] = [:]
  ) throws -> TemporalSymmetryAdmissionV1 {
    try TemporalSymmetryAdmissionV1(
      reportID: UUID(), gateRunID: runID,
      coreAdmission: try TemporalSymmetryCoreAdmissionReferenceV1(
        reportID: UUID(), gateRunID: UUID(), report: try evidence("core-admission.json")),
      manifestSHA256: digest, toolchainSHA256: digest, entries: entries, admittedBounds: admittedBounds,
      unexplainedDivergenceCount: 0,
      finalExitClass: entries.contains { $0.reasonCodes.contains(where: \.makesEvaluationUnavailable) }
        ? .unavailable
        : (entries.contains { $0.decision == .blocked } ? .blocked : .success))
  }
}
