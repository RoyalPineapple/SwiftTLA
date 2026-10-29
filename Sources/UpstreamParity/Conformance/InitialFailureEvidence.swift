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
    package let module: String
    package let moduleSHA256: String
    package let proofSHA256: String
    package let nativeSHA256: String
    package let graphCompared: Bool
    package let result: String
    package let site: Int
    package let kind: String
    package let operands: [Int]
}

package enum InitialFailureEvidenceError: Error, Equatable {
    case unsupportedNativeOutcome
    case unsupportedGeneratedOutput
    case invalidSourceSHA
}

/// shortcut: one deterministic Int-addition failure, widen after multi-branch failure-set semantics are defined.
package enum InitialFailureEvidence {
    private static let proofModule = "SwiftTLAInitialFailureProof"
    private static let failureKind = "integerOverflow.addition"

    package static func prepare(sourceSHA: String, to directory: URL) throws -> InitialFailureEvidenceReport {
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
        guard try rendered.initialEvaluationFailureBundle(capturingRecord: true) != nil else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let generated = directory.appendingPathComponent("generated-tla")
        try GeneratedTLCOracle.retainGeneratedInputs(rendered.tlaBundle, in: generated)
        let nativeURL = directory.appendingPathComponent("native-initial-failure.json")
        let proofURL = generated.appendingPathComponent("\(proofModule).tla")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let nativeBytes = try encoder.encode(NativeInitialFailureOutput(
            successfulInitialStates: 0, site: site, kind: failureKind, operands: operands))
        try nativeBytes.write(to: nativeURL, options: .atomic)
        let proofBytes = Data(proof.utf8)
        try proofBytes.write(to: proofURL, options: .atomic)
        let report = InitialFailureEvidenceReport(
            schema: "swifttla.initial-failure-proof-v1", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            proofSHA256: SHA256.hex(proofBytes), nativeSHA256: SHA256.hex(nativeBytes),
            graphCompared: false, result: "prepared", site: site,
            kind: failureKind, operands: operands)
        try encoder.encode(report).write(
            to: directory.appendingPathComponent("preparation.json"), options: .atomic)
        return report
    }

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int]) throws -> String {
        guard isIdentifier(module), tla.contains("\nInit ==") else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let definitions = tla.split(separator: "\n").compactMap { line -> String? in
            guard let equals = line.range(of: " =="), line.startIndex == line.firstIndex(where: { !$0.isWhitespace }) else {
                return nil
            }
            let left = line[..<equals.lowerBound]
            return String(left.prefix(while: { $0 != "(" && !$0.isWhitespace }))
        }
        let selected = definitions.filter { $0.hasPrefix("__SwiftTLASelectedInitialFailureRecord") }
        let aggregate = definitions.filter { $0.hasPrefix("__SwiftTLAAnyInitialEvaluationFailure") }
        let failures = definitions.filter { $0.hasPrefix("__SwiftTLAInitialOverflowFailure") }
        guard selected.count == 1, aggregate.count == 1, !failures.isEmpty,
              (selected + aggregate + failures).allSatisfy(isIdentifier) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let failureDefs = failures.joined(separator: ", ")
        return """
        ---- MODULE \(proofModule) ----
        EXTENDS \(module), TLAPS

        ExpectedOperand0 == \(binaryLiteral(operands[0]))
        ExpectedOperand1 == \(binaryLiteral(operands[1]))

        THEOREM SelectedFailurePayload ==
          \(selected[0]) =
            [site |-> \(site), kind |-> "\(failureKind)",
             operands |-> <<ExpectedOperand0, ExpectedOperand1>>]
          BY SMT DEF ExpectedOperand0, ExpectedOperand1, \(selected[0]), \(failureDefs)

        THEOREM InitialFailurePrecedesGraph ==
          /\\ \(aggregate[0])
          /\\ ~Init
          BY SMT DEF \(aggregate[0]), Init, \(failureDefs)
        ====
        """
    }

    private static func binaryLiteral(_ value: Int) -> String {
        let radix: UInt = 1_073_741_824
        var magnitude = value.magnitude
        var digits: [UInt] = []
        repeat {
            digits.append(magnitude % radix)
            magnitude /= radix
        } while magnitude != 0
        var expression = String(digits.removeLast())
        while let digit = digits.popLast() {
            expression = "(\(expression) * \(radix) + \(digit))"
        }
        return value < 0 ? "-(\(expression))" : expression
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
