import Foundation
import Testing
import UpstreamParity

struct CoreGovernanceRegisterFixtureTests {
  private let retainedFingerprintByCaseID = [
    "hour-clock-edge-mismatch": "4191a035e62b2f264f35cf8adbe8e29714d0fedd82ee823b11d31f0cc3f5fb53",
    "die-hard-violation": "7bd47a3941b836684ce33fcef619777c90657dbf423ed7a54989f04e6298452d"
  ]

  @Test("governance registers retain seeded divergences and bounded support")
  func retainsSeededDivergencesAndBoundedSupport() throws {
    let manifest = try decode(CoreConformanceCasesManifestV1.self, at: "cases.json")
    let ledger = try decode(CoreDivergenceLedgerV1.self, at: "divergences.json")
    let surface = try decode(CoreSupportSurfaceV1.self, at: "support-surface.json")

    try manifest.validate(ledger: ledger)
    try surface.validate(caseIDs: Set(manifest.cases.map(\.id)), ledger: ledger)

    let governanceByCaseID = Dictionary(uniqueKeysWithValues: manifest.cases.map { ($0.id, $0.governance) })
    #expect(governanceByCaseID.count == 4)
    #expect(governanceByCaseID["hour-clock"]?.role == .requiredComparison)
    #expect(governanceByCaseID["die-hard-type-ok"]?.role == .requiredComparison)
    #expect(governanceByCaseID["hour-clock-edge-mismatch"]?.role == .permanentRegression)
    #expect(governanceByCaseID["die-hard-violation"]?.role == .permanentRegression)
    #expect(manifest.cases.allSatisfy { !$0.governance.semanticCitations.isEmpty })

    #expect(Set(ledger.records.map(\.id)) == ["hour-clock-edge-mismatch", "die-hard-violation"])
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
      "die-hard-type-safety"
    ])
    #expect(surface.entries.filter { $0.requestedStatus == .unsupported }.count == 3)
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

  private func projectURL(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(path)
      .standardizedFileURL
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

  private enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() { self = .null }
      else if let value = try? container.decode(Bool.self) { self = .bool(value) }
      else if let value = try? container.decode(Double.self) { self = .number(value) }
      else if let value = try? container.decode(String.self) { self = .string(value) }
      else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
      else { self = .array(try container.decode([JSONValue].self)) }
    }
  }
}
