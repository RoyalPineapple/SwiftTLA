import Foundation
import Testing
import UpstreamParity

private struct EvidenceFailure {
  let evidence: TemporalSymmetryCaseEvidence?
  let gateRunID: UUID
  let manifest: String
  let toolchain: String
  let reason: TemporalSymmetryReasonCode
}

struct TemporalSymmetrySupportGateTests {
  @Test("complete current exact temporal evidence admits only declared bounds")
  func admitsCurrentExactTemporalEvidence() throws {
    let fixture = try Fixture()
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input())

    #expect(report.finalExitClass == .success)
    #expect(report.entries.map(\.decision) == [.admitted])
    #expect(report.admittedBounds == ["temporal-scope-0": fixture.bounds])
    #expect(report.entries[0].evidence == [try fixture.reference("temporal-comparison.json")])
    try report.validate(supportSurface: fixture.surface, cases: fixture.cases, ledger: fixture.ledger)
  }

  @Test("missing, partial, foreign, and stale evidence produce unavailable reports")
  func evidenceFailuresAreUnavailable() throws {
    let fixture = try Fixture()
    let failures: [EvidenceFailure] = [
      .init(evidence: nil, gateRunID: fixture.gateRunID, manifest: fixture.digest,
            toolchain: fixture.digest, reason: .missingEvidence),
      .init(evidence: try fixture.evidence(status: .partial), gateRunID: fixture.gateRunID,
            manifest: fixture.digest, toolchain: fixture.digest, reason: .partialEvidence),
      .init(evidence: try fixture.evidence(correlation: try fixture.correlation(gateRunID: UUID())),
            gateRunID: fixture.gateRunID, manifest: fixture.digest, toolchain: fixture.digest,
            reason: .foreignRun),
      .init(evidence: try fixture.evidence(), gateRunID: fixture.gateRunID,
            manifest: String(repeating: "b", count: 64), toolchain: fixture.digest,
            reason: .manifestDigestMismatch)
    ]
    for failure in failures {
      let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(
        gateRunID: failure.gateRunID,
        evidence: failure.evidence.map { [$0] } ?? [],
        manifestSHA256: failure.manifest,
        toolchainSHA256: failure.toolchain))
      #expect(report.finalExitClass == .unavailable)
      #expect(report.entries[0].reasonCodes.contains(failure.reason))
    }
  }

  @Test("a violated property without attributable lassos is unavailable")
  func missingTemporalWitnessIsUnavailable() throws {
    let fixture = try Fixture()
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(
      evidence: [try fixture.evidence(comparison: try fixture.comparison(violatedWithoutLasso: true))]))

    #expect(report.finalExitClass == .unavailable)
    #expect(report.entries[0].reasonCodes.contains(.missingTemporalWitness))
  }

  @Test("a current difference without a matching permanent fingerprint is unexplained")
  func unledgeredDifferenceBlocksTheClaim() throws {
    let fixture = try Fixture(expectedOutcome: .difference)
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(
      evidence: [try fixture.evidence(comparison: try fixture.comparison(difference: true), fingerprint: "new-difference")]))

    #expect(report.finalExitClass == .blocked)
    #expect(report.unexplainedDivergenceCount == 1)
    #expect(report.entries[0].reasonCodes.contains(.unexplainedDivergence))
    #expect(report.entries[0].reasonCodes.contains(.nonExactComparison))
  }

  @Test("linked divergences must be resolved with exact current evidence")
  func unresolvedLinkedDivergenceBlocksTheClaim() throws {
    let fixture = try Fixture(includeOpenDivergence: true)
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input())

    #expect(report.finalExitClass == .blocked)
    #expect(report.entries[0].reasonCodes.contains(.unresolvedDivergence))
  }

  @Test("one unexplained case in a two-case entry is counted once and blocks admission")
  func twoCasesOneEntryCountsUnexplainedDifferenceOnce() throws {
    let fixture = try Fixture(caseIDs: ["first", "second"], supportCases: [["first", "second"]])
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(evidence: [
      try fixture.evidence(caseID: "first"),
      try fixture.evidence(caseID: "second", comparison: try fixture.comparison(caseID: "second", difference: true), fingerprint: "new-difference")
    ]))

    #expect(report.unexplainedDivergenceCount == 1)
    #expect(report.unexplainedDivergenceCaseIDs == ["second"])
    #expect(report.entries.count == 1)
    #expect(report.entries[0].decision == .blocked)
    #expect(report.entries[0].reasonCodes.contains(.unexplainedDivergence))
  }

  @Test("one unexplained mandatory case is counted once even when entries share it")
  func sharedUnexplainedCaseIsCountedOnce() throws {
    let fixture = try Fixture(caseIDs: ["shared"], supportCases: [["shared"], ["shared"]])
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(evidence: [
      try fixture.evidence(caseID: "shared", comparison: try fixture.comparison(caseID: "shared", difference: true), fingerprint: "new-difference")
    ]))

    #expect(report.unexplainedDivergenceCount == 1)
    #expect(report.unexplainedDivergenceCaseIDs == ["shared"])
    #expect(report.entries.count == 2)
  }

  @Test("an unledgered difference outside a requested entry blocks the whole requested surface")
  func unrelatedUnexplainedCaseBlocksAdmission() throws {
    let fixture = try Fixture(caseIDs: ["requested", "outside"], supportCases: [["requested"]])
    let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(evidence: [
      try fixture.evidence(caseID: "requested"),
      try fixture.evidence(caseID: "outside", comparison: try fixture.comparison(caseID: "outside", difference: true), fingerprint: "new-difference")
    ]))

    #expect(report.entries[0].decision == .blocked)
    #expect(report.entries[0].reasonCodes.contains(.unexplainedDivergence))
    #expect(report.unexplainedDivergenceCaseIDs == ["outside"])
  }

  @Test("core admission must be current, correlated, and digest-bound")
  func invalidCoreAdmissionBlocksAsUnavailable() throws {
    let fixture = try Fixture()
    let core = try TemporalSymmetryCoreAdmissionReference(
      reportID: UUID(), gateRunID: UUID(), report: try fixture.reference("core-admission.json"))
    let stale = try TemporalSymmetryCoreAdmissionContext(
      temporalSymmetryGateRunID: fixture.gateRunID, reportID: UUID(), coreGateRunID: core.gateRunID,
      reportPath: core.report.path, reportSHA256: core.report.sha256)
    let foreign = try TemporalSymmetryCoreAdmissionContext(
      temporalSymmetryGateRunID: UUID(), reportID: core.reportID, coreGateRunID: core.gateRunID,
      reportPath: core.report.path, reportSHA256: core.report.sha256)
    let digestMismatch = try TemporalSymmetryCoreAdmissionContext(
      temporalSymmetryGateRunID: fixture.gateRunID, reportID: core.reportID, coreGateRunID: core.gateRunID,
      reportPath: core.report.path, reportSHA256: String(repeating: "b", count: 64))
    for (context, reason) in [
      (stale, TemporalSymmetryReasonCode.missingPrerequisite),
      (foreign, .foreignRun),
      (digestMismatch, .manifestDigestMismatch)
    ] {
      let report = TemporalSymmetrySupportGate().evaluate(try fixture.input(
        coreAdmission: core, coreAdmissionContext: context))
      #expect(report.finalExitClass == .unavailable)
      #expect(report.entries[0].reasonCodes.contains(reason))
    }
  }

  private struct Fixture {
    let digest = String(repeating: "a", count: 64)
    let gateRunID = UUID()
    let bounds: CoreFiniteBounds
    let cases: TemporalSymmetryCases
    let ledger: TemporalSymmetryDivergenceLedger
    let surface: TemporalSymmetrySupportSurface

    init(
      expectedOutcome: TemporalSymmetryExpectedOutcome = .exact,
      includeOpenDivergence: Bool = false,
      caseIDs: [String] = ["temporal"],
      supportCases: [[String]]? = nil
    ) throws {
      let digest = String(repeating: "a", count: 64)
      let bounds = try CoreFiniteBounds(summary: "three states", limits: ["states": 3])
      let source = try Self.makeCase(id: caseIDs[0], expectedOutcome: expectedOutcome, bounds: bounds, digest: digest)
      let regression = try Self.makeCase(id: "temporal-regression", expectedOutcome: .difference, bounds: bounds, digest: digest)
      self.bounds = bounds
      let declaredCases = try caseIDs.map {
        try Self.makeCase(
          id: $0,
          expectedOutcome: $0 == caseIDs[0] ? expectedOutcome : .exact,
          bounds: bounds,
          digest: digest
        )
      }
      cases = try TemporalSymmetryCases(cases: includeOpenDivergence ? declaredCases + [regression] : declaredCases)
      let supportCases = supportCases ?? [[source.id]]
      if includeOpenDivergence {
        let record = try Self.makeDivergence(source: source, regression: regression, bounds: bounds, digest: digest)
        ledger = try TemporalSymmetryDivergenceLedger(records: [record])
        surface = try TemporalSymmetrySupportSurface(entries: try supportCases.enumerated().map {
          try Self.makeSurface(id: "temporal-scope-\($0.offset)", bounds: bounds, caseIDs: $0.element, linkedDivergences: [record.id])
        })
      } else {
        ledger = try TemporalSymmetryDivergenceLedger(records: [])
        surface = try TemporalSymmetrySupportSurface(entries: try supportCases.enumerated().map {
          try Self.makeSurface(id: "temporal-scope-\($0.offset)", bounds: bounds, caseIDs: $0.element)
        })
      }
    }

    func input(
      gateRunID: UUID? = nil,
      evidence: [TemporalSymmetryCaseEvidence]? = nil,
      manifestSHA256: String? = nil,
      toolchainSHA256: String? = nil,
      coreAdmission suppliedCoreAdmission: TemporalSymmetryCoreAdmissionReference? = nil,
      coreAdmissionContext suppliedCoreAdmissionContext: TemporalSymmetryCoreAdmissionContext? = nil
    ) throws -> TemporalSymmetryGateInput {
      let currentGateRunID = gateRunID ?? self.gateRunID
      let coreAdmission = try suppliedCoreAdmission ?? TemporalSymmetryCoreAdmissionReference(
        reportID: UUID(), gateRunID: UUID(), report: try reference("core-admission.json"))
      let coreAdmissionContext = try suppliedCoreAdmissionContext ?? TemporalSymmetryCoreAdmissionContext(
        temporalSymmetryGateRunID: currentGateRunID,
        reportID: coreAdmission.reportID,
        coreGateRunID: coreAdmission.gateRunID,
        reportPath: coreAdmission.report.path,
        reportSHA256: coreAdmission.report.sha256)
      return try TemporalSymmetryGateInput(
        gateRunID: currentGateRunID,
        coreAdmission: coreAdmission,
        coreAdmissionContext: coreAdmissionContext,
        cases: cases, ledger: ledger, surface: surface, evidence: evidence ?? [try self.evidence()],
        manifestSHA256: manifestSHA256 ?? digest, toolchainSHA256: toolchainSHA256 ?? digest)
    }

    func evidence(
      caseID: String = "temporal",
      status: TemporalSymmetryEvidenceStatus = .complete,
      correlation: TemporalSymmetryCaseRunCorrelation? = nil,
      comparison: TemporalComparison? = nil,
      fingerprint: String? = nil
    ) throws -> TemporalSymmetryCaseEvidence {
      let comparison = try comparison ?? self.comparison(caseID: caseID, correlation: correlation)
      return try TemporalSymmetryCaseEvidence(
        comparison: .temporal(comparison), comparisonEvidence: try reference("temporal-comparison.json"),
        manifestSHA256: digest, toolchainSHA256: digest, status: status, normalizedDifferenceFingerprint: fingerprint)
    }

    func correlation(caseID: String = "temporal", gateRunID: UUID) throws -> TemporalSymmetryCaseRunCorrelation {
      try TemporalSymmetryCaseRunCorrelation(
        caseID: caseID, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    }

    func comparison(
      caseID: String = "temporal",
      correlation: TemporalSymmetryCaseRunCorrelation? = nil,
      difference: Bool = false,
      violatedWithoutLasso: Bool = false
    ) throws -> TemporalComparison {
      let correlation = try correlation ?? self.correlation(caseID: caseID, gateRunID: gateRunID)
      let swift: TemporalPropertyResult
      let tlc: TemporalPropertyResult
      if violatedWithoutLasso {
        swift = try TemporalPropertyResult(
          availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"],
          traceAvailability: .unavailable)
        tlc = swift
      } else {
        swift = try TemporalPropertyResult(
          availability: .evaluated, outcome: .satisfied, graphID: "graph", initialStateIDs: ["i"],
          traceAvailability: .notApplicable)
        tlc = difference
          ? try TemporalPropertyResult(
            availability: .evaluated, outcome: .violated, graphID: "graph", initialStateIDs: ["i"],
            traceAvailability: .available, traceEvidence: try reference("tlc-lasso.json"),
            lasso: try TemporalLassoWitness(prefixStateIDs: ["i"], cycleStateIDs: ["i", "i"]))
          : swift
      }
      return try TemporalComparison(
        caseID: caseID, configuration: try Self.configuration(), correlation: correlation,
        outcome: difference ? .difference : .exact, swiftResult: swift, tlcResult: tlc,
        swiftEvidence: try reference("swift.json"), tlcEvidence: try reference("tlc.json"),
        enablednessEvidence: try reference("enabledness.json"), fairComponents: [], rejectedComponents: [],
        diagnosticCode: difference ? .propertyOutcomeDifference : .exactAgreement)
    }

    private static func makeCase(
      id: String, expectedOutcome: TemporalSymmetryExpectedOutcome, bounds: CoreFiniteBounds, digest: String
    ) throws -> TemporalSymmetryCase {
      try TemporalSymmetryCase(
        id: id, kind: .temporal, swiftSpec: "TemporalFixture", provenance: try provenance(caseID: id, digest: digest),
        finiteBounds: bounds, semanticCitations: ["TLA+ temporal logic"], sourceInput: try reference("\(id).tla", digest: digest),
        configuration: try configuration(), expectedOutcome: expectedOutcome)
    }

    private static func makeSurface(
      id: String, bounds: CoreFiniteBounds, caseIDs: [String], linkedDivergences: [String] = []
    ) throws -> TemporalSymmetrySupportSurfaceEntry {
      try TemporalSymmetrySupportSurfaceEntry(
        id: id, behavior: "bounded temporal", kind: .temporal, finiteBounds: bounds,
        configuration: try configuration(), mandatoryCaseIDs: caseIDs, requestedStatus: .requested,
        linkedDivergenceIDs: linkedDivergences)
    }

    private static func makeDivergence(
      source: TemporalSymmetryCase, regression: TemporalSymmetryCase, bounds: CoreFiniteBounds, digest: String
    ) throws -> TemporalSymmetryDivergenceRecord {
      try TemporalSymmetryDivergenceRecord(
        id: "known-difference", kind: .temporal, provenance: try provenance(caseID: source.id, digest: digest),
        semanticCitations: ["TLA+ temporal logic"], reproducer: bounds, originalEvidence: try reference("original.json", digest: digest),
        permanentRegressionCaseID: regression.id, classification: .swiftTLADefect, disposition: .open,
        normalizedDifferenceFingerprint: "known-difference",
        latestComparison: try TemporalSymmetryDivergenceComparison(
          evidence: try reference("latest.json", digest: digest), outcome: .difference, normalizedDifferenceFingerprint: "known-difference"))
    }

    private static func provenance(caseID: String, digest: String) throws -> CoreDivergenceProvenance {
      try CoreDivergenceProvenance(
        caseID: caseID, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge", bridgeSourceSHA256: digest,
        bridgeBinarySHA256: digest)
    }

    private static func configuration() throws -> TemporalSymmetryConfiguration {
      try TemporalSymmetryConfiguration(property: "[] P", fairness: TemporalFairnessMode.none)
    }

    private static func reference(_ path: String, digest: String) throws -> CoreEvidenceReference {
      try CoreEvidenceReference(path: "Verification/TemporalSymmetryConformance/\(path)", sha256: digest)
    }

    func reference(_ path: String) throws -> CoreEvidenceReference {
      try Self.reference(path, digest: digest)
    }
  }
}
