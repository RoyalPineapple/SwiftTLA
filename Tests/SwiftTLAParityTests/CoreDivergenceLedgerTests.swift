import Testing
import UpstreamParity
import Foundation

struct CoreDivergenceLedgerTests {
  @Test("governance registers reject duplicate IDs and broken references")
  func rejectsDuplicateAndUnknownReferences() throws {
    let record = try divergenceRecord()
    #expect(throws: CoreGovernanceErrorV1.duplicateID(kind: "divergence", id: "edge-mismatch")) {
      _ = try CoreDivergenceLedgerV1(records: [record, record])
    }

    let ledger = try CoreDivergenceLedgerV1(records: [record])
    #expect(throws: CoreGovernanceErrorV1.unknownCaseID("edge-mismatch-regression")) {
      try ledger.validate(caseIDs: ["edge-mismatch"])
    }

    let entry = try supportEntry(linkedDivergences: ["missing-divergence"])
    let surface = try CoreSupportSurfaceV1(entries: [entry])
    #expect(throws: CoreGovernanceErrorV1.unknownDivergenceID("missing-divergence")) {
      try surface.validate(caseIDs: ["edge-mismatch", "edge-mismatch-regression"], ledger: ledger)
    }
  }

  @Test("governance rejects incomplete provenance, invalid dispositions, and excluded categories")
  func rejectsInvalidGovernanceDefinitions() throws {
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "edge-mismatch", field: "provenance")) {
      _ = try CoreDivergenceProvenanceV1(
        caseID: "edge-mismatch", moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
        tlcTag: "", tlcCommit: "commit", tlcJarSHA256: digest, javaDistribution: "Temurin",
        javaVersion: "17", javaArchiveSHA256: digest, bridgeClass: "bridge",
        bridgeSourceSHA256: digest, bridgeBinarySHA256: digest)
    }
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "edge-mismatch", field: "latestComparison")) {
      _ = try CoreDivergenceRecordV1(
        id: "edge-mismatch", provenance: try provenance(), semanticCitations: ["citation"],
        reproducer: try bounds(), originalEvidence: try evidence("original.json"),
        permanentRegressionCaseID: "edge-mismatch-regression", classification: .swiftTLADefect,
        disposition: .resolved, normalizedDifferenceFingerprint: "fingerprint",
        latestComparison: try CoreDivergenceComparisonV1(
          evidence: try evidence("latest.json"), outcome: .difference,
          normalizedDifferenceFingerprint: "changed"))
    }
    #expect(throws: CoreGovernanceErrorV1.unsupportedCategory("temporal")) {
      _ = try CoreSupportSurfaceEntryV1(
        id: "temporal", behavior: "eventually", category: .temporal, finiteBounds: try bounds(),
        mandatoryCaseIDs: ["edge-mismatch"], requestedStatus: .unsupported, reason: "outside V1")
    }
  }

  @Test("resolved divergences retain an exact latest comparison")
  func rejectsResolvedDifferenceEvenWhenFingerprintMatches() throws {
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "edge-mismatch", field: "latestComparison")) {
      _ = try CoreDivergenceRecordV1(
        id: "edge-mismatch", provenance: try provenance(), semanticCitations: ["citation"],
        reproducer: try bounds(), originalEvidence: try evidence("original.json"),
        permanentRegressionCaseID: "edge-mismatch-regression", classification: .swiftTLADefect,
        disposition: .resolved, normalizedDifferenceFingerprint: "fingerprint",
        latestComparison: try CoreDivergenceComparisonV1(
          evidence: try evidence("latest.json"), outcome: .difference,
          normalizedDifferenceFingerprint: "fingerprint"))
    }
  }

  @Test("governance JSON rejects unknown fields and invalid enum values")
  func rejectsMalformedGovernanceJSON() throws {
    let data = try JSONEncoder().encode(try CoreDivergenceLedgerV1(records: [try divergenceRecord()]))
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["misspelledRecords"] = []
    let unknownField = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "decode", field: "unknown field misspelledRecords")) {
      _ = try JSONDecoder().decode(CoreDivergenceLedgerV1.self, from: unknownField)
    }

    var invalidEnumObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var records = try #require(invalidEnumObject["records"] as? [[String: Any]])
    records[0]["classification"] = "not-a-classification"
    invalidEnumObject["records"] = records
    let invalidEnum = try JSONSerialization.data(withJSONObject: invalidEnumObject)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(CoreDivergenceLedgerV1.self, from: invalidEnum)
    }
  }

  @Test("admission contracts retain evidence correlations and complete aggregate counts")
  func validatesAdmissionCompleteness() throws {
    let runID = UUID()
    let correlation = try CoreSupportCaseRunCorrelationV1(
      caseID: "edge-mismatch", gateRunID: runID, swiftRunID: runID, tlcRunID: runID,
      comparisonRunID: runID)
    let admission = try CoreSupportAdmissionV1(gateRunID: runID, entries: [
      try CoreSupportAdmissionEntryV1(
        supportID: "clock-transitions", decision: .admitted, reasonCodes: [],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: [], evidence: [try evidence("comparison.json")],
        caseRunCorrelations: [correlation]),
      try CoreSupportAdmissionEntryV1(
        supportID: "missing", decision: .blocked, reasonCodes: [.missingEvidence],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: []),
      try CoreSupportAdmissionEntryV1(
        supportID: "stale", decision: .blocked, reasonCodes: [.foreignRun],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: []),
      try CoreSupportAdmissionEntryV1(
        supportID: "failing", decision: .blocked, reasonCodes: [.executionFailed],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: [])
    ])
    #expect(admission.counts.missing == 1)
    #expect(admission.counts.stale == 1)
    #expect(admission.counts.failing == 1)
    #expect(admission.finalExitClass == .blocked)
    #expect(admission.authority ==
      "Published TLA+ semantics are authoritative; TLC is a pinned executable reference; "
      + "TLC source and tests are diagnostic evidence; no hidden checker or oracle is claimed.")

    let encodedAdmission = try JSONEncoder().encode(admission)
    var admissionObject = try #require(JSONSerialization.jsonObject(with: encodedAdmission) as? [String: Any])
    #expect(admissionObject["finalExitClass"] as? String == "blocked")
    #expect(admissionObject["authority"] as? String == admission.authority)
    let decodedAdmission = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: encodedAdmission)
    #expect(decodedAdmission.finalExitClass == .blocked)
    #expect(decodedAdmission.authority == admission.authority)

    var invalidExitClassObject = admissionObject
    invalidExitClassObject["finalExitClass"] = "not-an-exit-class"
    let invalidExitClass = try JSONSerialization.data(withJSONObject: invalidExitClassObject)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: invalidExitClass)
    }

    var missingExitClassObject = admissionObject
    missingExitClassObject.removeValue(forKey: "finalExitClass")
    let missingExitClass = try JSONSerialization.data(withJSONObject: missingExitClassObject)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: missingExitClass)
    }

    var incompleteAuthorityObject = admissionObject
    incompleteAuthorityObject["authority"] =
      "Published TLA+ semantics are authoritative; TLC is a pinned executable reference."
    let incompleteAuthority = try JSONSerialization.data(withJSONObject: incompleteAuthorityObject)
    #expect(throws: CoreGovernanceErrorV1.invalidSchema(CoreSupportAdmissionV1.schema)) {
      _ = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: incompleteAuthority)
    }

    var admissionEntries = try #require(admissionObject["entries"] as? [[String: Any]])
    admissionEntries[0].removeValue(forKey: "evidence")
    admissionObject["entries"] = admissionEntries
    let incompleteAdmission = try JSONSerialization.data(withJSONObject: admissionObject)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: incompleteAdmission)
    }

    #expect(throws: CoreGovernanceErrorV1.invalidField(
      record: "clock-transitions", field: "evidence or caseRunCorrelations")) {
      _ = try CoreSupportAdmissionEntryV1(
        supportID: "clock-transitions", decision: .admitted, reasonCodes: [],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: [])
    }
  }

  @Test("admission succeeds when only unrelated support is explicitly unsupported")
  func allowsExplicitlyUnsupportedEntriesAlongsideAdmittedSupport() throws {
    let runID = UUID()
    let correlation = try CoreSupportCaseRunCorrelationV1(
      caseID: "edge-mismatch", gateRunID: runID, swiftRunID: runID, tlcRunID: runID,
      comparisonRunID: runID)
    let admission = try CoreSupportAdmissionV1(gateRunID: runID, entries: [
      try CoreSupportAdmissionEntryV1(
        supportID: "clock-transitions", decision: .admitted, reasonCodes: [],
        mandatoryCaseIDs: ["edge-mismatch"], divergenceIDs: [], evidence: [try evidence("comparison.json")],
        caseRunCorrelations: [correlation]),
      try CoreSupportAdmissionEntryV1(
        supportID: "unrelated-support", decision: .unsupported,
        reasonCodes: [.explicitlyUnsupported], mandatoryCaseIDs: ["edge-mismatch"],
        divergenceIDs: [])
    ])

    #expect(admission.counts.admitted == 1)
    #expect(admission.counts.unsupported == 1)
    #expect(admission.counts.unexplained == 0)
    #expect(admission.finalExitClass == .success)

    let encodedAdmission = try JSONEncoder().encode(admission)
    var admissionObject = try #require(JSONSerialization.jsonObject(with: encodedAdmission) as? [String: Any])
    admissionObject["finalExitClass"] = "blocked"
    let inconsistentExitClass = try JSONSerialization.data(withJSONObject: admissionObject)
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "admission", field: "finalExitClass")) {
      _ = try JSONDecoder().decode(CoreSupportAdmissionV1.self, from: inconsistentExitClass)
    }
  }

  private var digest: String { String(repeating: "a", count: 64) }

  private func bounds() throws -> CoreFiniteBoundsV1 {
    try CoreFiniteBoundsV1(summary: "12 clock states", limits: ["states": 12])
  }

  private func evidence(_ path: String) throws -> CoreEvidenceReferenceV1 {
    try CoreEvidenceReferenceV1(path: "Verification/CoreConformance/\(path)", sha256: digest)
  }

  private func provenance() throws -> CoreDivergenceProvenanceV1 {
    try CoreDivergenceProvenanceV1(
      caseID: "edge-mismatch", moduleSHA256: digest, cfgSHA256: digest, argumentsSHA256: digest,
      tlcTag: "v1.8.0", tlcCommit: "commit", tlcJarSHA256: digest,
      javaDistribution: "Eclipse Temurin", javaVersion: "17", javaArchiveSHA256: digest,
      bridgeClass: "bridge", bridgeSourceSHA256: digest, bridgeBinarySHA256: digest)
  }

  private func divergenceRecord() throws -> CoreDivergenceRecordV1 {
    try CoreDivergenceRecordV1(
      id: "edge-mismatch", provenance: try provenance(), semanticCitations: ["citation"],
      reproducer: try bounds(), originalEvidence: try evidence("original.json"),
      permanentRegressionCaseID: "edge-mismatch-regression", classification: .swiftTLADefect,
      disposition: .open, normalizedDifferenceFingerprint: "fingerprint",
      latestComparison: try CoreDivergenceComparisonV1(
        evidence: try evidence("latest.json"), outcome: .difference,
        normalizedDifferenceFingerprint: "fingerprint"))
  }

  private func supportEntry(linkedDivergences: [String]) throws -> CoreSupportSurfaceEntryV1 {
    try CoreSupportSurfaceEntryV1(
      id: "clock-transitions", behavior: "hour clock transitions", category: .transitionRelation,
      finiteBounds: try bounds(), mandatoryCaseIDs: ["edge-mismatch"], requestedStatus: .requested,
      linkedDivergenceIDs: linkedDivergences)
  }
}
