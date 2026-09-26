import CryptoKit
import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct ValidationEvidenceComparisonTests {
    @Test("complete generated-machine and TLC records match by full state and labeled edge")
    func completeGraphMatches() throws {
        let directory = try fixture(target: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try ValidationEvidenceComparison.compare(
            caseID: "fixture", native: directory.appendingPathComponent("native"),
            oracle: directory.appendingPathComponent("oracle"),
            actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")],
            to: directory.appendingPathComponent("comparison"))
        #expect(result.result == "exact")
        #expect(result.graphCompared)
        #expect(result.difference == nil)
    }

    @Test("a different complete state cannot pass through matching counts")
    func differentStateFails() throws {
        let directory = try fixture(target: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try ValidationEvidenceComparison.compare(
            caseID: "fixture", native: directory.appendingPathComponent("native"),
            oracle: directory.appendingPathComponent("oracle"),
            actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")],
            to: directory.appendingPathComponent("comparison"))
        #expect(result.result == "different")
        #expect(result.difference == "complete state set")
    }

    @Test("constraint exclusions and stuttering observations do not become reachable edges")
    func ignoresNonGraphObservations() throws {
        let reference = try fixtureCase(testReferencePin(),
            renderedActions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")])
        for stream in [
            try completeGraphStreamWithExcludedPredicateObservation(reference),
            try completeGraphStreamWithStutteringObservation(reference)
        ] {
            let directory = try fixture(target: 1)
            defer { try? FileManager.default.removeItem(at: directory) }
            try stream.write(to: directory.appendingPathComponent("oracle/tlc-graph/graph-events.jsonl"))
            let result = try ValidationEvidenceComparison.compare(
                caseID: "fixture", native: directory.appendingPathComponent("native"),
                oracle: directory.appendingPathComponent("oracle"),
                actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")],
                to: directory.appendingPathComponent("comparison"))
            #expect(result.result == "exact")
        }
    }

    @Test("two independently captured TLC graphs compare by state rather than fingerprint")
    func comparesTLCGraphs() throws {
        let reference = try fixtureCase(testReferencePin(),
            renderedActions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try completeGraphStream(reference)
        let generated = directory.appendingPathComponent("generated.jsonl")
        let upstream = directory.appendingPathComponent("upstream.jsonl")
        try source.write(to: generated)
        try source.write(to: upstream)
        #expect(try ValidationEvidenceComparison.compareTLCGraphs(
            caseID: "fixture", generated: generated, reference: upstream,
            actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")],
            in: directory) == nil)
    }

    @Test("matching decisive verdicts do not require a complete TLC graph")
    func decisiveResultDoesNotRequireGraph() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let native = root.appendingPathComponent("native")
        let oracle = root.appendingPathComponent("oracle")
        let tlc = oracle.appendingPathComponent("tlc-graph")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tlc, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nativeReport: [String: Any] = [
            "schema": "swifttla.native-validation-report", "scenario": "fixture",
            "graphComplete": false, "initialStates": 0, "states": 0, "edges": 0,
            "properties": ["Broken": "violated"]
        ]
        let oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": "fixture", "graphComplete": false,
            "graphInputSHA256": String(repeating: "0", count: 64),
            "properties": ["Broken": "violated"]
        ]
        try JSONSerialization.data(withJSONObject: nativeReport).write(to: native.appendingPathComponent("report.json"))
        try JSONSerialization.data(withJSONObject: oracleReport).write(to: oracle.appendingPathComponent("oracle.json"))
        try JSONSerialization.data(withJSONObject: ["invocation": ["exitStatus": 12]]).write(
            to: tlc.appendingPathComponent("tlc-process.json"))
        let key = CanonicalState(bindings: ["x": .integer(0)]).key.canonicalEncoding
        let records: [[String: Any]] = [
            ["type": "header", "schema": "swifttla.native-validation", "version": 1],
            ["type": "invariant-failure", "property": "Broken", "key": key]
        ]
        let body = try records.reduce(into: Data()) { data, record in
            data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            data.append(10)
        }
        let footer: [String: Any] = [
            "type": "complete", "completion": "decisive-violation", "states": 0,
            "initialStates": 0, "edges": 0, "bodySha256": SHA256.hex(body)
        ]
        let events = body + (try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])) + Data([10])
        try events.write(to: native.appendingPathComponent("machine.jsonl"))
        let result = try ValidationEvidenceComparison.compare(
            caseID: "fixture", native: native, oracle: oracle, actions: [],
            to: root.appendingPathComponent("comparison"))
        #expect(result.result == "exact")
        #expect(!result.graphCompared)
    }

    private func fixture(target: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let native = root.appendingPathComponent("native")
        let oracle = root.appendingPathComponent("oracle")
        let tlc = oracle.appendingPathComponent("tlc-graph")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tlc, withIntermediateDirectories: true)
        let nativeReport: [String: Any] = [
            "schema": "swifttla.native-validation-report", "scenario": "fixture",
            "graphComplete": true, "initialStates": 1, "states": 2, "edges": 1,
            "properties": [:]
        ]
        let oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": "fixture", "graphComplete": true,
            "graphInputSHA256": String(repeating: "0", count: 64), "properties": [:]
        ]
        try JSONSerialization.data(withJSONObject: nativeReport).write(
            to: native.appendingPathComponent("report.json"))
        try JSONSerialization.data(withJSONObject: oracleReport).write(
            to: oracle.appendingPathComponent("oracle.json"))
        try JSONSerialization.data(withJSONObject: ["invocation": ["exitStatus": 0]]).write(
            to: tlc.appendingPathComponent("tlc-process.json"))
        let key0 = CanonicalState(bindings: ["x": .integer(0)]).key.canonicalEncoding
        let key1 = CanonicalState(bindings: ["x": .integer(target)]).key.canonicalEncoding
        let records: [[String: Any]] = [
            ["type": "header", "schema": "swifttla.native-validation", "version": 1],
            ["type": "state", "id": 0, "key": key0, "initial": true],
            ["type": "state", "id": 1, "key": key1, "initial": false],
            ["type": "edge", "source": 0, "target": 1, "action": "Next"]
        ]
        let body = try records.reduce(into: Data()) { data, record in
            data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            data.append(10)
        }
        let footer: [String: Any] = [
            "type": "complete", "completion": "exhausted", "states": 2,
            "initialStates": 1, "edges": 1, "bodySha256": SHA256.hex(body)
        ]
        let nativeEvents = body + (try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])) + Data([10])
        try nativeEvents.write(to: native.appendingPathComponent("machine.jsonl"))
        let reference = try fixtureCase(testReferencePin(),
            renderedActions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")])
        try completeGraphStream(reference).write(to: tlc.appendingPathComponent("graph-events.jsonl"))
        return root
    }
}
