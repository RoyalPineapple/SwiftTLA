import CryptoKit
import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct ValidationEvidenceComparisonTests {
    private let actions = [RenderedAction(sourceName: "Next", arguments: [], renderedName: "Next")]

    @Test("binary producers compare the complete labeled graph")
    func completeGraphMatches() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try compare(root)
        #expect(result.result == "exact")
        #expect(result.graphCompared)
        #expect(result.difference == nil)
    }

    @Test("a changed state fails despite matching counts")
    func differentStateFails() throws {
        let root = try fixture(nativeTarget: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try compare(root).difference == "complete state set")
    }

    @Test("a changed edge fails despite matching counts")
    func differentEdgeFails() throws {
        let root = try fixture(nativeEdgeTarget: 0)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try compare(root).difference == "complete labeled edge set")
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
        try ValidationEvidenceComparison.compare(caseID: "fixture",
            native: root.appendingPathComponent("native"),
            oracle: root.appendingPathComponent("oracle"), actions: actions,
            to: root.appendingPathComponent("comparison"))
    }

    private func fixture(nativeTarget: Int = 1, nativeEdgeTarget: UInt64 = 1,
        nativeInitial: UInt64 = 0,
        edgeCount: Int = 1) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let native = root.appendingPathComponent("native")
        let tlc = root.appendingPathComponent("oracle/tlc-graph")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tlc, withIntermediateDirectories: true)
        let nativeReport: [String: Any] = [
            "schema": "swifttla.native-validation-report", "scenario": "fixture",
            "graphComplete": true, "initialStates": 1, "states": 2,
            "edges": edgeCount, "properties": [:], "deadlockSelected": false
        ]
        let oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": "fixture", "graphComplete": true,
            "graphInputSHA256": String(repeating: "0", count: 64),
            "properties": [:], "deadlockSelected": false
        ]
        try JSONSerialization.data(withJSONObject: nativeReport).write(to: native.appendingPathComponent("report.json"))
        try JSONSerialization.data(withJSONObject: oracleReport).write(
            to: root.appendingPathComponent("oracle/oracle.json"))
        try JSONSerialization.data(withJSONObject: ["invocation": ["exitStatus": 0]])
            .write(to: tlc.appendingPathComponent("tlc-process.json"))
        var writer = try BinaryGraphEvidenceWriter(to: native.appendingPathComponent("machine.bin"),
            caseID: "fixture")
        try writer.action(id: 0, name: "Next")
        try writer.state(id: 0, key: key(0), initial: nativeInitial == 0)
        try writer.state(id: 1, key: key(nativeTarget), initial: nativeInitial == 1)
        for _ in 0..<edgeCount {
            try writer.edge(source: 0, action: 0, target: nativeEdgeTarget)
        }
        try writer.finish(completion: 0)
        try tlcGraph(edgeCount: edgeCount).write(to: tlc.appendingPathComponent("graph-events.bin"))
        return root
    }

    private func key(_ value: Int) -> String {
        CanonicalState(bindings: ["x": .integer(value)]).key.canonicalEncoding
    }

    private func tlcGraph(edgeCount: Int, source: UInt64 = 101, target: UInt64 = 202) -> Data {
        var body = Data("STLAGRF1".utf8)
        body.append(1)
        append("fixture", to: &body)
        append("00000000-0000-4000-8000-000000000001", to: &body)
        for (fingerprint, value, initial) in [(source, "0", true), (target, "1", false)] {
            body.append(2)
            append(fingerprint, to: &body)
            body.append(initial ? 1 : 0)
            append(UInt32(1), to: &body)
            append("x", to: &body)
            append(value, to: &body)
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
