import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("TLC input safety")
struct TLCInputSafetyTests {
    @Test("non-ASCII formal inputs cannot start TLC or identify reusable evidence")
    func rejectsNonASCIIInputsBeforeLaunchAndCacheLookup() throws {
        let root = TLAModuleFile(name: "Unicode", tla: "---- MODULE Unicode ----\n====",
            cfg: "SPECIFICATION Spec")
        let samples: [(bundle: TLAModuleBundle, file: String)] = [
            (.external(root: .init(name: "Unicode", tla: "---- MODULE Unicode ----\nInit == x = \"é\"\n====",
                cfg: root.cfg)), "Unicode.tla"),
            (.external(root: .init(name: "Unicode", tla: root.tla,
                cfg: "CONSTANT Name = \"é\"")), "Unicode.cfg"),
            (.external(root: .init(name: "Unicode", tla: "---- MODULE Unicode ----\nEXTENDS Helper\n====",
                cfg: root.cfg), imports: [.init(name: "Helper", tla: "---- MODULE Helper ----\nX == \"é\"\n====")],
                dependencies: [.init(importingModule: "Unicode", importedModule: "Helper",
                    structuralPath: ["test", "helper"])]), "Helper.tla")
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try testReferencePin()
        for (index, sample) in samples.enumerated() {
            let request = TLCProcessRequest(
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                jar: directory.appendingPathComponent("tla2tools.jar"),
                bridgeJar: directory.appendingPathComponent("bridge.jar"),
                bundle: sample.bundle,
                graphEvents: directory.appendingPathComponent("events-\(index).jsonl"),
                traceOutput: directory.appendingPathComponent("trace-\(index).json"),
                workingDirectory: directory,
                finiteGraphCase: try fixtureCase(pin), runID: UUID(), invocation: .finiteGraph)
            #expect(throws: TLCProcessError.self, "\(sample.file) must be rejected before staging") {
                _ = try request.stageDeclaredBundle()
            }
            #expect(throws: TLCProcessError.self, "\(sample.file) must not key a cached oracle") {
                _ = try GeneratedTLCOracle.inputIdentity(bundle: sample.bundle, pin: pin,
                    arguments: ["-workers", "1"])
            }
        }
    }
}
