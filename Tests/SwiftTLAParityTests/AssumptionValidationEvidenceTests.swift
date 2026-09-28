import Foundation
import Testing
@testable import UpstreamParity

struct AssumptionValidationEvidenceTests {
    @Test("a state-free verdict matches only with a matching TLC receipt")
    func comparesCompleteAssumptionVerdicts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let native = root.appendingPathComponent("native")
        let oracle = root.appendingPathComponent("oracle")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oracle.appendingPathComponent("tlc"), withIntermediateDirectories: true)
        let nativeReport = NativeAssumptionReport(
            schema: "swifttla.native-assumption", caseID: "case", scenario: "configured",
            verdict: .satisfied, moduleSHA256: "module", cfgSHA256: "config")
        let oracleReport = TLCAssumptionReport(
            schema: "swifttla.tlc-assumption", caseID: "case", scenario: "configured",
            verdict: .satisfied, moduleSHA256: "module", cfgSHA256: "config",
            inputIdentity: "pinned-tool-input")
        try JSONEncoder().encode(nativeReport).write(to: native.appendingPathComponent("report.json"))
        try JSONEncoder().encode(oracleReport).write(to: oracle.appendingPathComponent("oracle.json"))
        let receipt: [String: Any] = [
            "caseID": "case", "invocation": ["exitStatus": 0],
            "inputs": [["file": "configured.tla", "sha256": "module"],
                       ["file": "configured.cfg", "sha256": "config"]]
        ]
        let process = oracle.appendingPathComponent("tlc/tlc-process.json")
        try JSONSerialization.data(withJSONObject: receipt).write(to: process)
        let equal = try AssumptionValidationEvidence.compareNative(
            id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("equal"))
        #expect(equal.result == "exact")
        #expect(equal.assumptionCompared)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("equal/machine.bin").path))

        let mismatched = TLCAssumptionReport(
            schema: oracleReport.schema, caseID: oracleReport.caseID, scenario: oracleReport.scenario,
            verdict: .violated, moduleSHA256: oracleReport.moduleSHA256,
            cfgSHA256: oracleReport.cfgSHA256, inputIdentity: oracleReport.inputIdentity)
        try JSONEncoder().encode(mismatched).write(to: oracle.appendingPathComponent("oracle.json"))
        let changedReceipt: [String: Any] = [
            "caseID": "case", "invocation": ["exitStatus": 10], "inputs": receipt["inputs"]!
        ]
        try JSONSerialization.data(withJSONObject: changedReceipt).write(to: process)
        let different = try AssumptionValidationEvidence.compareNative(
            id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("different"))
        #expect(different.result == "different")
        #expect(different.difference == "assumption verdict")

        try JSONSerialization.data(withJSONObject: receipt).write(to: process)
        #expect(throws: AssumptionValidationError.invalidEvidence("TLC process receipt")) {
            try AssumptionValidationEvidence.compareNative(
                id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("invalid"))
        }
    }
}
