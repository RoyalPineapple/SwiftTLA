import Foundation
import SwiftTLA

private struct NativeInitialFailureOutput: Codable {
    let successfulInitialStates: Int
    let site: Int
    let kind: String
    let operands: [Int]
}

package struct InitialFailureEvidenceReport: Codable, Sendable {
    package let schema: String
    package let sourceSHA: String
    package let inputSHA256: String
    package let tlcCommit: String
    package let tlcJarSHA256: String
    package let graphCompared: Bool
    package let result: String
    package let site: Int
    package let kind: String
    package let operands: [Int]
}

package enum InitialFailureEvidenceError: Error, Equatable {
    case unsupportedNativeOutcome
    case malformedTLCRecord
    case payloadMismatch
    case invalidSourceSHA
}

/// shortcut: one deterministic Int-addition failure, widen after multi-branch failure-set semantics are defined.
package enum InitialFailureEvidence {
    package static func compare(site: Int?, reason: NativeMachineEvaluationError?,
                                successfulInitialStates: Int, verdict: ValidationVerdict,
                                printed: [CanonicalValue]) throws -> (site: Int, operands: [Int]) {
        guard successfulInitialStates == 0, let site,
              case .integerOverflow(.addition, let operands)? = reason,
              operands.count == 2 else {
            throw InitialFailureEvidenceError.unsupportedNativeOutcome
        }
        let expected = CanonicalValue.record([
            "site": .integer(site),
            "kind": .string("integerOverflow.addition"),
            "operands": .tuple(operands.map(CanonicalValue.integer))
        ])
        guard verdict == .violated, printed.count == 1 else {
            throw InitialFailureEvidenceError.malformedTLCRecord
        }
        guard printed[0] == expected else {
            throw InitialFailureEvidenceError.payloadMismatch
        }
        return (site, operands)
    }

    package static func run(toolRoot: URL, projectRoot: URL, pin: TLCReferencePin,
                            sourceSHA: String, to directory: URL) throws -> InitialFailureEvidenceReport {
        guard TLCReferencePin.isRevision(sourceSHA) else {
            throw InitialFailureEvidenceError.invalidSourceSHA
        }
        let native = try CheckedAdditionPrefixInitialModel.initialOutcomes()
        guard native.states.isEmpty, let site = native.firstFailureInitializerOrdinal,
              case .integerOverflow(.addition, let operands)? = native.firstFailure,
              operands.count == 2 else {
            throw InitialFailureEvidenceError.unsupportedNativeOutcome
        }
        let rendered = try CheckedAdditionPrefixInitialModel.render()
        guard let bundle = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedNativeOutcome
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(NativeInitialFailureOutput(successfulInitialStates: 0,
            site: site, kind: "integerOverflow.addition", operands: operands))
            .write(to: directory.appendingPathComponent("native-initial-failure.json"), options: .atomic)
        try GeneratedTLCOracle.retainGeneratedInputs(bundle,
            in: directory.appendingPathComponent("generated-tla"))
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        let retained = directory.appendingPathComponent("tlc")
        let arguments = ["-workers", "1", "-fp", "1"]
        let inputSHA = try GeneratedTLCOracle.inputIdentity(bundle: bundle, pin: pin,
            arguments: arguments, invocation: .propertyCheck, captureEvaluations: true)
        let outcome = try GeneratedTLCOracle.run(bundle: bundle,
            id: "ordered-int-initial-failure", maximumStates: 1, timeout: 300,
            tools: ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: pin),
            pin: pin, workRoot: work, retained: retained,
            invocation: .propertyCheck, renderedActions: [],
            process: TLCProcessAdapter(), captureEvaluations: true)
        let verdict = try GeneratedTLCOracle.initialFailureVerdict(
            outcome: outcome, retained: retained, module: bundle.root.name)
        let printed = try TLCEvaluationOutput(reading:
            retained.appendingPathComponent("tlc-evaluation.bin")).values
        let selected = try compare(site: native.firstFailureInitializerOrdinal,
            reason: native.firstFailure, successfulInitialStates: native.states.count,
            verdict: verdict, printed: printed)
        let report = InitialFailureEvidenceReport(schema: "swifttla.initial-failure-evidence-v1",
            sourceSHA: sourceSHA, inputSHA256: inputSHA, tlcCommit: pin.commit,
            tlcJarSHA256: pin.jarSHA256, graphCompared: false, result: "exact",
            site: selected.site, kind: "integerOverflow.addition", operands: selected.operands)
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"),
            options: .atomic)
        return report
    }
}
