import Foundation
import Testing
@testable import UpstreamParity

@Suite("Selected initial failure evidence")
struct InitialFailureEvidenceTests {
    @Test("A failure-only initializer retains native and actual TLA output for a proof without a graph")
    func preparesSelectedFailureProof() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifttla-initial-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sha = String(repeating: "a", count: 40)
        let report = try InitialFailureEvidence.prepare(sourceSHA: sha, to: directory)
        #expect(report.schema == "swifttla.initial-failure-proof-v2")
        #expect(report.result == "prepared")
        #expect(report.sourceSHA == sha)
        #expect(!report.graphCompared)
        #expect(report.site == 3)
        #expect(report.kind == "integerOverflow.addition")
        #expect(report.operands == [3, Int.max])

        let native = try Data(contentsOf: directory.appendingPathComponent("native-initial-failure.json"))
        let generated = directory.appendingPathComponent("generated-tla")
        let module = try Data(contentsOf: generated.appendingPathComponent("\(report.module).tla"))
        let checkModule = try Data(contentsOf: generated.appendingPathComponent("\(report.checkModule).tla"))
        let checkConfiguration = try Data(contentsOf: generated.appendingPathComponent("\(report.checkModule).cfg"))
        let proof = try Data(contentsOf: generated.appendingPathComponent("SwiftTLAInitialFailureProof.tla"))
        #expect(report.nativeSHA256 == SHA256.hex(native))
        #expect(report.moduleSHA256 == SHA256.hex(module))
        #expect(report.checkModuleSHA256 == SHA256.hex(checkModule))
        #expect(report.checkConfigurationSHA256 == SHA256.hex(checkConfiguration))
        #expect(report.proofSHA256 == SHA256.hex(proof))
        #expect(try JSONDecoder().decode(InitialFailureEvidenceReport.self,
            from: Data(contentsOf: directory.appendingPathComponent("preparation.json"))).result == "prepared")
        let proofText = try String(contentsOf: generated.appendingPathComponent("SwiftTLAInitialFailureProof.tla"),
            encoding: .utf8)
        #expect(proofText.contains("InitialFailurePrecedesGraph"))
        #expect(proofText.contains("1073741824"))
    }

    @Test("Invalid source provenance is refused before output")
    func rejectsInvalidRevision() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifttla-invalid-revision-\(UUID().uuidString)")
        #expect(throws: InitialFailureEvidenceError.invalidSourceSHA) {
            try InitialFailureEvidence.prepare(sourceSHA: "not-a-revision", to: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
