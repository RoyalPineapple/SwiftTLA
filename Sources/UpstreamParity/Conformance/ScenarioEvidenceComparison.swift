import Foundation
import SwiftTLA

package enum ScenarioEvidenceComparison {
    package static func compare<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, native: URL, oracle: URL,
        actions: [RenderedAction], to directory: URL, spoolExecutable: URL? = nil
    ) throws -> ValidationEvidenceComparisonReport {
        let decoder = JSONDecoder()
        let swift = try decoder.decode(NativeValidationReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let tlc = try decoder.decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        let coverage = try ScenarioCheckCoverage(scenario)
        guard swift.scenario == scenario.name,
              swift.deadlockSelected == coverage.checksDeadlock,
              tlc.deadlockSelected == coverage.checksDeadlock,
              Set(swift.properties.keys) == Set(coverage.selectedProperties),
              Set(tlc.properties.keys) == Set(coverage.selectedProperties) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("scenario check coverage")
        }
        if !coverage.checksDeadlock && (swift.deadlock != nil || tlc.deadlock != nil) {
            throw ValidationEvidenceComparisonError.invalidEvidence("unselected deadlock verdict")
        }
        if coverage.checksDeadlock &&
            ((swift.graphComplete && swift.deadlock == nil) || (tlc.graphComplete && tlc.deadlock == nil)) {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing deadlock verdict")
        }
        let result = try ValidationEvidenceComparison.compare(
            scenario: scenario, caseID: caseID, native: native, oracle: oracle,
            actions: actions, to: directory, spoolExecutable: spoolExecutable)
        try coverage.attach(to: directory.appendingPathComponent("comparison.json"))
        return result
    }
}
