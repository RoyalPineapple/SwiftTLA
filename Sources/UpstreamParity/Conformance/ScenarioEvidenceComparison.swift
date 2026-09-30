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
        let rendered = try scenario.render()
        let graphChecks = rendered.checkNames.intersection(
            rendered.invariantNames.union(rendered.reachabilityNames))
        let checkedBundle = try rendered.tlaBundle(checking: graphChecks,
            checkDeadlock: rendered.checksDeadlock)
        let checkFreeBundle = try rendered.tlaBundle(checking: [], checkDeadlock: false)
        let processURL = oracle.appendingPathComponent("tlc-graph/tlc-process.json")
        let process = try JSONSerialization.jsonObject(with: Data(contentsOf: processURL)) as? [String: Any]
        let inputs = process?["inputs"] as? [[String: String]]
        let inputPairs = inputs?.compactMap { input -> (String, String)? in
            guard input.count == 2, let file = input["file"], let hash = input["sha256"] else {
                return nil
            }
            return (file, hash)
        }
        guard process?["caseID"] as? String == caseID,
              let inputs, let inputPairs, inputPairs.count == inputs.count,
              Set(inputPairs.map(\.0)).count == inputPairs.count,
              let configuration = process?["configuration"] as? String else {
            throw ValidationEvidenceComparisonError.invalidEvidence("generated TLC graph input")
        }
        let inputMap = Dictionary(uniqueKeysWithValues: inputPairs)
        func matches(_ bundle: TLAModuleBundle) -> Bool {
            configuration == bundle.cfg && inputMap == Dictionary(uniqueKeysWithValues:
                bundleInputJSON(bundle).map { ($0["file"]!, $0["sha256"]!) })
        }
        let checkedMatches = matches(checkedBundle)
        let checkFreeMatches = tlc.graphComplete && matches(checkFreeBundle)
        guard checkedMatches || checkFreeMatches else {
            throw ValidationEvidenceComparisonError.invalidEvidence("generated TLC graph input")
        }
        if checkedMatches, tlc.graphComplete {
            let graphVerdictsMatch = graphChecks.allSatisfy { name in
                tlc.properties[name] == (rendered.reachabilityNames.contains(name) ? .unreachable : .satisfied)
            }
            guard graphVerdictsMatch,
                  !rendered.checksDeadlock || tlc.deadlock == .satisfied else {
                throw ValidationEvidenceComparisonError.invalidEvidence("completed TLC graph verdict")
            }
        }
        if checkFreeMatches && !checkedMatches &&
            !FileManager.default.fileExists(atPath: oracle.appendingPathComponent("tlc-check/tlc-process.json").path) {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing checked TLC pass")
        }
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
        if coverage.checksDeadlock && (swift.deadlock == nil || tlc.deadlock == nil) {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing deadlock verdict")
        }
        let result = try ValidationEvidenceComparison.compare(
            scenario: scenario, caseID: caseID, native: native, oracle: oracle,
            actions: actions, to: directory, spoolExecutable: spoolExecutable)
        try coverage.attach(to: directory.appendingPathComponent("comparison.json"))
        guard result.result == "exact" else { return result }
        for (property, expected) in scenario.expectations {
            guard let name = scenario.formalPropertyNames[property],
                  let nativeVerdict = swift.properties[name], nativeVerdict.satisfies(expected),
                  let oracleVerdict = tlc.properties[name], oracleVerdict.satisfies(expected) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected outcome")
            }
        }
        if let expected = scenario.deadlockExpectation {
            guard let nativeVerdict = swift.deadlock, nativeVerdict.satisfies(expected) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected deadlock")
            }
            guard let oracleVerdict = tlc.deadlock, oracleVerdict.satisfies(expected) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected deadlock")
            }
        }
        return result
    }
}
