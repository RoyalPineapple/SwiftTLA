import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct NativeSampledValidationTests {
    private struct Trace: Decodable {
        let kind: String
        let property: String
        let steps: [Step]

        struct Step: Decodable {
            let state: [String: TLAValue]
        }
    }

    private func sampledScenario() throws -> TraceReplayInitialFailure.ValidationScenario {
        let original = try #require(TraceReplayInitialFailure.validationScenarios().first)
        return TraceReplayInitialFailure.ValidationScenario(
            name: original.name, displayName: original.displayName,
            checking: .init(properties: [.BelowThree], checkDeadlock: false),
            checkingMode: .simulation(traces: 2, maximumDepth: 3),
            behavior: original.behavior, selectedSymmetry: original.selectedSymmetry,
            selectedFairnessProfile: original.selectedFairnessProfile,
            selectedFairnessProfileName: original.selectedFairnessProfileName,
            selectedView: original.selectedView,
            selectedPostcondition: original.selectedPostcondition,
            postconditionName: original.postconditionName,
            postconditionExpectation: original.postconditionExpectation,
            expectations: [.BelowThree: .violated], deadlockExpectation: nil)
    }

    @Test("sampled native checking retains a complete initial invariant witness")
    func initialInvariantWitness() throws {
        let scenario = try sampledScenario()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let report = try NativeValidationRunner.run(
            scenario: scenario, caseID: "sampled-initial", maximumStates: 10, to: output)
        #expect(!report.graphComplete)
        #expect(report.properties == ["BelowThree": ValidationVerdict.violated])
        #expect(report.deadlock == nil)
        let data = try Data(contentsOf: output.appendingPathComponent("sampled-traces.jsonl"))
        let first = try #require(data.split(separator: 0x0A).first)
        let trace = try JSONDecoder().decode(Trace.self, from: Data(first))
        #expect(trace.kind == "violation")
        #expect(trace.property == "BelowThree")
        #expect(trace.steps.count == 1)
        #expect(trace.steps.first?.state == ["x": .int(3)])
    }

    @Test("sampled evidence retains every requested inconclusive behavior")
    func retainsEverySampledTrace() throws {
        let original = try #require(TraceReplayInitialFailure.validationScenarios().first)
        let scenario = TraceReplayInitialFailure.ValidationScenario(
            name: original.name, displayName: original.displayName,
            checking: .init(properties: [], checkDeadlock: false),
            checkingMode: .simulation(traces: 2, maximumDepth: 3),
            behavior: original.behavior, selectedSymmetry: original.selectedSymmetry,
            selectedFairnessProfile: original.selectedFairnessProfile,
            selectedFairnessProfileName: original.selectedFairnessProfileName,
            selectedView: original.selectedView,
            selectedPostcondition: original.selectedPostcondition,
            postconditionName: original.postconditionName,
            postconditionExpectation: original.postconditionExpectation,
            expectations: [:], deadlockExpectation: nil)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let report = try NativeValidationRunner.run(
            scenario: scenario, caseID: "sampled-complete", maximumStates: 10, to: output)
        let lines = try Data(contentsOf: output.appendingPathComponent("sampled-traces.jsonl"))
            .split(separator: 0x0A)
        let traces = try lines.map { try JSONDecoder().decode(Trace.self, from: Data($0)) }
        #expect(traces.count == 2)
        #expect(traces.allSatisfy { $0.kind == "inconclusive" })
        #expect(traces.map { $0.steps.map(\.state["x"]) } ==
            Array(repeating: [.int(3), .int(4), .int(5), .int(6)], count: 2))
        #expect(report.initialStates == 2)
        #expect(report.states == 8)
        #expect(report.edges == 6)
    }

    @Test("sampled verdict parity requires replayable independent TLC evidence")
    func comparesSampledWitnesses() throws {
        let scenario = try sampledScenario()
        let caseID = "sampled-initial"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let native = root.appendingPathComponent("native")
        _ = try NativeValidationRunner.run(
            scenario: scenario, caseID: caseID, maximumStates: 10, to: native)
        let oracle = root.appendingPathComponent("oracle")
        let retained = oracle.appendingPathComponent("tlc-graph")
        let logs = retained.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let rendered = try scenario.render()
        let bundle = try rendered.tlaBundle(checking: rendered.checkNames, checkDeadlock: false)
        let pin = try testReferencePin()
        let arguments = GeneratedTLCOracle.simulationArguments(traces: 2, maximumDepth: 3)
        let report = GeneratedTLCOracleReport(
            schema: "swifttla.generated-tlc-oracle", caseID: caseID,
            scenario: scenario.name, maximumStates: 10, graphComplete: false,
            graphInputSHA256: try GeneratedTLCOracle.inputIdentity(
                bundle: bundle, pin: pin, arguments: arguments, invocation: .propertyCheck),
            properties: ["BelowThree": .violated], deadlock: nil, deadlockSelected: false,
            postconditionName: nil, postcondition: nil)
        try JSONEncoder().encode(report).write(to: oracle.appendingPathComponent("oracle.json"))
        let process: [String: Any] = [
            "caseID": caseID,
            "configuration": bundle.cfg,
            "inputs": bundleInputJSON(bundle),
            "toolPin": [
                "tag": pin.tag, "commit": pin.commit, "jarSHA256": pin.jarSHA256,
                "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
                "javaArchiveSHA256": pin.javaArchiveSHA256, "bridgeClass": pin.bridgeClass,
                "bridgeSourceHashes": pin.bridgeSourceHashes,
                "bridgeBinarySHA256": pin.bridgeBinarySHA256
            ],
            "invocation": ["arguments": arguments + ["-config", "configuration", "module"],
                           "exitStatus": 12]
        ]
        try JSONSerialization.data(withJSONObject: process)
            .write(to: retained.appendingPathComponent("tlc-process.json"))
        try Data("Error: Invariant BelowThree is violated by the initial state:\n".utf8)
            .write(to: logs.appendingPathComponent("tlc.stdout.log"))
        let trace = retained.appendingPathComponent("counterexample.json")
        try Data(#"{"vars":["x"],"counterexample":{"state":[[1,{"x":3}]],"action":[]}}"#.utf8)
            .write(to: trace)
        let comparison = try ScenarioEvidenceComparison.compare(
            scenario: scenario, caseID: caseID, native: native, oracle: oracle,
            actions: rendered.actions, to: root.appendingPathComponent("comparison"))
        #expect(comparison.result == "exact")
        #expect(!comparison.graphCompared)

        try Data(#"{"vars":["x"],"counterexample":{"state":[[1,{"x":4}]],"action":[]}}"#.utf8)
            .write(to: trace)
        #expect(throws: TLCTraceError.self) {
            try ScenarioEvidenceComparison.compare(
                scenario: scenario, caseID: caseID, native: native, oracle: oracle,
                actions: rendered.actions, to: root.appendingPathComponent("invalid-comparison"))
        }
    }
}
