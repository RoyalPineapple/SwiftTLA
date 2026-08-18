import Foundation
import Testing
import UpstreamParity

struct CoreGovernanceRegisterFixtureTests {
  private let retainedFingerprintByCaseID = [
    "hour-clock-edge-mismatch": "4191a035e62b2f264f35cf8adbe8e29714d0fedd82ee823b11d31f0cc3f5fb53",
    "die-hard-violation": "7bd47a3941b836684ce33fcef619777c90657dbf423ed7a54989f04e6298452d",
    "multicar-elevator-edge-mismatch": "b9b341af04cff0ea34a04e0053496b1fa3a7b14102ef891da84d2e44820846a5"
  ]

  @Test("governance registers retain seeded divergences and bounded support")
  func retainsSeededDivergencesAndBoundedSupport() throws {
    let manifest = try decode(CoreConformanceCasesManifestV1.self, at: "cases.json")
    let ledger = try decode(CoreDivergenceLedgerV1.self, at: "divergences.json")
    let surface = try decode(CoreSupportSurfaceV1.self, at: "support-surface.json")

    try manifest.validate(ledger: ledger)
    try surface.validate(caseIDs: Set(manifest.cases.map(\.id)), ledger: ledger)

    let governanceByCaseID = Dictionary(uniqueKeysWithValues: manifest.cases.map { ($0.id, $0.governance) })
    #expect(governanceByCaseID.count == 6)
    #expect(governanceByCaseID["hour-clock"]?.role == .requiredComparison)
    #expect(governanceByCaseID["die-hard-type-ok"]?.role == .requiredComparison)
    #expect(governanceByCaseID["hour-clock-edge-mismatch"]?.role == .permanentRegression)
    #expect(governanceByCaseID["die-hard-violation"]?.role == .permanentRegression)
    #expect(governanceByCaseID["multicar-elevator"]?.role == .requiredComparison)
    #expect(governanceByCaseID["multicar-elevator-edge-mismatch"]?.role == .permanentRegression)
    #expect(manifest.cases.allSatisfy { !$0.governance.semanticCitations.isEmpty })

    #expect(Set(ledger.records.map(\.id)) == [
      "hour-clock-edge-mismatch", "die-hard-violation", "multicar-elevator-edge-mismatch"
    ])
    for record in ledger.records {
      #expect(record.disposition == .unsupported)
      #expect(record.latestComparison.outcome == .difference)
      #expect(record.normalizedDifferenceFingerprint == record.latestComparison.normalizedDifferenceFingerprint)
      try verify(record.originalEvidence)
      try verify(record.latestComparison.evidence)
      let retained = try decode(RetainedComparison.self, atProjectPath: record.latestComparison.evidence.path)
      #expect(retained.conformant == false)
      #expect(retained.correlation.caseID == record.permanentRegressionCaseID)
      #expect(retained.correlation.engine == "runner")
      #expect(!retained.differences.isEmpty)
      let fingerprint = try CoreDivergenceLedgerV1.normalizedDifferenceFingerprint(
        from: Data(contentsOf: projectURL(record.latestComparison.evidence.path)))
      #expect(record.normalizedDifferenceFingerprint == fingerprint)
      #expect(retainedFingerprintByCaseID[record.id] == fingerprint)

      let driftedFingerprint = try fingerprintWithDrift(from: record.latestComparison.evidence.path)
      #expect(driftedFingerprint != fingerprint)
    }

    let requested = surface.entries.filter { $0.requestedStatus == .requested }
    #expect(Set(requested.map(\.id)) == [
      "hour-clock-reachable-state-space",
      "hour-clock-transition-relation",
      "die-hard-type-safety",
      "multicar-elevator-reachable-state-space",
      "multicar-elevator-transition-relation"
    ])
    #expect(surface.entries.filter { $0.requestedStatus == .unsupported }.count == 4)
  }

  @Test("ledger provenance must match the current retained TLC reference pin")
  func rejectsLedgerPinThatDiffersFromRetainedEvidence() throws {
    let manifest = try decode(CoreConformanceCasesManifestV1.self, at: "cases.json")
    let ledger = try decode(CoreDivergenceLedgerV1.self, at: "divergences.json")

    for record in ledger.records {
      let toolchainPath = record.latestComparison.evidence.path
        .replacingOccurrences(of: "comparison.json", with: "toolchain.json")
      let toolchain = try decode(RetainedToolchain.self, atProjectPath: toolchainPath)
      #expect(record.provenance.tlcTag == toolchain.declaredPin.tag)
      #expect(record.provenance.tlcCommit == toolchain.declaredPin.commit)
      #expect(record.provenance.tlcJarSHA256 == toolchain.declaredPin.jarSHA256)
      #expect(record.provenance.javaDistribution == toolchain.declaredPin.javaDistribution)
      #expect(record.provenance.javaVersion == toolchain.declaredPin.javaVersion)
      #expect(record.provenance.javaArchiveSHA256 == toolchain.declaredPin.javaArchiveSHA256)
      #expect(record.provenance.bridgeClass == toolchain.declaredPin.bridgeClass)
      #expect(record.provenance.bridgeSourceSHA256 == toolchain.declaredPin.bridgeSourceSHA256)
      #expect(record.provenance.bridgeBinarySHA256 == toolchain.declaredPin.bridgeBinarySHA256)
    }

    let alteredRecord = try #require(ledger.records.first)
    let alteredProvenance = try CoreDivergenceProvenanceV1(
      caseID: alteredRecord.provenance.caseID,
      moduleSHA256: alteredRecord.provenance.moduleSHA256,
      cfgSHA256: alteredRecord.provenance.cfgSHA256,
      argumentsSHA256: alteredRecord.provenance.argumentsSHA256,
      tlcTag: alteredRecord.provenance.tlcTag,
      tlcCommit: "retired-pin",
      tlcJarSHA256: alteredRecord.provenance.tlcJarSHA256,
      javaDistribution: alteredRecord.provenance.javaDistribution,
      javaVersion: alteredRecord.provenance.javaVersion,
      javaArchiveSHA256: alteredRecord.provenance.javaArchiveSHA256,
      bridgeClass: alteredRecord.provenance.bridgeClass,
      bridgeSourceSHA256: alteredRecord.provenance.bridgeSourceSHA256,
      bridgeBinarySHA256: alteredRecord.provenance.bridgeBinarySHA256)
    let alteredLedger = try CoreDivergenceLedgerV1(records: ledger.records.map { record in
      guard record.id == alteredRecord.id else { return record }
      return try CoreDivergenceRecordV1(
        id: record.id, provenance: alteredProvenance, semanticCitations: record.semanticCitations,
        reproducer: record.reproducer, originalEvidence: record.originalEvidence,
        permanentRegressionCaseID: record.permanentRegressionCaseID,
        classification: record.classification, disposition: record.disposition,
        normalizedDifferenceFingerprint: record.normalizedDifferenceFingerprint,
        latestComparison: record.latestComparison)
    })

    #expect(throws: CoreGovernanceErrorV1.invalidField(
      record: alteredRecord.id, field: "TLC reference pin")) {
      try manifest.validate(ledger: alteredLedger)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, at path: String) throws -> T {
    try JSONDecoder().decode(type, from: fixtureData(path))
  }

  private func decode<T: Decodable>(_ type: T.Type, atProjectPath path: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: projectURL(path)))
  }

  private func verify(_ evidence: CoreEvidenceReferenceV1) throws {
    #expect(SHA256V1.hex(try Data(contentsOf: projectURL(evidence.path))) == evidence.sha256)
  }

  private func fingerprintWithDrift(from path: String) throws -> String {
    var comparison = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: projectURL(path))) as? [String: Any])
    var differences = try #require(comparison["differences"] as? [[String: Any]])
    var firstDifference = try #require(differences.first)
    firstDifference["category"] = "fingerprint-drift"
    differences[0] = firstDifference
    comparison["differences"] = differences
    let data = try JSONSerialization.data(withJSONObject: comparison, options: [.sortedKeys])
    return try CoreDivergenceLedgerV1.normalizedDifferenceFingerprint(from: data)
  }

  private func fixtureData(_ path: String) throws -> Data {
    try Data(contentsOf: fixtureURL(path))
  }

  private func fixtureURL(_ path: String) -> URL {
    projectURL("Verification/CoreConformance/\(path)")
  }

  private struct RetainedComparison: Decodable {
    struct Correlation: Decodable {
      let caseID: String
      let engine: String
    }

    let conformant: Bool
    let correlation: Correlation
    let differences: [JSONValue]
  }

  private struct RetainedToolchain: Decodable {
    struct Pin: Decodable {
      let tag: String
      let commit: String
      let jarSHA256: String
      let javaDistribution: String
      let javaVersion: String
      let javaArchiveSHA256: String
      let bridgeClass: String
      let bridgeSourceSHA256: String
      let bridgeBinarySHA256: String
    }

    let declaredPin: Pin
  }

  private enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        self = .null
      } else if let value = try? container.decode(Bool.self) {
        self = .bool(value)
      } else if let value = try? container.decode(Double.self) {
        self = .number(value)
      } else if let value = try? container.decode(String.self) {
        self = .string(value)
      } else if let value = try? container.decode([String: JSONValue].self) {
        self = .object(value)
      } else {
        self = .array(try container.decode([JSONValue].self))
      }
    }
  }
}
