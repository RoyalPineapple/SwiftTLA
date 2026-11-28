import Foundation
import SwiftTLA
import UpstreamParity

/// Both pinned TLC witnesses must replay, step for step, on the generated Swift machine.
func compareReferenceWitness<S: ModelValidationScenario>(
    _ scenario: S, id: String, directory: URL, tools: ResolvedTLCToolchain,
    pin: TLCReferencePin, timeout: TimeInterval
) throws {
    let rendered = try scenario.render()
    let expected = scenario.checking.properties.filter { scenario.expectations[$0] == .violated }
    guard expected.count == 1, let property = expected.first,
          let name = scenario.formalPropertyNames[property], rendered.invariantNames.contains(name) else {
        throw ValidationCLIError.invalidManifest("one selected invariant must be expected to fail")
    }
    let generated = directory.appendingPathComponent("generated")
    try GeneratedTLCOracle.retainGeneratedInputs(rendered.tlaBundle, in: directory.appendingPathComponent("export"))
    let outcome = try GeneratedTLCOracle.run(bundle: rendered.tlaBundle, id: id,
        maximumStates: 10_000_000, timeout: timeout, tools: tools, pin: pin, workRoot: directory,
        retained: generated, invocation: .finiteGraph, renderedActions: rendered.actions, process: TLCProcessAdapter())
    guard outcome == .safetyViolation else { throw ValidationCLIError.invalidManifest("generated TLC outcome: \(outcome)") }
    let initial = try scenario.initialMachines()
    func replay(_ root: URL) throws -> GraphTrace {
        let log = try String(contentsOf: root.appendingPathComponent("logs/tlc.stdout.log"), encoding: .utf8)
        guard log.split(whereSeparator: \.isNewline).contains(where: {
            $0 == "Error: Invariant \(name) is violated." || $0 == "Error: Invariant \(name) is violated by the initial state:"
        }) else { throw ValidationCLIError.invalidManifest("TLC did not identify \(name)") }
        let data = try Data(contentsOf: root.appendingPathComponent("counterexample.json"))
        let result = try TLCTraceParser().replaySampledCounterexample(data, initialMachines: initial,
            renderedActions: rendered.actions, maximumDepth: Int.max, checkingDeadlock: false)
        guard try result.final.violatedInvariants(checking: [property], atLevel: result.trace.steps.count).contains(property) else {
            throw ValidationCLIError.invalidManifest("Swift did not violate \(name) at the final witness state")
        }
        return result.trace
    }
    let published = try replay(directory)
    guard try replay(generated).steps == published.steps else {
        throw ValidationCLIError.invalidManifest("different labeled witnesses")
    }
    let receipt: [String: Any] = ["caseID": id, "mode": "exact-violation-witness", "property": name,
        "states": published.steps.count, "actions": published.steps.compactMap(\.action), "graphCompared": false]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("witness-comparison.json"), options: .withoutOverwriting)
}
