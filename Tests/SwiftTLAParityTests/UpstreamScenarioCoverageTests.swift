import Foundation
import Testing
@testable import UpstreamParity

struct UpstreamScenarioCoverageTests {
    @Test("cached upstream evidence reports selected and omitted model checks")
    func annotatesRetainedComparison() throws {
        let scenario = try #require(SelectedChecksModel.validationScenarios().first { $0.name == "Selected" })
        let url = try retainedReport(properties: ["Reached": .reached, "Safe": .satisfied])
        defer { try? FileManager.default.removeItem(at: url) }

        try ScenarioCheckCoverage.annotateUpstream(scenario, caseID: "fixture", reportURL: url)
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let value = try #require(report["coverage"])
        let coverage = try JSONDecoder().decode(ScenarioCheckCoverage.self,
            from: JSONSerialization.data(withJSONObject: value))
        #expect(coverage.selectedProperties == ["Reached", "Safe"])
        #expect(coverage.omittedProperties == ["InitiallyZero", "StaysZero"])
        #expect(!coverage.coversCompleteScenario)
        #expect(report["result"] as? String == "exact")
    }

    @Test("a complete upstream comparison cannot omit a scenario-selected check")
    func rejectsIncompleteSelectedVerdicts() throws {
        let scenario = try #require(SelectedChecksModel.validationScenarios().first { $0.name == "Selected" })
        let url = try retainedReport(properties: ["Safe": .satisfied])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: EvidenceFormatError.self) {
            try ScenarioCheckCoverage.annotateUpstream(scenario, caseID: "fixture", reportURL: url)
        }
    }

    private func retainedReport(properties: [String: ValidationVerdict]) throws -> URL {
        let report = UpstreamTLCParityReport(
            schema: "swifttla.upstream-tlc-parity", caseID: "fixture",
            result: "exact", graphCompared: true, difference: nil,
            generatedProperties: properties, referenceProperties: properties,
            generatedDeadlock: nil, referenceDeadlock: nil, deadlockSelected: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try JSONEncoder().encode(report).write(to: url)
        return url
    }
}
