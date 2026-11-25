import Foundation
import SwiftTLA

package enum ReferenceCachePolicy { case disabled, readThrough, requireHit }

/// A content-addressed original TLC execution. The Swift port and the comparison
/// verdict are deliberately outside this identity.
enum UpstreamReferenceCache {
    private struct Receipt: Codable {
        let key: String
        let files: [String: String]
        let sourceSHA: String?
        let originRunID: String?
    }

    static func run(_ request: TLCProcessRequest, process: TLCProcessAdapter,
                    retainingIn output: URL, cache: URL, requireHit: Bool = false) throws -> TLCExecutionOutcome {
        try request.validateDeclaredBundle()
        let launch = request.finiteGraphCase
        let input = try GeneratedTLCOracle.inputIdentity(bundle: request.bundle, pin: launch.pin,
            arguments: launch.arguments, invocation: request.invocation,
            captureEvaluations: request.evaluationOutput != nil, supplementalJar: request.supplementalJar)
        let fields = ["reference-execution-v1", request.caseID, request.bundle.root.name, input,
            String(request.bundle.usesFormalStringEncoding),
            String(request.timeout)]
        let key = SHA256.hex(try JSONEncoder().encode(fields))
        let fm = FileManager.default
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let cache = cache.resolvingSymlinksInPath().standardizedFileURL
        let destination = output.resolvingSymlinksInPath().standardizedFileURL.path
        guard destination != cache.path, !destination.hasPrefix(cache.path + "/"),
              !cache.path.hasPrefix(destination + "/") else {
            throw UpstreamTLCParityError.invalidOutcome("reference cache overlaps evidence output")
        }
        let entry = cache.appendingPathComponent(key)
        let receiptName = "reference-origin.json"
        if fm.fileExists(atPath: entry.path) {
            let receiptURL = try RetainedFiles.resolve(entry.appendingPathComponent(receiptName), beneath: cache)
            let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
            guard receipt.key == key, try hashes(in: entry) == receipt.files else {
                throw UpstreamTLCParityError.invalidOutcome("corrupt upstream reference: \(key)")
            }
            let record = try JSONSerialization.jsonObject(with:
                Data(contentsOf: entry.appendingPathComponent("tlc-process.json"))) as? [String: Any]
            let expectedInputs = bundleInputJSON(request.bundle)
            var expectedPin = pinJSON(launch.pin)
            if let jar = request.supplementalJar { expectedPin["supplementalJarSHA256"] = jar.sha256 }
            guard record?["caseID"] as? String == request.caseID,
                  record?["configuration"] as? String == request.bundle.cfg,
                  let inputs = record?["inputs"] as? [[String: String]],
                  Set(inputs) == Set(expectedInputs),
                  inputs.count == expectedInputs.count,
                  let pin = record?["toolPin"] as? NSDictionary, pin.isEqual(to: expectedPin),
                  let invocation = record?["invocation"] as? [String: Any],
                  let status = invocation["exitStatus"] as? Int32 else {
                throw UpstreamTLCParityError.invalidOutcome("invalid upstream process: \(key)")
            }
            let result = try TLCProcessResult(status: status,
                stdout: String(contentsOf: entry.appendingPathComponent("logs/tlc.stdout.log"), encoding: .utf8),
                stderr: String(contentsOf: entry.appendingPathComponent("logs/tlc.stderr.log"), encoding: .utf8))
            let outcome = TLCExecutionOutcome(process: result, invocation: request.invocation)
            if case .failed = outcome { throw UpstreamTLCParityError.invalidOutcome("failed upstream capture") }
            try fm.copyItem(at: entry, to: output)
            print("upstream reference hit \(request.caseID) \(key)")
            return outcome
        }

        guard !requireHit else {
            throw UpstreamTLCParityError.invalidOutcome("no upstream capture for these inputs: \(request.caseID) \(key)")
        }
        let outcome = try process.run(request, retainingIn: output)
        if case .failed = outcome { return outcome }
        let environment = ProcessInfo.processInfo.environment
        let files = try hashes(in: output)
        guard request.invocation != .finiteGraph || outcome != .completed || files["graph-events.bin.gz"] != nil else {
            throw UpstreamTLCParityError.invalidOutcome("missing completed upstream graph")
        }
        let receipt = Receipt(key: key, files: files,
            sourceSHA: environment["SWIFT_TLA_SHA"] ?? environment["GITHUB_SHA"], originRunID: environment["GITHUB_RUN_ID"])
        try JSONEncoder().encode(receipt).write(to: output.appendingPathComponent(receiptName), options: .withoutOverwriting)
        let staging = cache.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: output, to: staging)
        do { try fm.moveItem(at: staging, to: entry) }
        catch let error as CocoaError where error.code == .fileWriteFileExists { /* concurrent fill */ }
        print("upstream reference stored \(request.caseID) \(key)")
        return outcome
    }

    private static func hashes(in root: URL) throws -> [String: String] {
        let fm = FileManager.default
        let allowed = Set(["tlc-process.json", "graph-events.bin.gz", "counterexample.json", "tlc-evaluation.bin",
                           "logs/tlc.stdout.log", "logs/tlc.stderr.log"])
        var result: [String: String] = [:]
        for directory in ["", "logs"] {
            let path = directory.isEmpty ? root : root.appendingPathComponent(directory)
            for file in try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                let name = directory.isEmpty ? file.lastPathComponent : directory + "/" + file.lastPathComponent
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink == false else { throw UpstreamTLCParityError.invalidOutcome(name) }
                if name == "logs", values.isDirectory == true { continue }
                guard values.isRegularFile == true else { throw UpstreamTLCParityError.invalidOutcome(name) }
                if name == "reference-origin.json" { continue }
                guard allowed.contains(name) else { throw UpstreamTLCParityError.invalidOutcome(name) }
                result[name] = SHA256.hex(try Data(contentsOf: file, options: .mappedIfSafe))
            }
        }
        guard ["tlc-process.json", "logs/tlc.stdout.log", "logs/tlc.stderr.log"].allSatisfy({ result[$0] != nil }) else {
            throw UpstreamTLCParityError.invalidOutcome("incomplete upstream capture")
        }
        return result
    }
}
