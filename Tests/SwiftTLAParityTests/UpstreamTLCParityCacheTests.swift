import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamTLCParityCacheTests {
    @Test("upstream parity reuses only a complete generated graph with matching inputs and tool pin")
    func reusesMatchingGeneratedOracle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oracle = root.appendingPathComponent("oracle")
        let graph = oracle.appendingPathComponent("tlc-graph")
        try FileManager.default.createDirectory(at: graph, withIntermediateDirectories: true)
        let bundle = TLAModuleBundle.external(root: .init(
            name: "Fixture", tla: "---- MODULE Fixture ----\nInit == TRUE\n====",
            cfg: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n"))
        let pin = try testReferencePin()
        let identity = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle, pin: pin, arguments: ["-workers", "1", "-fp", "1"])
        let report: [String: Any] = [
            "schema": "swifttla.generated-tlc-oracle", "caseID": "fixture", "scenario": "Fixture",
            "maximumStates": 100, "graphComplete": true, "graphInputSHA256": identity,
            "properties": [:], "deadlock": NSNull(), "deadlockSelected": false
        ]
        try JSONSerialization.data(withJSONObject: report)
            .write(to: oracle.appendingPathComponent("oracle.json"))
        let expectedPin: [String: Any] = [
            "tag": pin.tag, "commit": pin.commit,
            "jarSHA256": pin.jarSHA256, "javaDistribution": pin.javaDistribution,
            "javaVersion": pin.javaVersion, "javaArchiveSHA256": pin.javaArchiveSHA256,
            "bridgeClass": pin.bridgeClass, "bridgeSourceHashes": pin.bridgeSourceHashes,
            "bridgeBinarySHA256": pin.bridgeBinarySHA256
        ]
        let receipt: [String: Any] = [
            "caseID": "fixture", "configuration": bundle.cfg,
            "inputs": bundleInputJSON(bundle), "toolPin": expectedPin,
            "invocation": ["exitStatus": 0,
                           "arguments": ["-dump", "class,\(pin.bridgeClass)", "-workers", "1", "-fp", "1"]]
        ]
        let receiptURL = graph.appendingPathComponent("tlc-process.json")
        try JSONSerialization.data(withJSONObject: receipt).write(to: receiptURL)
        try Data([0x1f, 0x8b]).write(to: graph.appendingPathComponent("graph-events.bin.gz"))
        let origin: [String: String] = [
            "sourceSHA": String(repeating: "a", count: 40),
            "originRunID": "1", "cacheKey": String(repeating: "b", count: 64)
        ]
        try JSONSerialization.data(withJSONObject: origin)
            .write(to: oracle.appendingPathComponent("evidence-origin.json"))

        let output = root.appendingPathComponent("generated-graph")
        #expect(try UpstreamTLCParity.reuseGeneratedGraph(
            from: oracle, to: output, id: "fixture", bundle: bundle, pin: pin))
        #expect(try Data(contentsOf: output.appendingPathComponent("tlc-process.json"))
            == Data(contentsOf: receiptURL))
        let changed = TLAModuleBundle.external(root: .init(
            name: "Fixture", tla: "---- MODULE Fixture ----\nInit == FALSE\n====",
            cfg: bundle.cfg))
        let stale = root.appendingPathComponent("stale")
        #expect(try !UpstreamTLCParity.reuseGeneratedGraph(
            from: oracle, to: stale, id: "fixture", bundle: changed, pin: pin))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        var wrongPin = expectedPin
        wrongPin["jarSHA256"] = String(repeating: "0", count: 64)
        var wrongTool = receipt
        wrongTool["toolPin"] = wrongPin
        try JSONSerialization.data(withJSONObject: wrongTool).write(to: receiptURL)
        #expect(throws: UpstreamTLCParityError.invalidOutcome("cached generated oracle receipt: fixture")) {
            _ = try UpstreamTLCParity.reuseGeneratedGraph(
                from: oracle, to: root.appendingPathComponent("wrong-pin"),
                id: "fixture", bundle: bundle, pin: pin)
        }
        var incomplete = receipt
        incomplete["invocation"] = ["exitStatus": 12,
            "arguments": ["-dump", "class,\(pin.bridgeClass)", "-workers", "1", "-fp", "1"]]
        try JSONSerialization.data(withJSONObject: incomplete).write(to: receiptURL)
        #expect(throws: UpstreamTLCParityError.invalidOutcome("cached generated oracle receipt: fixture")) {
            _ = try UpstreamTLCParity.reuseGeneratedGraph(
                from: oracle, to: root.appendingPathComponent("incomplete"),
                id: "fixture", bundle: bundle, pin: pin)
        }
    }

    @Test("upstream evidence is bound to both module inputs and the exploration limit")
    func cacheKeyChangesWithReferenceOrLimit() throws {
        let scenario = try #require(modelValidationScenarios().first).scenario
        let rendered = try scenario.render()
        let pin = try testReferencePin()
        func reference(_ value: Int) -> TLAModuleBundle {
            .external(root: .init(name: "Reference", tla: "---- MODULE Reference ----\nX == \(value)\n====",
                                  cfg: "CHECK_DEADLOCK FALSE"))
        }
        func key(reference: TLAModuleBundle, limit: Int, cfgPin: String? = nil) throws -> String {
            try UpstreamTLCParity.cacheKey(id: "reference-case", rendered: rendered,
                reference: reference,
                expectedModuleSHA256: SHA256.hex(Data(reference.tla.utf8)),
                expectedCFGSHA256: cfgPin ?? SHA256.hex(Data(reference.cfg.utf8)),
                maximumStates: limit,
                decisive: false, pin: pin)
        }
        let baseline = try key(reference: reference(1), limit: 100)
        #expect(baseline == (try key(reference: reference(1), limit: 100)))
        #expect(baseline != (try key(reference: reference(2), limit: 100)))
        #expect(baseline != (try key(reference: reference(1), limit: 101)))
        #expect(throws: UpstreamTLCParityError.inputMismatch("reference-case")) {
            try key(reference: reference(1), limit: 100,
                cfgPin: SHA256.hex(Data("stale configuration".utf8)))
        }
    }
}
