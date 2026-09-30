import CryptoKit
import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct ValidationEvidenceComparisonTests {
    private let actions = [
        RenderedAction(sourceName: "Next", arguments: [], renderedName: "Next"),
        RenderedAction(sourceName: "Other", arguments: [], renderedName: "Other")
    ]

    @Test("binary producers compare the complete labeled graph")
    func completeGraphMatches() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try compare(root)
        #expect(result.result == "exact")
        #expect(result.graphCompared)
        #expect(result.difference == nil)
        let coverage = try coverage(root)
        #expect(coverage.selectedProperties.isEmpty)
        #expect(coverage.omittedProperties == ["InitiallyZero", "Reached", "Safe", "StaysZero"])
        #expect(!coverage.coversCompleteScenario)
    }

    @Test("matching reports cannot omit a selected property and claim parity")
    func missingSelectedVerdictsFail() throws {
        let root = try fixture(scenarioName: "Selected", omitSelectedVerdicts: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a complete graph can match an explicit subset without claiming full scenario coverage")
    func selectedVerdictsMatch() throws {
        let root = try fixture(scenarioName: "Selected")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try compare(root)
        #expect(result.result == "exact")
        #expect(result.graphCompared)
        let coverage = try coverage(root)
        #expect(coverage.selectedProperties == ["Reached", "Safe"])
        #expect(coverage.omittedProperties == ["InitiallyZero", "StaysZero"])
        #expect(!coverage.coversCompleteScenario)
    }

    @Test("cached matching verdicts cannot override the scenario's expected outcome")
    func staleExpectedOutcomeFails() throws {
        let root = try fixture(scenarioName: "Selected")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["native/report.json", "oracle/oracle.json"] {
            let url = root.appendingPathComponent(path)
            var report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var properties = try #require(report["properties"] as? [String: String])
            properties["Safe"] = "violated"
            report["properties"] = properties
            try JSONSerialization.data(withJSONObject: report).write(to: url)
        }
        #expect(throws: ValidationEvidenceComparisonError.invalidEvidence("scenario expected outcome")) {
            _ = try compare(root)
        }
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("comparison/comparison.json"))) as? [String: Any])
        #expect(report["result"] as? String == "exact")
        #expect(report["graphCompared"] as? Bool == true)
    }

    @Test("cached TLC graph evidence must name the current generated input and configuration")
    func staleGeneratedGraphInputFails() throws {
        for mismatch in ["source", "configuration"] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("oracle/tlc-graph/tlc-process.json")
            var process = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            if mismatch == "source" {
                var inputs = try #require(process["inputs"] as? [[String: String]])
                inputs[0]["sha256"] = String(repeating: "0", count: 64)
                process["inputs"] = inputs
            } else {
                process["configuration"] = "CHECK_DEADLOCK FALSE"
            }
            try JSONSerialization.data(withJSONObject: process).write(to: url)
            #expect(throws: ValidationEvidenceComparisonError.invalidEvidence("generated TLC graph input")) {
                _ = try compare(root)
            }
        }
    }

    @Test("a complete graph may use the separate check-free TLC input")
    func completeCheckFreeGraphInputMatches() throws {
        let root = try fixture(scenarioName: "Selected")
        defer { try? FileManager.default.removeItem(at: root) }
        let scenario = try #require(SelectedChecksModel.validationScenarios().first { $0.name == "Selected" })
        let bundle = try scenario.render().tlaBundle(checking: [], checkDeadlock: false)
        let url = root.appendingPathComponent("oracle/tlc-graph/tlc-process.json")
        var process = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        process["inputs"] = inputHashes(for: bundle)
        process["configuration"] = bundle.cfg
        try JSONSerialization.data(withJSONObject: process).write(to: url)
        #expect(try compare(root).graphCompared)
    }

    @Test("a verdict for a disabled deadlock check cannot establish parity")
    func unselectedDeadlockVerdictFails() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["native/report.json", "oracle/oracle.json"] {
            let url = root.appendingPathComponent(path)
            var report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            report["deadlock"] = "satisfied"
            try JSONSerialization.data(withJSONObject: report).write(to: url)
        }
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a selected deadlock check requires a verdict even after an early counterexample")
    func missingSelectedDeadlockVerdictFails() throws {
        for graphComplete in [true, false] {
            let root = try fixture(graphComplete: graphComplete,
                tlcExitStatus: graphComplete ? 0 : 12,
                scenarioName: "All")
            defer { try? FileManager.default.removeItem(at: root) }
            for path in ["native/report.json", "oracle/oracle.json"] {
                let url = root.appendingPathComponent(path)
                var report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                report.removeValue(forKey: "deadlock")
                try JSONSerialization.data(withJSONObject: report).write(to: url)
            }
            #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
        }
    }

    @Test("a changed state fails despite matching counts")
    func differentStateFails() throws {
        let root = try fixture(nativeTarget: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try compare(root).difference == "complete state set")
    }

    @Test("a changed endpoint or action label fails despite matching counts")
    func differentLabeledEdgeFails() throws {
        for (target, action) in [(UInt64(0), "Next"), (UInt64(1), "Other")] {
            let root = try fixture(nativeEdgeTarget: target, nativeAction: action)
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try compare(root).difference == "complete labeled edge set")
        }
    }

    @Test("repeated transitions count as one labeled graph edge")
    func duplicateEdgesHaveSetSemantics() throws {
        let root = try fixture(edgeCount: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        try tlcGraph(edgeCount: 1).write(
            to: root.appendingPathComponent("oracle/tlc-graph/graph-events.bin"))
        #expect(try compare(root).result == "exact")
    }

    @Test("a changed initial state fails despite matching state and edge sets")
    func differentInitialFails() throws {
        let root = try fixture(nativeInitial: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try compare(root).difference == "initial state set")
    }

    @Test("a damaged binary footer is rejected")
    func corruptFooterFails() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("oracle/tlc-graph/graph-events.bin")
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: url)
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a malformed complete value is rejected even with a valid footer digest")
    func malformedStateFails() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("native/machine.bin")
        var bytes = try Data(contentsOf: url)
        let key = try #require(bytes.range(of: Data("STLASV01".utf8)))
        bytes[key.lowerBound + 17] = 0xff
        let footer = bytes.count - (1 + 8 * 8 + 1 + 32)
        bytes.replaceSubrange((bytes.count - 32)..<bytes.count,
            with: Data(CryptoKit.SHA256.hash(data: bytes[..<footer])))
        try bytes.write(to: url)
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a truncated binary stream cannot establish parity")
    func truncatedEvidenceFails() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("oracle/tlc-graph/graph-events.bin")
        var bytes = try Data(contentsOf: url)
        bytes.removeLast()
        try bytes.write(to: url)
        #expect(throws: BinaryGraphEvidenceError.self) { _ = try compare(root) }
    }

    @Test("a failed TLC process cannot certify a partial counterexample")
    func failedPartialProcessFails() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 124)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a deadlock exit must agree with the reported deadlock verdict")
    func mismatchedPartialProcessFails() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 11)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["native/report.json", "oracle/oracle.json"] {
            let url = root.appendingPathComponent(path)
            var report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            report["deadlock"] = "satisfied"
            try JSONSerialization.data(withJSONObject: report).write(to: url)
        }
        #expect(throws: ValidationEvidenceComparisonError.invalidEvidence("TLC process outcome")) {
            _ = try compare(root)
        }
    }

    @Test("a decisive safety exit can certify verdict parity without claiming graph parity")
    func decisivePartialProcessComparesVerdicts() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 12)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try compare(root)
        #expect(result.result == "exact")
        #expect(!result.graphCompared)
    }

    @Test("a partial result without a TLC trace cannot be exact")
    func partialWitnessIsRequired() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 12)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("oracle/tlc-graph/counterexample.json"))
        #expect(throws: ValidationEvidenceComparisonError.self) { _ = try compare(root) }
    }

    @Test("a TLC counterexample with an impossible transition cannot certify parity")
    func impossiblePartialWitnessFails() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 12)
        defer { try? FileManager.default.removeItem(at: root) }
        let trace = root.appendingPathComponent("oracle/tlc-graph/counterexample.json")
        let corrupted = try String(contentsOf: trace, encoding: .utf8)
            .replacingOccurrences(of: #""value":1"#, with: #""value":2"#)
        try Data(corrupted.utf8).write(to: trace)
        #expect(throws: TLCTraceError.self) { _ = try compare(root) }
    }

    @Test("early reachability and deadlock witnesses replay against generated transitions")
    func otherPartialWitnessesReplay() throws {
        let root = try fixture(graphComplete: false, tlcExitStatus: 12)
        defer { try? FileManager.default.removeItem(at: root) }
        let scenario = try #require(SelectedChecksModel.validationScenarios().first)
        let rendered = try scenario.render()
        let oracle = root.appendingPathComponent("oracle")
        let reportURL = oracle.appendingPathComponent("oracle.json")
        let stdout = oracle.appendingPathComponent("tlc-graph/logs/tlc.stdout.log")
        try Data("Error: Invariant Reached is violated.\n".utf8).write(to: stdout)
        let reachability = try JSONDecoder().decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: reportURL))
        try PartialWitnessVerification.verify(scenario: scenario, report: reachability,
            exitStatus: 12, oracle: oracle, rendered: rendered)

        var deadlockJSON = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as? [String: Any])
        deadlockJSON["deadlock"] = "violated"
        let deadlock = try JSONDecoder().decode(GeneratedTLCOracleReport.self,
            from: JSONSerialization.data(withJSONObject: deadlockJSON))
        try PartialWitnessVerification.verify(scenario: scenario, report: deadlock,
            exitStatus: 11, oracle: oracle, rendered: rendered)
    }

    @Test("binary spools retain all edges across buffered reads")
    func binarySpoolsAcrossBatches() throws {
        let root = try fixture(edgeCount: 60_000)
        defer { try? FileManager.default.removeItem(at: root) }
        let spool = root.appendingPathComponent("tlc-spool")
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: false)
        try ValidationEvidenceComparison.writeTLCSpool(
            root.appendingPathComponent("oracle/tlc-graph/graph-events.bin"),
            caseID: "fixture", actions: actions, in: spool)
        let manifest = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: spool.appendingPathComponent("spool.json"))) as? [String: Any])
        #expect(manifest["stateCount"] as? Int == 2)
        #expect(manifest["edgeCount"] as? Int == 60_000)
        #expect(try Data(contentsOf: spool.appendingPathComponent("edges.raw")).count == 1_200_000)
        #expect(try compare(root).result == "exact")
    }

    @Test("two TLC runs compare full states despite different fingerprint IDs")
    func tlcGraphsMatchByValue() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let generated = root.appendingPathComponent("generated.bin")
        let reference = root.appendingPathComponent("reference.bin")
        try tlcGraph(edgeCount: 1).write(to: generated)
        try tlcGraph(edgeCount: 1, source: 303, target: 404).write(to: reference)
        #expect(try ValidationEvidenceComparison.compareTLCGraphs(caseID: "fixture",
            generated: generated, reference: reference, actions: actions, in: root) == nil)
    }

    private func compare(_ root: URL) throws -> ValidationEvidenceComparisonReport {
        let report = try JSONDecoder().decode(NativeValidationReport.self,
            from: Data(contentsOf: root.appendingPathComponent("native/report.json")))
        let scenario = try #require(SelectedChecksModel.validationScenarios().first { $0.name == report.scenario })
        return try ScenarioEvidenceComparison.compare(scenario: scenario, caseID: "fixture",
            native: root.appendingPathComponent("native"),
            oracle: root.appendingPathComponent("oracle"), actions: actions,
            to: root.appendingPathComponent("comparison"))
    }

    private func coverage(_ root: URL) throws -> ScenarioCheckCoverage {
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("comparison/comparison.json"))) as? [String: Any])
        let value = try #require(report["coverage"])
        return try JSONDecoder().decode(ScenarioCheckCoverage.self,
            from: JSONSerialization.data(withJSONObject: value))
    }

    private func fixture(nativeTarget: Int = 1, nativeEdgeTarget: UInt64 = 1,
        nativeAction: String = "Next",
        nativeInitial: UInt64 = 0,
        edgeCount: Int = 1, graphComplete: Bool = true, tlcExitStatus: Int = 0,
        scenarioName: String? = nil, omitSelectedVerdicts: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let native = root.appendingPathComponent("native")
        let tlc = root.appendingPathComponent("oracle/tlc-graph")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tlc, withIntermediateDirectories: true)
        let name = scenarioName ?? (graphComplete ? "Graph only" : "All")
        let scenario = try #require(SelectedChecksModel.validationScenarios().first { $0.name == name })
        let rendered = try scenario.render()
        let graphChecks = rendered.checkNames.intersection(
            rendered.invariantNames.union(rendered.reachabilityNames))
        let graphBundle = try rendered.tlaBundle(checking: graphChecks,
            checkDeadlock: rendered.checksDeadlock)
        let selected = Set(try ScenarioCheckCoverage(scenario).selectedProperties)
        let allVerdicts = ["InitiallyZero": "violated", "Reached": "reached",
            "Safe": "satisfied", "StaysZero": "violated"]
        let verdicts = omitSelectedVerdicts ? [:] : allVerdicts.filter { selected.contains($0.key) }
        var nativeReport: [String: Any] = [
            "schema": "swifttla.native-validation-report", "scenario": name, "maximumStates": 100,
            "graphComplete": graphComplete, "initialStates": 1, "states": 2,
            "edges": edgeCount, "properties": verdicts,
            "deadlockSelected": scenario.checking.checkDeadlock
        ]
        var oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": name, "maximumStates": 100, "graphComplete": graphComplete,
            "graphInputSHA256": String(repeating: "0", count: 64),
            "properties": verdicts, "deadlockSelected": scenario.checking.checkDeadlock
        ]
        if scenario.checking.checkDeadlock {
            nativeReport["deadlock"] = "violated"
            oracleReport["deadlock"] = "violated"
        }
        try JSONSerialization.data(withJSONObject: nativeReport).write(to: native.appendingPathComponent("report.json"))
        try JSONSerialization.data(withJSONObject: oracleReport).write(
            to: root.appendingPathComponent("oracle/oracle.json"))
        try JSONSerialization.data(withJSONObject: [
            "caseID": "fixture",
            "invocation": ["exitStatus": tlcExitStatus],
            "inputs": inputHashes(for: graphBundle), "configuration": graphBundle.cfg
        ])
            .write(to: tlc.appendingPathComponent("tlc-process.json"))
        if !graphComplete {
            try FileManager.default.createDirectory(at: tlc.appendingPathComponent("logs"),
                withIntermediateDirectories: false)
            try Data("Error: Invariant InitiallyZero is violated.\n".utf8)
                .write(to: tlc.appendingPathComponent("logs/tlc.stdout.log"))
            try Data(#"{"vars":["value","pc"],"counterexample":{"state":[[1,{"value":0,"pc":"advance"}],[2,{"value":1,"pc":"advance"}]],"action":[[[1,{"value":0,"pc":"advance"}],{"name":"advance"},[2,{"value":1,"pc":"advance"}]]]}}"#.utf8)
                .write(to: tlc.appendingPathComponent("counterexample.json"))
        }
        var writer = try BinaryGraphEvidenceWriter(to: native.appendingPathComponent("machine.bin"),
            caseID: "fixture")
        try writer.action(id: 0, name: nativeAction)
        try writer.state(id: 0, key: key(0), initial: nativeInitial == 0)
        try writer.state(id: 1, key: key(nativeTarget), initial: nativeInitial == 1)
        for _ in 0..<edgeCount {
            try writer.edge(source: 0, action: 0, target: nativeEdgeTarget)
        }
        if !graphComplete {
            try writer.invariantFailure(property: "InitiallyZero", key: key(1), predecessor: 0, action: 0)
        }
        try writer.finish(completion: graphComplete ? 0 : 1)
        try tlcGraph(edgeCount: edgeCount).write(to: tlc.appendingPathComponent("graph-events.bin"))
        return root
    }

    private func inputHashes(for bundle: TLAModuleBundle) -> [[String: String]] {
        bundle.files.map { file in
            ["file": "\(file.name).tla", "sha256": SHA256.hex(Data(file.tla.utf8))]
        } + [["file": "\(bundle.root.name).cfg",
              "sha256": SHA256.hex(Data(bundle.cfg.utf8))]]
    }

    private func key(_ value: Int) throws -> Data {
        let token = try #require(TLAStateProjection.Token(validating: "x"))
        return try CanonicalBinaryState.encode(TLAStateProjection(validating: [
            .init(token: token, value: .int(value))
        ]))
    }

    private func tlcGraph(edgeCount: Int, source: UInt64 = 101, target: UInt64 = 202) -> Data {
        var body = Data("STLAGRF2".utf8)
        body.append(1)
        append("fixture", to: &body)
        append("00000000-0000-4000-8000-000000000001", to: &body)
        for (fingerprint, value, initial) in [(source, 0, true), (target, 1, false)] {
            body.append(2)
            append(fingerprint, to: &body)
            body.append(initial ? 1 : 0)
            let key = tlcKey(value)
            append(UInt32(key.count), to: &body)
            body.append(key)
        }
        body.append(1)
        append(UInt32(0), to: &body)
        append("Next", to: &body)
        append("", to: &body)
        for _ in 0..<edgeCount {
            body.append(3)
            append(source, to: &body)
            append(UInt32(0), to: &body)
            append(target, to: &body)
        }
        let digest = Data(CryptoKit.SHA256.hash(data: body))
        body.append(255)
        for count in [2, 1, edgeCount, 0, 0, 0, 0, 0] { append(UInt64(count), to: &body) }
        body.append(0)
        body.append(digest)
        return body
    }

    private func tlcKey(_ value: Int) -> Data {
        var key = Data("STLASV01".utf8)
        append(UInt32(1), to: &key)
        append("x", to: &key)
        key.append(1)
        append(UInt32(8), to: &key)
        append(UInt64(bitPattern: Int64(value)), to: &key)
        return key
    }

    private func append(_ value: String, to bytes: inout Data) {
        append(UInt32(value.utf8.count), to: &bytes)
        bytes.append(contentsOf: value.utf8)
    }

    private func append(_ value: UInt32, to bytes: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    private func append(_ value: UInt64, to bytes: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
