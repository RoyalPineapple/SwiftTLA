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
        let source: Source?

        struct Source: Codable {
            let repository: String
            let commit: String
            let path: String
        }
        }
    }
}

private struct CorpusCase {
    let id: String
    let specification: () -> TLASpec
    let swiftConfiguration: String
    let plusCalConfiguration: String
}

private enum ExportError: Error, CustomStringConvertible {
    case usage
    case outputExists(String)
    case invalidAlgorithmCount(id: String, actual: Int)
    case moduleFetch(name: String, url: String)
    case moduleDigest(name: String, expected: String, actual: String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: canonical-corpus-export --output <directory> --swift-tla-sha <sha>"
        case .outputExists(let path):
            return "Output directory already exists: \(path)"
        case .invalidAlgorithmCount(let id, let actual):
            return "Canonical corpus case \(id) has \(actual) authored Algorithms; expected exactly one."
        case .moduleFetch(let name, let url):
            return "Canonical corpus module \(name) could not be fetched from \(url)."
        case .moduleDigest(let name, let expected, let actual):
            return "Canonical corpus module \(name) digest differs: expected \(expected); got \(actual)."
        }
    }
}

private let corpus = [
    CorpusCase(
        id: "boulanger-upstream-port",
        specification: { BoulangerModel.spec },
        swiftConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        plusCalConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n"
    ),
    CorpusCase(
        id: "kvsnap-upstream-port",
        specification: { KVsnapModel.spec },
        swiftConfiguration: "SPECIFICATION Spec\nINVARIANTS TypeOK SnapshotIsolation\nPROPERTIES Termination\nCONSTANT k1 = k1\nCONSTANT k2 = k2\nCONSTANT t1 = t1\nCONSTANT t2 = t2\nCONSTANT t3 = t3\nCONSTANT NoVal = NoVal\n",
        plusCalConfiguration: "SPECIFICATION Spec\nINVARIANTS TypeOK SnapshotIsolation\nPROPERTIES Termination\nCONSTANT k1 = k1\nCONSTANT k2 = k2\nCONSTANT t1 = t1\nCONSTANT t2 = t2\nCONSTANT t3 = t3\nCONSTANT NoVal = NoVal\n"
    ),
    CorpusCase(
        id: "voteproof-upstream-port",
        specification: { VoteProofModel.spec },
        swiftConfiguration: "SPECIFICATION Spec\nINVARIANTS TypeOK VInv1 VInv2 VInv3 VInv4\nPROPERTIES Refines\nCONSTANT Value = {\"v1\", \"v2\"}\nCONSTANT Acceptor = {\"a1\", \"a2\", \"a3\"}\nCONSTANT Quorum = {{\"a1\", \"a2\"}, {\"a1\", \"a3\"}, {\"a2\", \"a3\"}, {\"a1\", \"a2\", \"a3\"}}\nCONSTANT Ballot = {0, 1, 2}\nCHECK_DEADLOCK FALSE\n",
        plusCalConfiguration: "SPECIFICATION Spec\nINVARIANTS TypeOK VInv1 VInv2 VInv3 VInv4\nPROPERTIES Refines\nCONSTANT Value = {\"v1\", \"v2\"}\nCONSTANT Acceptor = {\"a1\", \"a2\", \"a3\"}\nCONSTANT Quorum = {{\"a1\", \"a2\"}, {\"a1\", \"a3\"}, {\"a1\", \"a2\", \"a3\"}}\nCONSTANT Ballot = {0, 1, 2}\nCHECK_DEADLOCK FALSE\n"
    ),
]

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func write(
    _ data: Data,
    relativePath: String,
    source: Manifest.Case.File.Source? = nil,
    under root: URL
) throws -> Manifest.Case.File {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: destination, options: Data.WritingOptions.atomic)
    return .init(path: relativePath, sha256: sha256(data), source: source)
}

private func write(_ text: String, relativePath: String, under root: URL) throws -> Manifest.Case.File {
    try write(Data(text.utf8), relativePath: relativePath, under: root)
}

private func fetchPinnedModule(_ input: CanonicalCorpusModuleInput) throws -> Data {
    let urlString = "https://raw.githubusercontent.com/\(input.source.repository)/\(input.source.commit)/\(input.source.path)"
    guard let url = URL(string: urlString) else {
        throw ExportError.moduleFetch(name: input.name, url: urlString)
    }
    var lastDigest: String?
    for attempt in 0..<3 {
        if let data = try? Data(contentsOf: url) {
            let actual = sha256(data)
            if actual == input.sha256 { return data }
            lastDigest = actual
        }
        if attempt < 2 { Thread.sleep(forTimeInterval: 1) }
    }
    if let lastDigest {
        throw ExportError.moduleDigest(name: input.name, expected: input.sha256, actual: lastDigest)
    }
    throw ExportError.moduleFetch(name: input.name, url: urlString)
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

@main
private enum CanonicalCorpusExport {
    static func main() {
        do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    guard !FileManager.default.fileExists(atPath: options.output.path) else {
        throw ExportError.outputExists(options.output.path)
    }
    try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)

    let cases = try corpus.map { item -> Manifest.Case in
        let specification = item.specification()
        let compilation = try specification.compile()
        let externalInputs = try CanonicalCorpusModuleClosure.inputs(for: item.id).map { input in
            (input, try fetchPinnedModule(input))
        }
        let externalImports = externalInputs.map { input, data in
            TLAModuleFile(name: input.name, tla: String(decoding: data, as: UTF8.self))
        }
        let bundle = try compilation.renderedTLAModuleBundle(additionalImports: externalImports)
        let plusCalModules = try compilation.renderedAuthoredPlusCalModules(additionalImports: externalImports)
        guard plusCalModules.count == 1 else {
            throw ExportError.invalidAlgorithmCount(id: item.id, actual: plusCalModules.count)
        }
        try TLAModuleBundle.untrusted(
            root: TLAModuleFile(name: bundle.root.name, tla: plusCalModules[0]),
            imports: bundle.imports
        ).validateRenderedBundleIntegrity()

        var files = [Manifest.Case.File]()
        files.append(try write(bundle.root.tla, relativePath: "\(item.id)/swift/\(bundle.root.name).tla", under: options.output))
        files.append(try write(item.swiftConfiguration, relativePath: "\(item.id)/swift/\(bundle.root.name).cfg", under: options.output))
        let externalNames = Set(externalImports.map(\.name))
        for imported in bundle.imports where !externalNames.contains(imported.name) {
            files.append(try write(imported.tla, relativePath: "\(item.id)/imports/\(imported.name).tla", under: options.output))
        }
        files.append(try write(plusCalModules[0], relativePath: "\(item.id)/pluscal/\(bundle.root.name).tla", under: options.output))
        files.append(try write(item.plusCalConfiguration, relativePath: "\(item.id)/pluscal/\(bundle.root.name).cfg", under: options.output))
        for (input, data) in externalInputs {
            let source = Manifest.Case.File.Source(
                repository: input.source.repository,
                commit: input.source.commit,
                path: input.source.path
            )
            files.append(try write(
                data,
                relativePath: "\(item.id)/imports/\(input.name).tla",
                source: source,
                under: options.output
            ))
        }
        return .init(id: item.id, module: bundle.root.name, files: files.sorted { $0.path < $1.path })
    }

    let manifest = Manifest(schema: "CanonicalCorpusExportV1", swiftTLASHA: options.sha, cases: cases)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(
        to: options.output.appendingPathComponent("manifest.json"),
        options: Data.WritingOptions.atomic
    )
        } catch {
    fputs("canonical-corpus-export: \(error)\n", stderr)
    exit(2)
        }
    }
}
