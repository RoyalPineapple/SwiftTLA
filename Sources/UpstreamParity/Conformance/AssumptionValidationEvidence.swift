import Foundation
import SwiftTLA

package struct NativeAssumptionReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let scenario: String
    package let verdict: ValidationVerdict
    package let evaluatedValues: [String]
    package let moduleSHA256: String
    package let cfgSHA256: String
}

package struct TLCAssumptionReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let scenario: String
    package let verdict: ValidationVerdict
    package let evaluatedValues: [String]
    package let moduleSHA256: String
    package let cfgSHA256: String
    package let inputIdentity: String
}

package struct AssumptionComparisonReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let result: String
    package let assumptionCompared: Bool
    package let difference: String?
    package let leftVerdict: ValidationVerdict
    package let rightVerdict: ValidationVerdict
}

package enum AssumptionValidationError: Error, Equatable {
    case invalidScenario(String)
    case invalidReference(String)
    case invalidOutcome(String)
    case invalidEvidence(String)
}

/// A state-free check compares the assumption verdict and complete evaluated values.
package enum AssumptionValidationEvidence {
    package static func native(
        scenario: any AssumptionValidationScenario, id: String, to directory: URL
    ) throws -> NativeAssumptionReport {
        let rendered = try scenario.render()
        try requireAssumptionsOnly(rendered, id: id)
        let evaluation = try scenario.evaluateAssumptions()
        let report = NativeAssumptionReport(
            schema: "swifttla.native-assumption", caseID: id, scenario: scenario.name,
            verdict: evaluation.satisfied ? .satisfied : .violated,
            evaluatedValues: try evaluation.evaluatedValues.map { try CanonicalValue($0).canonicalEncoding },
            moduleSHA256: SHA256.hex(Data(rendered.tlaBundle.tla.utf8)),
            cfgSHA256: SHA256.hex(Data(rendered.tlaBundle.cfg.utf8)))
        try write(report, in: directory, name: "report.json")
        return report
    }

    package static func oracleCacheKey(
        scenario: any AssumptionValidationScenario, id: String, maximumStates: Int,
        pin: TLCReferencePin
    ) throws -> String {
        let rendered = try scenario.render()
        try requireAssumptionsOnly(rendered, id: id)
        let identity: [String: Any] = [
            "schema": "swifttla.assumption-oracle-cache-v2",
            "caseID": id, "scenario": scenario.name, "maximumStates": maximumStates,
            "input": try GeneratedTLCOracle.inputIdentity(bundle: rendered.tlaBundle, pin: pin,
                arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck,
                captureEvaluations: true)
        ]
        return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
    }

    package static func oracle(
        scenario: any AssumptionValidationScenario, id: String, maximumStates: Int,
        timeout: TimeInterval, tools: ResolvedTLCToolchain, pin: TLCReferencePin,
        to directory: URL, process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws -> TLCAssumptionReport {
        let rendered = try scenario.render()
        try requireAssumptionsOnly(rendered, id: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        try GeneratedTLCOracle.retainGeneratedInputs(rendered.tlaBundle,
            in: directory.appendingPathComponent("generated-input"))
        let retained = directory.appendingPathComponent("tlc")
        let outcome = try GeneratedTLCOracle.run(
            bundle: rendered.tlaBundle, id: id, maximumStates: maximumStates,
            timeout: timeout, tools: tools, pin: pin, workRoot: work,
            retained: retained, invocation: .propertyCheck, renderedActions: [], process: process,
            captureEvaluations: true)
        let evaluatedValues = try capturedValues(in: retained)
        let report = TLCAssumptionReport(
            schema: "swifttla.tlc-assumption", caseID: id, scenario: scenario.name,
            verdict: try verdict(outcome, id: id),
            evaluatedValues: evaluatedValues,
            moduleSHA256: SHA256.hex(Data(rendered.tlaBundle.tla.utf8)),
            cfgSHA256: SHA256.hex(Data(rendered.tlaBundle.cfg.utf8)),
            inputIdentity: try GeneratedTLCOracle.inputIdentity(bundle: rendered.tlaBundle,
                pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck,
                captureEvaluations: true))
        try write(report, in: directory, name: "oracle.json", create: false)
        return report
    }

    package static func compareNative(
        id: String, native: URL, oracle: URL, to directory: URL
    ) throws -> AssumptionComparisonReport {
        let left = try JSONDecoder().decode(NativeAssumptionReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let right = try JSONDecoder().decode(TLCAssumptionReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        guard left.schema == "swifttla.native-assumption", right.schema == "swifttla.tlc-assumption",
              left.caseID == id, right.caseID == id, left.scenario == right.scenario,
              left.moduleSHA256 == right.moduleSHA256, left.cfgSHA256 == right.cfgSHA256 else {
            throw AssumptionValidationError.invalidEvidence("assumption report identity")
        }
        try verifyProcess(oracle.appendingPathComponent("tlc/tlc-process.json"),
            id: id, verdict: right.verdict, moduleSHA256: right.moduleSHA256,
            cfgSHA256: right.cfgSHA256)
        guard right.evaluatedValues == (try capturedValues(in: oracle.appendingPathComponent("tlc"))) else {
            throw AssumptionValidationError.invalidEvidence("TLC evaluated values")
        }
        let difference: String? = if left.verdict != right.verdict {
            "assumption verdict"
        } else if left.evaluatedValues != right.evaluatedValues {
            "evaluated values"
        } else {
            nil
        }
        let report = AssumptionComparisonReport(
            schema: "swifttla.assumption-comparison", caseID: id,
            result: difference == nil ? "exact" : "different", assumptionCompared: true,
            difference: difference, leftVerdict: left.verdict, rightVerdict: right.verdict)
        try write(report, in: directory, name: "comparison.json")
        return report
    }

    package static func upstreamCacheKey(
        id: String, scenario: any AssumptionValidationScenario, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        expectedVerdict: ValidationExpectation, maximumStates: Int, pin: TLCReferencePin
    ) throws -> String {
        let rendered = try scenario.render()
        try requireAssumptionsOnly(rendered, id: id)
        try requireReference(reference, id: id, moduleSHA256: expectedModuleSHA256,
            cfgSHA256: expectedCFGSHA256)
        let identity: [String: Any] = [
            "schema": "swifttla.assumption-upstream-cache-v2", "caseID": id,
            "maximumStates": maximumStates, "expectedVerdict": expectedVerdict.rawValue,
            "generated": try GeneratedTLCOracle.inputIdentity(bundle: rendered.tlaBundle,
                pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck,
                captureEvaluations: true),
            "reference": try GeneratedTLCOracle.inputIdentity(bundle: reference,
                pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck,
                captureEvaluations: true)
        ]
        return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
    }

    package static func compareUpstream(
        id: String, scenario: any AssumptionValidationScenario, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        expectedVerdict: ValidationExpectation, maximumStates: Int, timeout: TimeInterval,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, to directory: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws -> AssumptionComparisonReport {
        let rendered = try scenario.render()
        try requireAssumptionsOnly(rendered, id: id)
        try requireReference(reference, id: id, moduleSHA256: expectedModuleSHA256,
            cfgSHA256: expectedCFGSHA256)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        try GeneratedTLCOracle.retainGeneratedInputs(rendered.tlaBundle,
            in: directory.appendingPathComponent("generated-input"))
        let parseWork = work.appendingPathComponent("parse")
        try FileManager.default.createDirectory(at: parseWork, withIntermediateDirectories: false)
        let launch = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
            moduleSHA256: expectedModuleSHA256, cfgSHA256: expectedCFGSHA256,
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: pin)
        let parseRequest = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            bundle: reference, graphEvents: parseWork.appendingPathComponent("events.bin"),
            traceOutput: parseWork.appendingPathComponent("counterexample.json"),
            workingDirectory: parseWork, finiteGraphCase: launch, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let configuration = try TLCReferenceConfiguration.parse(parseRequest, checking: [])
        let lines = configuration.declarations.split(whereSeparator: \.isNewline)
        guard configuration.invariants.isEmpty, configuration.properties.isEmpty,
              !lines.contains(where: { line in
                  ["INIT ", "NEXT ", "SPECIFICATION "].contains { line.hasPrefix($0) }
              }) else {
            throw AssumptionValidationError.invalidReference("state checks or behavior in \(id)")
        }
        let generatedOutput = directory.appendingPathComponent("generated")
        let referenceOutput = directory.appendingPathComponent("reference")
        let generated = try GeneratedTLCOracle.run(
            bundle: rendered.tlaBundle, id: id, maximumStates: maximumStates, timeout: timeout,
            tools: tools, pin: pin, workRoot: work, retained: generatedOutput,
            invocation: .propertyCheck, renderedActions: [], process: process,
            captureEvaluations: true)
        let upstream = try GeneratedTLCOracle.run(
            bundle: reference, id: id, maximumStates: maximumStates, timeout: timeout,
            tools: tools, pin: pin, workRoot: work, retained: referenceOutput,
            invocation: .propertyCheck, renderedActions: [], process: process,
            captureEvaluations: true)
        let left = try verdict(generated, id: id)
        let right = try verdict(upstream, id: id)
        let generatedSHA = SHA256.hex(Data(rendered.tlaBundle.tla.utf8))
        let generatedCFG = SHA256.hex(Data(rendered.tlaBundle.cfg.utf8))
        try verifyProcess(generatedOutput.appendingPathComponent("tlc-process.json"),
            id: id, verdict: left, moduleSHA256: generatedSHA, cfgSHA256: generatedCFG)
        try verifyProcess(referenceOutput.appendingPathComponent("tlc-process.json"),
            id: id, verdict: right, moduleSHA256: expectedModuleSHA256,
            cfgSHA256: expectedCFGSHA256)
        let generatedValues = try capturedValues(in: generatedOutput)
        let upstreamValues = try capturedValues(in: referenceOutput)
        let difference: String? = if left != right {
            "assumption verdict"
        } else if left.rawValue != expectedVerdict.rawValue {
            "published assumption outcome"
        } else if generatedValues != upstreamValues {
            "evaluated values"
        } else {
            nil
        }
        let report = AssumptionComparisonReport(
            schema: "swifttla.assumption-upstream-comparison", caseID: id,
            result: difference == nil ? "exact" : "different", assumptionCompared: true,
            difference: difference, leftVerdict: left, rightVerdict: right)
        try write(report, in: directory, name: "comparison.json", create: false)
        return report
    }

    private static func requireAssumptionsOnly(_ rendered: RenderedSpecification, id: String) throws {
        guard rendered.isAssumptionsOnly, rendered.actions.isEmpty, rendered.checkNames.isEmpty,
              !rendered.checksDeadlock else {
            throw AssumptionValidationError.invalidScenario(id)
        }
    }

    private static func requireReference(_ reference: TLAModuleBundle, id: String,
        moduleSHA256: String, cfgSHA256: String) throws {
        guard SHA256.hex(Data(reference.tla.utf8)) == moduleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == cfgSHA256 else {
            throw AssumptionValidationError.invalidReference(id)
        }
    }

    private static func verdict(_ outcome: TLCExecutionOutcome, id: String) throws -> ValidationVerdict {
        switch outcome {
        case .completed: .satisfied
        case .assumptionViolation: .violated
        default: throw AssumptionValidationError.invalidOutcome("\(id): \(outcome)")
        }
    }

    private static func capturedValues(in directory: URL) throws -> [String] {
        try TLCEvaluationOutput(reading: directory.appendingPathComponent("tlc-evaluation.bin"))
            .values.map(\.canonicalEncoding)
    }

    private static func verifyProcess(_ url: URL, id: String, verdict: ValidationVerdict,
        moduleSHA256: String, cfgSHA256: String) throws {
        let data = try Data(contentsOf: url)
        guard let process = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              process["caseID"] as? String == id,
              let invocation = process["invocation"] as? [String: Any],
              invocation["exitStatus"] as? Int == (verdict == .satisfied ? 0 : 10),
              let arguments = invocation["arguments"] as? [String],
              arguments.contains("org.swifttla.conformance.TLCEvaluationOutput"),
              arguments.contains(where: { $0.hasPrefix("-Dswifttla.tlc.evaluation.path=") }),
              let inputs = process["inputs"] as? [[String: String]],
              inputs.contains(where: { $0["file"]?.hasSuffix(".tla") == true
                  && $0["sha256"] == moduleSHA256 }),
              inputs.contains(where: { $0["file"]?.hasSuffix(".cfg") == true
                  && $0["sha256"] == cfgSHA256 }) else {
            throw AssumptionValidationError.invalidEvidence("TLC process receipt")
        }
    }

    private static func write<T: Encodable>(_ report: T, in directory: URL,
        name: String, create: Bool = true) throws {
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
