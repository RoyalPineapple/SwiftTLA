import Foundation
import SwiftTLA

/// Replays a TLC counterexample against the generated machine only at the
/// comparison boundary; neither evidence producer reads the other engine.
package enum TLCWitnessVerification {
    @discardableResult
    package static func verifyPartial<Scenario: ModelValidationScenario>(
        scenario: Scenario, report: GeneratedTLCOracleReport, exitStatus: Int,
        oracle: URL, rendered: RenderedSpecification
    ) throws -> Int {
        guard !report.graphComplete else {
            throw ValidationEvidenceComparisonError.invalidEvidence("partial witness selection")
        }
        return try verify(scenario: scenario, report: report, exitStatus: exitStatus,
            root: oracle.appendingPathComponent("tlc-graph"), rendered: rendered)
    }

    package static func verifyChecked<Scenario: ModelValidationScenario>(
        scenario: Scenario, report: GeneratedTLCOracleReport, caseID: String,
        oracle: URL, rendered: RenderedSpecification
    ) throws {
        guard report.graphComplete else {
            throw ValidationEvidenceComparisonError.invalidEvidence("checked witness selection")
        }
        let root = oracle.appendingPathComponent("tlc-check")
        let process = try JSONSerialization.jsonObject(with:
            Data(contentsOf: root.appendingPathComponent("tlc-process.json"))) as? [String: Any]
        let graphChecks = rendered.checkNames.intersection(
            rendered.invariantNames.union(rendered.reachabilityNames))
        let bundle = try rendered.tlaBundle(checking: graphChecks,
            checkDeadlock: rendered.checksDeadlock)
        let inputs = process?["inputs"] as? [[String: String]]
        let pairs = inputs?.compactMap { input -> (String, String)? in
            guard input.count == 2, let file = input["file"], let hash = input["sha256"] else {
                return nil
            }
            return (file, hash)
        }
        let expected = Dictionary(uniqueKeysWithValues: bundleInputJSON(bundle).map {
            ($0["file"]!, $0["sha256"]!)
        })
        guard process?["caseID"] as? String == caseID,
              process?["configuration"] as? String == bundle.cfg,
              let inputs, let pairs, pairs.count == inputs.count,
              Set(pairs.map(\.0)).count == pairs.count,
              Dictionary(uniqueKeysWithValues: pairs) == expected,
              let invocation = process?["invocation"] as? [String: Any],
              let status = invocation["exitStatus"] as? Int,
              status == 11 || status == 12 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("checked TLC process input or outcome")
        }
        _ = try verify(scenario: scenario, report: report, exitStatus: status,
            root: root, rendered: rendered)
    }

    private static func verify<Scenario: ModelValidationScenario>(
        scenario: Scenario, report: GeneratedTLCOracleReport, exitStatus: Int,
        root: URL, rendered: RenderedSpecification
    ) throws -> Int {
        let names = scenario.formalPropertyNames
        guard report.scenario == scenario.name,
              report.deadlockSelected == scenario.checking.checkDeadlock,
              Set(report.properties.keys) == rendered.checkNames,
              Set(scenario.checking.properties.compactMap { names[$0] }) == rendered.checkNames else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC witness selection")
        }
        let traceURL = root.appendingPathComponent("counterexample.json")
        guard let trace = try? Data(contentsOf: traceURL), !trace.isEmpty else {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing TLC counterexample")
        }
        let replay = try TLCTraceParser().replayCounterexample(
            trace, initialMachines: scenario.initialMachines(), renderedActions: rendered.actions,
            maximumStates: report.maximumStates, checkingDeadlock: exitStatus == 11)

        if exitStatus == 11 {
            guard report.deadlock == .violated, replay.finalIsDeadlocked == true else {
                throw ValidationEvidenceComparisonError.invalidEvidence("false TLC deadlock witness")
            }
            return replay.trace.steps.count
        }
        guard exitStatus == 12 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("partial TLC process outcome")
        }
        let stdout = try String(contentsOf: root.appendingPathComponent("logs/tlc.stdout.log"), encoding: .utf8)
        let reported = rendered.invariantNames.union(rendered.reachabilityNames).filter { name in
            stdout.split(whereSeparator: \.isNewline).contains {
                $0 == "Error: Invariant \(name) is violated."
                    || (replay.trace.steps.count == 1
                        && $0 == "Error: Invariant \(name) is violated by the initial state:")
            }
        }
        guard reported.count == 1, let name = reported.first,
              let property = names.first(where: { $0.value == name })?.key else {
            throw ValidationEvidenceComparisonError.invalidEvidence("unidentified TLC counterexample")
        }
        if rendered.reachabilityNames.contains(name) {
            guard report.properties[name] == .reached,
                  try replay.final.matchedReachabilityProperties(checking: [property]).contains(property) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("false TLC reachability witness")
            }
        } else {
            guard report.properties[name] == .violated,
                  try replay.final.violatedInvariants(checking: [property], atLevel: replay.trace.steps.count).contains(property) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("false TLC invariant witness")
            }
        }
        return replay.trace.steps.count
    }
}
