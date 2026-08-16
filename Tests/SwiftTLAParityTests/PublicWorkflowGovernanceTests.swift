import Foundation
import Testing
@testable import UpstreamParity

@Suite("P4 public workflow governance")
struct PublicWorkflowGovernanceTests {
  @Test("admission needs complete hosted workflow evidence and a successful named platform")
  func admissionIsEvidenceBound() throws {
    let fixture = Fixture()
    let caseRecord = try fixture.caseRecord()
    let support = try fixture.support(caseID: caseRecord.id)
    let platform = try fixture.platform()
    let evidence = try fixture.evidence(caseID: caseRecord.id, gateRunID: fixture.gateRunID)
    let entry = try PublicWorkflowAdmissionEntryV1(
      supportID: support.id, decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [caseRecord.id],
      divergenceIDs: [], evidence: [evidence], platformEvidence: [platform])
    let report = try PublicWorkflowAdmissionV1(
      gateRunID: fixture.gateRunID, entries: [entry], admittedBounds: [support.id: support.finiteBounds])

    try report.validate(
      supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [support]),
      cases: try PublicWorkflowCasesV1(cases: [caseRecord]),
      ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    #expect(report.finalExitClass == .success)
  }

  @Test("partial and foreign evidence is unavailable, never admitted")
  func unsafeEvidenceFailsClosed() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try PublicWorkflowAdmissionEntryV1(
        supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
        divergenceIDs: [], evidence: [try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID, status: .partial)],
        platformEvidence: [try fixture.platform()])
    }
    let foreignEntry = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
      divergenceIDs: [], evidence: [try fixture.evidence(caseID: record.id, gateRunID: UUID())],
      platformEvidence: [try fixture.platform()])
    let foreignReport = try PublicWorkflowAdmissionV1(
      gateRunID: fixture.gateRunID, entries: [foreignEntry], admittedBounds: ["annotation": record.finiteBounds])
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try foreignReport.validate(
        supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [try fixture.support(caseID: record.id)]),
        cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    let blocked = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .unavailable, reasonCodes: [.partialEvidence],
      mandatoryCaseIDs: [record.id], divergenceIDs: [])
    let report = try PublicWorkflowAdmissionV1(gateRunID: fixture.gateRunID, entries: [blocked])
    #expect(report.finalExitClass == .unavailable)
  }

  @Test("decoders reject unknown fields and claims cannot admit an unsupported platform")
  func schemaAndPlatformBoundaryAreStrict() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    object["invented"] = true
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try JSONDecoder().decode(PublicWorkflowConformanceCaseV1.self, from: JSONSerialization.data(withJSONObject: object))
    }
    let unavailable = try PublicWorkflowPlatformEvidenceV1(
        platform: "iOS", command: "xcodebuild test", sdk: "iphoneos", destination: "generic/platform=iOS",
        xcodeVersion: "27", fixture: try fixture.reference("platform-fixture"), status: .unavailable,
        exitCode: nil, stdout: try fixture.reference("stdout"), stderr: try fixture.reference("stderr"),
        correlation: try fixture.platformCorrelation(caseID: record.id, platformRunID: fixture.platformRunID),
        fixtureBinding: try fixture.binding(caseID: record.id, evidence: fixture.reference("platform-fixture"), runID: fixture.platformRunID),
        stdoutBinding: try fixture.binding(caseID: record.id, evidence: fixture.reference("stdout"), runID: fixture.platformRunID),
        stderrBinding: try fixture.binding(caseID: record.id, evidence: fixture.reference("stderr"), runID: fixture.platformRunID),
        execution: try fixture.candidateExecution())
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try PublicWorkflowAdmissionEntryV1(
        supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
        divergenceIDs: [], evidence: [try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID)],
        platformEvidence: [unavailable])
    }
  }

  @Test("declared support state, bounds, categories, and reasons cannot bypass admission")
  func declarationStateAndReasonsAreEnforced() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    let evidence = try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID)
    let platform = try fixture.platform(caseID: record.id)
    let admitted = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
      divergenceIDs: [], evidence: [evidence], platformEvidence: [platform])
    let unsupported = try fixture.support(caseID: record.id, requestedStatus: .unsupported, reason: "not evaluated")
    let report = try PublicWorkflowAdmissionV1(
      gateRunID: fixture.gateRunID, entries: [admitted], admittedBounds: ["annotation": record.finiteBounds])
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try report.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [unsupported]),
                          cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    let wrongCategory = try fixture.support(caseID: record.id, category: .parserBuilder)
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try PublicWorkflowSupportSurfaceV1(entries: [wrongCategory]).validate(
        cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    let wrongBounds = try fixture.support(caseID: record.id, bounds: try CoreFiniteBoundsV1(summary: "two", limits: ["states": 2]))
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try PublicWorkflowSupportSurfaceV1(entries: [wrongBounds]).validate(
        cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    let unavailable = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .unavailable, reasonCodes: [.foreignRun], mandatoryCaseIDs: [record.id], divergenceIDs: [])
    let unavailableReport = try PublicWorkflowAdmissionV1(gateRunID: fixture.gateRunID, entries: [unavailable])
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try unavailableReport.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [try fixture.support(caseID: record.id)]),
                                    cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
  }

  @Test("foreign artifact identities and current ledger divergences block admission")
  func identitiesAndLedgerAreAdmissionPrerequisites() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    let malformedEvidence = try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID, fixtureSource: fixture.reference("foreign-fixture"))
    let entry = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
      divergenceIDs: [], evidence: [malformedEvidence], platformEvidence: [try fixture.platform(caseID: record.id)])
    let report = try PublicWorkflowAdmissionV1(gateRunID: fixture.gateRunID, entries: [entry], admittedBounds: ["annotation": record.finiteBounds])
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try report.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [try fixture.support(caseID: record.id)]),
                          cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    let validEntry = try PublicWorkflowAdmissionEntryV1(
      supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
      divergenceIDs: [], evidence: [try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID)],
      platformEvidence: [try fixture.platform(caseID: record.id)])
    let ledgerReport = try PublicWorkflowAdmissionV1(
      gateRunID: fixture.gateRunID, entries: [validEntry], admittedBounds: ["annotation": record.finiteBounds],
      unexplainedDivergenceCount: 0)
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try ledgerReport.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [try fixture.support(caseID: record.id, requestedStatus: .requested)]),
                                cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try fixture.openLedger(caseID: record.id))
    }
  }

  @Test("platform case, run, and retained logs cannot be substituted")
  func platformArtifactsAreIndependentlyBound() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    let other = try fixture.caseRecord(id: "annotation-other")
    let support = try fixture.support(caseID: record.id)
    let evidence = try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID)
    let nonmandatory = try fixture.platform(caseID: other.id, record: other)
    let nonmandatoryReport = try fixture.admittedReport(record: record, evidence: evidence, platform: nonmandatory)
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try nonmandatoryReport.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [support]),
                                     cases: try PublicWorkflowCasesV1(cases: [record, other]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try fixture.platform(caseID: record.id, bindingRunID: UUID())
    }
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try fixture.platform(caseID: record.id, stdoutBindingEvidence: fixture.reference("stderr"))
    }
    let localDiagnostic = try fixture.platform(caseID: record.id, ci: false)
    #expect(localDiagnostic.execution.authority == .diagnostic)
  }

  @Test("diagnostic evidence cannot impersonate hosted workflow evidence")
  func candidateAndDiagnosticEvidenceAreDistinct() throws {
    let fixture = Fixture()
    let record = try fixture.caseRecord()
    let localEvidence = try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID, ci: false)
    #expect(localEvidence.execution.authority == .diagnostic)
    let candidateEvidence = try fixture.evidence(caseID: record.id, gateRunID: fixture.gateRunID)
    #expect(candidateEvidence.execution.authority == .candidate)
    let support = try fixture.support(caseID: record.id)
    let candidateReport = try fixture.admittedReport(record: record, evidence: candidateEvidence, platform: try fixture.platform(caseID: record.id))
    try candidateReport.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [support]),
                                 cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    let diagnosticReport = try fixture.admittedReport(record: record, evidence: localEvidence, platform: try fixture.platform(caseID: record.id, ci: false))
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try diagnosticReport.validate(supportSurface: try PublicWorkflowSupportSurfaceV1(entries: [support]),
                                    cases: try PublicWorkflowCasesV1(cases: [record]), ledger: try PublicWorkflowDivergenceLedgerV1(records: []))
    }
  }

  private struct Fixture {
    let digest = String(repeating: "a", count: 64)
    let gateRunID = UUID()
    let platformRunID = UUID()

    func reference(_ name: String) throws -> CoreEvidenceReferenceV1 {
      try CoreEvidenceReferenceV1(path: "Verification/PublicWorkflowConformance/\(name)", sha256: digest)
    }

    func caseRecord(id: String = "annotation-valid") throws -> PublicWorkflowConformanceCaseV1 {
      try PublicWorkflowConformanceCaseV1(
        id: id, category: .annotation, publicName: "@TLAValidated",
        finiteBounds: try CoreFiniteBoundsV1(summary: "one state", limits: ["states": 1]),
        semanticCitations: ["TLA+ Specifying Systems"], provenance: CoreDivergenceProvenanceV1(
          caseID: id, moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
          tlcTag: "v1.8.0", tlcCommit: "30cc3601321c3fc02e044d0ecb5c58d8921e18df", tlcJarSHA256: digest,
          javaDistribution: "Eclipse Temurin", javaVersion: "17.0.19+10", javaArchiveSHA256: digest,
          bridgeClass: "org.swifttla.conformance.LosslessStateWriter", bridgeSourceSHA256: digest, bridgeBinarySHA256: digest),
        sourceInput: try reference("fixture.swift"), configuration: try reference("fixture.json"),
        expectedOutcome: .exact, authorityBoundary: .publishedSemantics)
    }

    func support(caseID: String, category: PublicWorkflowCaseCategoryV1 = .annotation,
                 bounds: CoreFiniteBoundsV1? = nil, requestedStatus: PublicWorkflowSupportRequestV1 = .requested,
                 reason: String? = nil) throws -> PublicWorkflowSupportSurfaceEntryV1 {
      try PublicWorkflowSupportSurfaceEntryV1(
        id: "annotation", behavior: "bounded annotation fixture", category: category,
        finiteBounds: try bounds ?? CoreFiniteBoundsV1(summary: "one state", limits: ["states": 1]),
        mandatoryCaseIDs: [caseID], requestedStatus: requestedStatus, releaseClaim: "One bounded fixture",
        requiredPlatforms: ["macOS"], reason: reason)
    }

    func binding(caseID: String, evidence: CoreEvidenceReferenceV1, runID: UUID = UUID(), source: CoreEvidenceReferenceV1? = nil, record: PublicWorkflowConformanceCaseV1? = nil) throws -> PublicWorkflowEvidenceBindingV1 {
      let record = try record ?? caseRecord(id: caseID)
      return try PublicWorkflowEvidenceBindingV1(
        caseID: caseID, gateRunID: gateRunID, evidenceRunID: runID,
        sourceInput: source ?? record.sourceInput, configuration: record.configuration,
        provenance: record.provenance, evidence: evidence)
    }

    func evidence(
      caseID: String, gateRunID: UUID, status: PublicWorkflowEvidenceStatusV1 = .complete,
      fixtureSource: CoreEvidenceReferenceV1? = nil, ci: Bool = true
    ) throws -> PublicWorkflowCaseEvidenceV1 {
      let fixtureRunID = UUID()
      let comparisonRunID = UUID()
      let fixtureReference = try reference("fixture-result.json")
      let comparisonReference = try reference("comparison.json")
      let provenanceReference = try reference("provenance.json")
      let record = try caseRecord()
      return try PublicWorkflowCaseEvidenceV1(
        caseID: caseID, correlation: try PublicWorkflowCaseRunCorrelationV1(
          caseID: caseID, gateRunID: gateRunID, fixtureRunID: fixtureRunID, comparisonRunID: comparisonRunID),
        status: status, fixture: fixtureReference, comparison: comparisonReference, provenance: provenanceReference,
        fixtureBinding: try PublicWorkflowEvidenceBindingV1(caseID: caseID, gateRunID: gateRunID, evidenceRunID: fixtureRunID, sourceInput: fixtureSource ?? record.sourceInput, configuration: record.configuration, provenance: record.provenance, evidence: fixtureReference),
        comparisonBinding: try PublicWorkflowEvidenceBindingV1(caseID: caseID, gateRunID: gateRunID, evidenceRunID: comparisonRunID, sourceInput: record.sourceInput, configuration: record.configuration, provenance: record.provenance, evidence: comparisonReference),
        provenanceBinding: try PublicWorkflowEvidenceBindingV1(caseID: caseID, gateRunID: gateRunID, evidenceRunID: comparisonRunID, sourceInput: record.sourceInput, configuration: record.configuration, provenance: record.provenance, evidence: provenanceReference),
        outcome: status == .complete ? .exact : .unavailable, diagnosticCode: status == .complete ? .exactAgreement : .evidenceUnavailable,
        execution: try (ci ? candidateExecution() : diagnosticExecution()))
    }

    func platformCorrelation(caseID: String, platformRunID: UUID = UUID()) throws -> PublicWorkflowPlatformRunCorrelationV1 {
      try PublicWorkflowPlatformRunCorrelationV1(caseID: caseID, gateRunID: gateRunID, platformRunID: platformRunID)
    }

    func platform(caseID: String = "annotation-valid", record: PublicWorkflowConformanceCaseV1? = nil,
                  platformRunID: UUID? = nil, bindingRunID: UUID? = nil,
                  stdoutBindingEvidence: CoreEvidenceReferenceV1? = nil, ci: Bool = true) throws -> PublicWorkflowPlatformEvidenceV1 {
      let platformFixture = try reference("platform-fixture")
      let stdout = try reference("stdout")
      let stderr = try reference("stderr")
      let correlation = try platformCorrelation(caseID: caseID, platformRunID: platformRunID ?? UUID())
      let bindingRunID = bindingRunID ?? correlation.platformRunID
      let record = try record ?? caseRecord(id: caseID)
      return try PublicWorkflowPlatformEvidenceV1(
        platform: "macOS", command: "xcodebuild test", sdk: "macosx", destination: "platform=macOS",
        xcodeVersion: "27", fixture: platformFixture, status: .succeeded,
        exitCode: 0, stdout: stdout, stderr: stderr, correlation: correlation,
        fixtureBinding: try binding(caseID: caseID, evidence: platformFixture, runID: bindingRunID, record: record),
        stdoutBinding: try binding(caseID: caseID, evidence: stdoutBindingEvidence ?? stdout, runID: bindingRunID, record: record),
        stderrBinding: try binding(caseID: caseID, evidence: stderr, runID: bindingRunID, record: record),
        execution: try (ci ? candidateExecution() : diagnosticExecution()))
    }

    func diagnosticExecution() throws -> PublicWorkflowCIExecutionV1 {
      try PublicWorkflowCIExecutionV1(authority: .diagnostic, metadata: try reference("local-diagnostic.json"))
    }

    func candidateExecution() throws -> PublicWorkflowCIExecutionV1 {
      return try PublicWorkflowCIExecutionV1(
        authority: .candidate, gitSHA: String(repeating: "b", count: 40), repository: "RoyalPineapple/SwiftTLA",
        workflow: "Public Workflow Conformance", ref: "refs/heads/main", runID: "123", runAttempt: 1, job: "public-workflow",
        serverURL: "https://github.com", metadata: try reference("ci-candidate.json"))
    }

    func admittedReport(record: PublicWorkflowConformanceCaseV1, evidence: PublicWorkflowCaseEvidenceV1, platform: PublicWorkflowPlatformEvidenceV1) throws -> PublicWorkflowAdmissionV1 {
      let entry = try PublicWorkflowAdmissionEntryV1(
        supportID: "annotation", decision: .admitted, reasonCodes: [], mandatoryCaseIDs: [record.id],
        divergenceIDs: [], evidence: [evidence], platformEvidence: [platform])
      return try PublicWorkflowAdmissionV1(gateRunID: gateRunID, entries: [entry], admittedBounds: ["annotation": record.finiteBounds])
    }

    func openLedger(caseID: String) throws -> PublicWorkflowDivergenceLedgerV1 {
      try PublicWorkflowDivergenceLedgerV1(records: [
        try PublicWorkflowDivergenceRecordV1(
          id: "open", caseID: caseID, semanticCitations: ["TLA+ Specifying Systems"],
          reproducer: try CoreFiniteBoundsV1(summary: "one state", limits: ["states": 1]),
          originalEvidence: try reference("original"), permanentRegressionCaseID: caseID,
          classification: .swiftTLADefect, disposition: .open, normalizedDifferenceFingerprint: "difference",
          latestComparison: try PublicWorkflowDivergenceComparisonV1(evidence: try reference("latest"), outcome: .difference, normalizedDifferenceFingerprint: "difference"))
      ])
    }
  }
}
