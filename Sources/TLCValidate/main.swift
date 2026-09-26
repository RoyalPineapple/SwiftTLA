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
default:
    fputs("""
    Usage: tlc-validate <command>
      native list | run --case <id-or-all> --output <directory> --maximum-states <positive-integer>
      oracle run --case <id-or-all> --output <directory> --maximum-states <positive-integer>
      compare run --case <id-or-all> --native <directory> --oracle <directory> --output <directory>
      upstream list | run --case <id-or-all> --output <directory>
      temporal-symmetry run --output <directory>
    """, stderr)
    exit(1)
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
