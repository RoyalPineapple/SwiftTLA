import Foundation
import Testing
import UpstreamParity

struct FiniteGraphManifestTests {
  @Test("reference cases reject unknown comparison modes")
  func rejectsUnknownComparisonMode() throws {
    let source = try Data(contentsOf: URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/FiniteGraph/cases.json"))
    let text = String(decoding: source, as: UTF8.self)
      .replacingOccurrences(of: "\"decisive-counterexample\"", with: "\"partial-graph\"")
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FiniteGraphManifest.self, from: Data(text.utf8))
    }
  }

  @Test("one native model can declare separate reference configurations")
  func acceptsMultipleConfigurations() throws {
    let manifest = try decodeCases(ids: ["hour-clock-default", "hour-clock-no-deadlock"])
    #expect(manifest.cases.map(\.id) == ["hour-clock-default", "hour-clock-no-deadlock"])
    #expect(manifest.cases.map(\.sourceModel) == [.hourClock, .hourClock])
    #expect(Set(manifest.cases.map(\.configuration)).count == 2)
  }

  @Test("case identifiers remain unique across configurations")
  func rejectsDuplicateCaseIDs() {
    #expect(throws: EvidenceFormatError.duplicateID(kind: "finite graph case", id: "same")) {
      try decodeCases(ids: ["same", "same"])
    }
  }

  @Test("case identifiers cannot escape output directories or shadow the all selector",
    arguments: ["", "all", "../outside", "/tmp/outside", "a/b", ".", "..", "a\n", "é"])
  func rejectsInvalidCaseIDs(id: String) {
    #expect(throws: FiniteGraphCaseError.invalidIdentifier("case ID")) {
      try decodeCases(ids: [id])
    }
  }

  @Test("a missing case identity is not inferred from its source model")
  func requiresExplicitCaseID() {
    #expect(throws: DecodingError.self) {
      try decodeCases(ids: [nil])
    }
  }

  private func decodeCases(ids: [String?]) throws -> FiniteGraphManifest {
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/FiniteGraph/cases.json")
    let source = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    let cases = try #require(source["cases"] as? [[String: Any]])
    let original = try #require(cases.first { $0["sourceModel"] as? String == "hour-clock" })
    let variants = ids.enumerated().map { index, id in
      var variant = original
      variant["id"] = id
      variant["configuration"] = "hour-clock/variant-\(index).cfg"
      return variant
    }
    return try JSONDecoder().decode(FiniteGraphManifest.self,
      from: JSONSerialization.data(withJSONObject: ["schema": "FiniteGraphCases", "cases": variants]))
  }
}
