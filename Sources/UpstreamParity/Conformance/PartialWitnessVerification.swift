import Foundation
import SwiftTLA

/// Replays a TLC counterexample against the generated machine only at the
/// comparison boundary; neither evidence producer reads the other engine.
package enum PartialWitnessVerification {
    package static func verify<Scenario: ModelValidationScenario>(
        scenario: Scenario, report: GeneratedTLCOracleReport, exitStatus: Int,
        oracle: URL, rendered: RenderedSpecification
    ) throws {
        let names = scenario.formalPropertyNames
        guard !report.graphComplete, report.scenario == scenario.name,
              report.deadlockSelected == scenario.checking.checkDeadlock,
              Set(report.properties.keys) == rendered.checkNames,
              Set(scenario.checking.properties.compactMap { names[$0] }) == rendered.checkNames else {
            throw ValidationEvidenceComparisonError.invalidEvidence("partial witness selection")
        }
        let root = oracle.appendingPathComponent("tlc-graph")
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
            return
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
                  try replay.final.violatedInvariants(checking: [property]).contains(property) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("false TLC invariant witness")
            }
        }
    }
}
