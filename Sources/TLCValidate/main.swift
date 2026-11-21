import Foundation
import SwiftTLA
import UpstreamParity

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "native": runNative(arguments: Array(args.dropFirst()))
case "oracle": runOracle(arguments: Array(args.dropFirst()))
case "compare": runCompare(arguments: Array(args.dropFirst()))
case "upstream": runUpstream(arguments: Array(args.dropFirst()))
case "temporal-symmetry": runTemporalSymmetry(arguments: Array(args.dropFirst()))
case "initial-failure": runInitialFailure(arguments: Array(args.dropFirst()))
default:
    fputs("""
    Usage: tlc-validate <command>
      native list | run --case <id-or-all> --output <directory> --maximum-states <positive-integer>
      oracle run --case <id-or-all> --output <directory> --maximum-states <positive-integer>
      oracle cache-key --case <id> --maximum-states <positive-integer>
      compare run --case <id-or-all> --native <directory> --oracle <directory> --output <directory>
      upstream list | run --case <id-or-all> --output <directory> | cache-key --case <id>
      upstream trace-reference --output <directory>
      upstream shiviz-reference --output <directory>
      temporal-symmetry run --output <directory>
      initial-failure prepare --authored-source <swift-file> --native-source <swift-file> --output <directory>
      initial-failure prepare-conditional --authored-source <swift-file> --native-source <swift-file> --proof <tla-file> --output <directory>
    """, stderr)
    exit(1)
}

func validationExecutableURL() -> URL {
    let argument = CommandLine.arguments[0]
    if argument.hasPrefix("/") { return URL(fileURLWithPath: argument).standardizedFileURL }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(argument).standardizedFileURL
}

struct PinnedTLCToolchain: Decodable {
    let schema: String
    let tlc: TLC
    let java: Java
    let bridge: Bridge
    struct TLC: Decodable {
        let tag: String
        let commit: String
        let jar: GitHubBuildArtifact
    }
    struct Java: Decodable {
        let distribution: String
        let version: String
        let archives: [String: Download]
    }
    struct Bridge: Decodable {
        let `class`: String
        let sources: [String: String]
    }
    struct Download: Decodable {
        let url: String
        let sha256: String
    }
    struct GitHubBuildArtifact: Decodable {
        let repository: String
        let artifactID: Int
        let archiveSHA256: String
        let buildRunID: Int
        let buildRevision: String
        let sha256: String
    }
}

func referencePin(
    from toolchain: PinnedTLCToolchain,
    javaArchive: PinnedTLCToolchain.Download, toolRoot: URL
) throws -> TLCReferencePin {
    let binary = toolRoot.appendingPathComponent("bridge.jar")
    return try TLCReferencePin(
        tag: toolchain.tlc.tag,
        commit: toolchain.tlc.commit,
        jarSHA256: toolchain.tlc.jar.sha256,
        javaDistribution: toolchain.java.distribution,
        javaVersion: toolchain.java.version,
        javaArchiveSHA256: javaArchive.sha256,
        bridgeClass: toolchain.bridge.class,
        bridgeSourceHashes: toolchain.bridge.sources,
        bridgeBinarySHA256: SHA256.hex(try Data(contentsOf: binary))
    )
}

private enum TemporalSymmetryCLIError: Error, CustomStringConvertible {
    case usage
    case missingToolRoot

    var description: String {
        switch self {
        case .usage: "Usage: tlc-validate temporal-symmetry run --output <directory>"
        case .missingToolRoot: "FINITE_GRAPH_TOOL_ROOT is required"
        }
    }
}

private func runTemporalSymmetry(arguments: [String]) -> Never {
    guard arguments.count == 3, arguments[0] == "run",
          arguments[1] == "--output", !arguments[2].isEmpty else {
        failTemporalSymmetry(TemporalSymmetryCLIError.usage)
    }
    do {
        let projectRoot = try RetainedFiles.projectRoot(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let environment = ProcessInfo.processInfo.environment
        let casesURL = environment["TEMPORAL_SYMMETRY_CASES"].flatMap { path in
            path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL
        } ?? projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
        guard let toolRoot = environment["FINITE_GRAPH_TOOL_ROOT"].map(URL.init(fileURLWithPath:)) else {
            throw TemporalSymmetryCLIError.missingToolRoot
        }
        let lock = try decode(PinnedTLCToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin" else {
            throw ValidationCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw ValidationCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let records = try TemporalSymmetryCheck().run(.init(
            manifest: try decode(TemporalSymmetryManifest.self, at: casesURL),
            projectRoot: projectRoot,
            outputDirectory: URL(fileURLWithPath: arguments[2]).standardizedFileURL,
            toolRoot: toolRoot,
            referencePin: try referencePin(from: lock, javaArchive: javaArchive, toolRoot: toolRoot)))
        for record in records {
            print("temporal-symmetry \(record.caseID): \(record.outcome.rawValue) \(record.diagnostic)")
        }
        if records.contains(where: { $0.outcome == .unavailable }) { exit(2) }
        if records.contains(where: { $0.outcome == .difference }) { exit(1) }
        exit(0)
    } catch {
        failTemporalSymmetry(error)
    }
}

private func failTemporalSymmetry(_ error: Error) -> Never {
    fputs("temporal-symmetry: \(error)\n", stderr)
    exit(2)
}

private func runInitialFailure(arguments: [String]) -> Never {
    if arguments.first == "prepare-conditional" { runConditionalPreparation(arguments: arguments) }
    guard arguments.count == 7, arguments[0] == "prepare",
          arguments[1] == "--authored-source", !arguments[2].isEmpty,
          arguments[3] == "--native-source", !arguments[4].isEmpty,
          arguments[5] == "--output", !arguments[6].isEmpty else {
        fputs("initial-failure: expected prepare --authored-source <swift-file> --native-source <swift-file> --output <directory>\n", stderr)
        exit(2)
    }
    do {
        let environment = ProcessInfo.processInfo.environment
        guard let sourceSHA = environment["SWIFT_TLA_SHA"] else {
            throw ValidationCLIError.invalidManifest("missing source SHA")
        }
        let authoredSource = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let nativeSource = try String(contentsOf: URL(fileURLWithPath: arguments[4]), encoding: .utf8)
        let report = try InitialFailureEvidence.prepare(sourceSHA: sourceSHA, authoredSource: authoredSource,
            nativeSource: nativeSource, to: URL(fileURLWithPath: arguments[6]).standardizedFileURL)
        print("initial-failure: \(report.result), site \(report.site), no graph")
        exit(0)
    } catch {
        fputs("initial-failure: \(error)\n", stderr)
        exit(2)
    }
}

private func runConditionalPreparation(arguments: [String]) -> Never {
    guard arguments.count == 9, arguments[1] == "--authored-source", arguments[3] == "--native-source",
          arguments[5] == "--proof", arguments[7] == "--output",
          [2, 4, 6, 8].allSatisfy({ !arguments[$0].isEmpty }) else {
        fputs("initial-failure: expected prepare-conditional --authored-source <swift-file> --native-source <swift-file> --proof <tla-file> --output <directory>\n", stderr)
        exit(2)
    }
    do {
        guard let sourceSHA = ProcessInfo.processInfo.environment["SWIFT_TLA_SHA"] else {
            throw ValidationCLIError.invalidManifest("missing source SHA")
        }
        let authored = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let native = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
        let origin = "// original-source-range: \(authored.path):"
        guard let source = String(data: native, encoding: .utf8),
              source.split(separator: "\n").filter({ $0.hasPrefix("// original-source-range: ") }).count == 1,
              source.split(separator: "\n").contains(where: { $0.hasPrefix(origin) }) else {
            throw ValidationCLIError.invalidManifest("conditional expansion has another source origin")
        }
        try ConditionalActionEvidence.prepare(sourceSHA: sourceSHA, authoredSource: Data(contentsOf: authored),
            nativeSource: native, proofSource: Data(contentsOf: URL(fileURLWithPath: arguments[6])),
            to: URL(fileURLWithPath: arguments[8]).standardizedFileURL)
        print("conditional: prepared actual native routing")
        exit(0)
    } catch {
        fputs("conditional: \(error)\n", stderr)
        exit(2)
    }
}
