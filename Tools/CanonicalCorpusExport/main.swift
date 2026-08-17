import CryptoKit
import Foundation
import CanonicalUpstreamCorpus
import SwiftTLA

private struct Manifest: Codable {
    let schema: String
    let swiftTLASHA: String
    let cases: [Case]

    struct Case: Codable {
        let id: String
        let module: String
        let files: [File]

        struct File: Codable {
            let path: String
            let sha256: String
        }
    }
}

private struct CorpusCase {
    let id: String
    let specification: () -> TLASpec
}

private enum ExportError: Error, CustomStringConvertible {
    case usage
    case outputExists(String)
    case invalidAlgorithmCount(id: String, actual: Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: canonical-corpus-export --output <directory> --swift-tla-sha <sha>"
        case .outputExists(let path):
            return "Output directory already exists: \(path)"
        case .invalidAlgorithmCount(let id, let actual):
            return "Canonical corpus case \(id) has \(actual) authored Algorithms; expected exactly one."
        }
    }
}

private let corpus = [
    CorpusCase(id: "boulanger-upstream-port", specification: { BoulangerModel.spec }),
    CorpusCase(id: "kvsnap-upstream-port", specification: { KVsnapModel.spec }),
    CorpusCase(id: "voteproof-upstream-port", specification: { VoteProofModel.spec }),
]

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func write(_ text: String, relativePath: String, under root: URL) throws -> Manifest.Case.File {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = Data(text.utf8)
    try data.write(to: destination, options: .atomic)
    return .init(path: relativePath, sha256: sha256(data))
}

private func parseArguments(_ arguments: [String]) throws -> (output: URL, sha: String) {
    var output: String?
    var sha: String?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--output":
            guard index + 1 < arguments.count else { throw ExportError.usage }
            output = arguments[index + 1]
            index += 2
        case "--swift-tla-sha":
            guard index + 1 < arguments.count else { throw ExportError.usage }
            sha = arguments[index + 1]
            index += 2
        default:
            throw ExportError.usage
        }
    }
    guard let output, let sha, !sha.isEmpty else { throw ExportError.usage }
    return (URL(fileURLWithPath: output).standardizedFileURL, sha)
}

do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    guard !FileManager.default.fileExists(atPath: options.output.path) else {
        throw ExportError.outputExists(options.output.path)
    }
    try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)

    let cases = try corpus.map { item -> Manifest.Case in
        let specification = item.specification()
        let bundle = specification.tlaBundle
        let plusCalModules = try specification.renderAuthoredPlusCalModules()
        guard plusCalModules.count == 1 else {
            throw ExportError.invalidAlgorithmCount(id: item.id, actual: plusCalModules.count)
        }

        var files = [Manifest.Case.File]()
        files.append(try write(bundle.root.tla, relativePath: "\(item.id)/swift/\(bundle.root.name).tla", under: options.output))
        files.append(try write(bundle.root.cfg ?? "", relativePath: "\(item.id)/swift/\(bundle.root.name).cfg", under: options.output))
        for imported in bundle.imports {
            files.append(try write(imported.tla, relativePath: "\(item.id)/imports/\(imported.name).tla", under: options.output))
        }
        files.append(try write(plusCalModules[0], relativePath: "\(item.id)/pluscal/\(bundle.root.name).tla", under: options.output))
        return .init(id: item.id, module: bundle.root.name, files: files.sorted { $0.path < $1.path })
    }

    let manifest = Manifest(schema: "CanonicalCorpusExportV1", swiftTLASHA: options.sha, cases: cases)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: options.output.appendingPathComponent("manifest.json"), options: .atomic)
} catch {
    fputs("canonical-corpus-export: \(error)\n", stderr)
    exit(2)
}
