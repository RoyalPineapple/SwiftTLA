import CryptoKit
import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct ValidationEvidenceComparisonTests {
    @Test("independent graph spooling retains every state and labeled edge")
    func completeGraphSpoolsAreReusable() throws {
        let directory = try fixture(target: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nativeSpool = directory.appendingPathComponent("native-spool")
        let tlcSpool = directory.appendingPathComponent("tlc-spool")
        try FileManager.default.createDirectory(at: nativeSpool, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: tlcSpool, withIntermediateDirectories: false)
        let actions = [RenderedAction(sourceName: "Next", arguments: [], renderedName: "Next")]
        try ValidationEvidenceComparison.writeNativeSpool(
            directory.appendingPathComponent("native/machine.jsonl"),
            expectedComplete: true, actions: actions, in: nativeSpool)
        try ValidationEvidenceComparison.writeTLCSpool(
            directory.appendingPathComponent("oracle/tlc-graph/graph-events.jsonl.gz"),
            caseID: "fixture", actions: actions, in: tlcSpool)
        for spool in [nativeSpool, tlcSpool] {
            let manifest = try JSONSerialization.jsonObject(with:
                Data(contentsOf: spool.appendingPathComponent("spool.json"))) as? [String: Any]
            #expect(manifest?["stateCount"] as? Int == 2)
            #expect(try Data(contentsOf: spool.appendingPathComponent("states.raw"))
                .split(separator: 10).count == 2)
            #expect(try Data(contentsOf: spool.appendingPathComponent("edges.raw"))
                .split(separator: 10).count == 1)
        }
    }

    @Test("compact TLC evidence reads every event across memory-release batches")
    func compactGraphSpoolsAcrossBatches() throws {
        let directory = try fixture(target: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = try fixtureCase(testReferencePin(),
            renderedActions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")])
        let source = try completeGraphStream(reference)
        var records = try source.split(separator: 10).map { line -> [String: Any] in
            guard let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("fixture graph event")
            }
            return record
        }
        let repeated = 1_100
        for offset in 0..<repeated {
            var transition = records[2]
            transition["seq"] = offset + 3
            transition["stateFlags"] = ["raw": 1, "seen": true, "notInModel": false]
            records.insert(transition, at: records.count - 1)
        }
        records[records.count - 1]["seq"] = repeated + 3
        records[records.count - 1]["lastBodySeq"] = repeated + 2
        records[records.count - 1]["counts"] = ["header": 1, "initial": 1,
            "transition": repeated + 1]
        let expanded = try records.reduce(into: Data()) { data, record in
            data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            data.append(10)
        }
        let graph = directory.appendingPathComponent("oracle/tlc-graph/graph-events.jsonl.gz")
        try writeCompressedGraph(expanded, to: graph)
        let spool = directory.appendingPathComponent("tlc-spool")
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: false)
        try ValidationEvidenceComparison.writeTLCSpool(graph, caseID: "fixture",
            actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")], in: spool)
        #expect(try Data(contentsOf: spool.appendingPathComponent("states.raw"))
            .split(separator: 10).count == 2)
        #expect(try Data(contentsOf: spool.appendingPathComponent("edges.raw"))
            .split(separator: 10).count == repeated + 1)
    }

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
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("comparison/swift").path))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("comparison/tlc").path))
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
            try writeCompressedGraph(stream,
                to: directory.appendingPathComponent("oracle/tlc-graph/graph-events.jsonl.gz"))
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
        let generated = directory.appendingPathComponent("generated.jsonl.gz")
        let upstream = directory.appendingPathComponent("upstream.jsonl.gz")
        try writeCompressedGraph(source, to: generated)
        try writeCompressedGraph(source, to: upstream)
        #expect(try ValidationEvidenceComparison.compareTLCGraphs(
            caseID: "fixture", generated: generated, reference: upstream,
            actions: [.init(sourceName: "Next", arguments: [], renderedName: "Next")],
            in: directory) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("generated-graph-spool").path))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("reference-graph-spool").path))
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
            "properties": ["Broken": "violated"], "deadlockSelected": true
        ]
        let oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": "fixture", "graphComplete": false,
            "graphInputSHA256": String(repeating: "0", count: 64),
            "properties": ["Broken": "violated"], "deadlockSelected": true
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
        #expect(result.deadlockSelected)
        #expect(result.deadlock == nil)
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
            "properties": [:], "deadlockSelected": false
        ]
        let oracleReport: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture",
            "scenario": "fixture", "graphComplete": true,
            "graphInputSHA256": String(repeating: "0", count: 64), "properties": [:],
            "deadlockSelected": false
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
        try writeCompressedGraph(completeGraphStream(reference),
            to: tlc.appendingPathComponent("graph-events.jsonl.gz"))
        return root
    }

    private func writeCompressedGraph(_ stream: Data, to destination: URL) throws {
        var records = try stream.split(separator: 10).map { line -> [String: Any] in
            guard let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("fixture graph event")
            }
            return record
        }
        for index in records.indices {
            records[index]["version"] = 4
            guard records[index]["type"] as? String == "transition",
                  let source = records[index]["source"] as? [String: Any],
                  let target = records[index]["target"] as? [String: Any],
                  let flags = records[index]["stateFlags"] as? [String: Any] else { continue }
            records[index]["source"] = ["fingerprint": source["fingerprint"]!, "level": source["level"]!]
            if flags["seen"] as? Bool == true || flags["notInModel"] as? Bool == true {
                records[index]["target"] = ["fingerprint": target["fingerprint"]!, "level": target["level"]!]
            }
            if flags["notInModel"] as? Bool == true { records[index]["resolvedActions"] = [] }
        }
        let body = try records.dropLast().reduce(into: Data()) { data, record in
            data.append(try bridgeLine(record))
            data.append(10)
        }
        records[records.count - 1]["bodySha256"] = SHA256.hex(body)
        let footer = try bridgeLine(records[records.count - 1])
        try compress(body + footer + Data([10]), to: destination)
    }

    private func bridgeLine(_ record: [String: Any]) throws -> Data {
        func field(_ key: String) throws -> String {
            guard let value = record[key] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture \(key)")
            }
            return try fragment(value)
        }
        let type = try field("type")
        let base = "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":4,\"type\":\(type),\"callback\":\(try field("callback")),\"seq\":\(try field("seq")),\"runId\":\(try field("runId")),\"caseId\":\(try field("caseId"))"
        let suffix: String
        switch record["type"] as? String {
        case "header":
            suffix = ""
        case "initial":
            suffix = ",\"state\":\(try bridgeState(record["state"]))"
        case "transition":
            guard let resolved = record["resolvedActions"] as? [[String: Any]],
                  let flags = record["stateFlags"] as? [String: Any] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture transition")
            }
            let actions = try resolved.map { try bridgeAction($0) }.joined(separator: ",")
            suffix = ",\"source\":\(try bridgeState(record["source"])),\"target\":\(try bridgeState(record["target"])),\"action\":\(try bridgeAction(record["action"])),\"resolvedActions\":[\(actions)],\"stateFlags\":{\"raw\":\(try fragment(flags["raw"])),\"seen\":\(try fragment(flags["seen"])),\"notInModel\":\(try fragment(flags["notInModel"]))},\"visualization\":\(try field("visualization")),\"predicateLocation\":\(try field("predicateLocation")),\"reachable\":\(try field("reachable"))"
        case "unsupported":
            suffix = ",\"reason\":\(try field("reason"))"
        case "footer":
            suffix = ",\"status\":\(try field("status")),\"counts\":\(try field("counts")),\"lastBodySeq\":\(try field("lastBodySeq")),\"bodySha256\":\(try field("bodySha256"))"
        default:
            throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture type")
        }
        return Data("\(base)\(suffix)}".utf8)
    }

    private func bridgeState(_ value: Any?) throws -> String {
        guard let state = value as? [String: Any] else {
            throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture state")
        }
        let base = "{\"fingerprint\":\(try fragment(state["fingerprint"])),\"level\":\(try fragment(state["level"]))"
        guard let bindings = state["bindings"] as? [[String: Any]] else { return base + "}" }
        let fields = try bindings.map { binding in
            "{\"ordinal\":\(try fragment(binding["ordinal"])),\"name\":\(try fragment(binding["name"])),\"tla\":\(try fragment(binding["tla"]))}"
        }.joined(separator: ",")
        return "\(base),\"bindings\":[\(fields)]}"
    }

    private func bridgeAction(_ value: Any?) throws -> String {
        guard let action = value as? [String: Any] else {
            throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture action")
        }
        return "{\"name\":\(try fragment(action["name"])),\"location\":\(try fragment(action["location"])),\"named\":\(try fragment(action["named"]))}"
    }

    private func fragment(_ value: Any?) throws -> String {
        guard let value else { throw ValidationEvidenceComparisonError.invalidEvidence("bridge fixture field") }
        return String(decoding: try JSONSerialization.data(withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
    }

    private func compress(_ data: Data, to destination: URL) throws {
        let source = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-n", "-c", source.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let compressed = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("fixture compression")
        }
        try compressed.write(to: destination)
    }
}
