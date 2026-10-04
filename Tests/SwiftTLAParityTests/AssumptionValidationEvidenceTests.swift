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
            verdict: .satisfied, evaluatedValues: [], moduleSHA256: "module", cfgSHA256: "config")
        let oracleReport = TLCAssumptionReport(
            schema: "swifttla.tlc-assumption", caseID: "case", scenario: "configured",
            verdict: .satisfied, evaluatedValues: [], moduleSHA256: "module", cfgSHA256: "config",
            inputIdentity: "pinned-tool-input")
        try JSONEncoder().encode(nativeReport).write(to: native.appendingPathComponent("report.json"))
        try JSONEncoder().encode(oracleReport).write(to: oracle.appendingPathComponent("oracle.json"))
        let captureArguments = ["-Dswifttla.tlc.evaluation.path=/working/evaluations.bin",
                                "org.swifttla.conformance.TLCEvaluationOutput"]
        let receipt: [String: Any] = [
            "caseID": "case", "invocation": [
                "exitStatus": 0, "arguments": captureArguments
            ],
            "inputs": [["file": "configured.tla", "sha256": "module"],
                       ["file": "configured.cfg", "sha256": "config"]]
        ]
        let process = oracle.appendingPathComponent("tlc/tlc-process.json")
        try JSONSerialization.data(withJSONObject: receipt).write(to: process)
        let evaluations = oracle.appendingPathComponent("tlc/tlc-evaluation.bin")
        try Data(Array("STLAOUT1".utf8) + [1, 2, 0, 0, 0, 0, 0, 0, 0, 0]).write(to: evaluations)
        let equal = try AssumptionValidationEvidence.compareNative(
            id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("equal"))
        #expect(equal.result == "exact")
        #expect(equal.assumptionCompared)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("equal/machine.bin.gz").path))

        let mismatched = TLCAssumptionReport(
            schema: oracleReport.schema, caseID: oracleReport.caseID, scenario: oracleReport.scenario,
            verdict: .violated, evaluatedValues: [], moduleSHA256: oracleReport.moduleSHA256,
            cfgSHA256: oracleReport.cfgSHA256, inputIdentity: oracleReport.inputIdentity)
        try JSONEncoder().encode(mismatched).write(to: oracle.appendingPathComponent("oracle.json"))
        let changedReceipt: [String: Any] = [
            "caseID": "case", "invocation": [
                "exitStatus": 10, "arguments": captureArguments
            ], "inputs": receipt["inputs"]!
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

        try JSONSerialization.data(withJSONObject: changedReceipt).write(to: process)
        let changedValues = TLCAssumptionReport(
            schema: oracleReport.schema, caseID: oracleReport.caseID, scenario: oracleReport.scenario,
            verdict: .violated, evaluatedValues: ["tuple:[integer:1]"],
            moduleSHA256: oracleReport.moduleSHA256, cfgSHA256: oracleReport.cfgSHA256,
            inputIdentity: oracleReport.inputIdentity)
        try JSONEncoder().encode(changedValues).write(to: oracle.appendingPathComponent("oracle.json"))
        #expect(throws: AssumptionValidationError.invalidEvidence("TLC evaluated values")) {
            try AssumptionValidationEvidence.compareNative(
                id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("stale"))
        }

        let printed = Array("<<1>>".utf8)
        try Data(Array("STLAOUT1".utf8) + [1, 1, 0, 0, 0, UInt8(printed.count)]
            + printed + [2, 0, 0, 0, 0, 0, 0, 0, 1]).write(to: evaluations)
        let matchingVerdict = TLCAssumptionReport(
            schema: oracleReport.schema, caseID: oracleReport.caseID, scenario: oracleReport.scenario,
            verdict: .satisfied, evaluatedValues: changedValues.evaluatedValues,
            moduleSHA256: oracleReport.moduleSHA256, cfgSHA256: oracleReport.cfgSHA256,
            inputIdentity: oracleReport.inputIdentity)
        try JSONEncoder().encode(matchingVerdict).write(to: oracle.appendingPathComponent("oracle.json"))
        try JSONSerialization.data(withJSONObject: receipt).write(to: process)
        let valueMismatch = try AssumptionValidationEvidence.compareNative(
            id: "case", native: native, oracle: oracle, to: root.appendingPathComponent("value-mismatch"))
        #expect(valueMismatch.result == "different")
        #expect(valueMismatch.difference == "evaluated values")
    }
}
