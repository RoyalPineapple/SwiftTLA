import SwiftTLA
import UpstreamParity
import Foundation
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "finite-graph" {
    runFiniteGraphCheck(arguments: Array(args.dropFirst()))
}
if args.first == "temporal-symmetry" {
    runTemporalSymmetry(arguments: Array(args.dropFirst()))
}
guard let name = args.first else {
    fputs("""
    Usage: tlc-validate <command>
      finite-graph run ...
      temporal-symmetry run ...
    """, stderr)
    exit(1)
}
fputs("tlc-validate: unknown command \(name)\n", stderr)
exit(1)
struct PinnedTLCToolchain: Decodable {
    let schema: String
    let tlc: TLC
    let java: Java
    let bridge: Bridge
    struct TLC: Decodable {
        let tag: String
        let commit: String
        let jar: Artifact
    }
    struct Java: Decodable {
        let distribution: String
        let version: String
        let archives: [String: Artifact]
    }
    struct Bridge: Decodable {
        let `class`: String
        let source: String
        let sourceSha256: String
        let binarySha256: String
    }
    struct Artifact: Decodable {
        let url: String
        let sha256: String
    }
}

private func referencePin(
    from toolchain: PinnedTLCToolchain,
    javaArchive: PinnedTLCToolchain.Artifact
) throws -> TLCReferencePin {
    try TLCReferencePin(
        tag: toolchain.tlc.tag,
        commit: toolchain.tlc.commit,
        jarSHA256: toolchain.tlc.jar.sha256,
        javaDistribution: toolchain.java.distribution,
        javaVersion: toolchain.java.version,
        javaArchiveSHA256: javaArchive.sha256,
        bridgeClass: toolchain.bridge.class,
        bridgeSourceSHA256: toolchain.bridge.sourceSha256,
        bridgeBinarySHA256: toolchain.bridge.binarySha256
    )
}

enum FiniteGraphCLIError: Error, CustomStringConvertible {
    case usage
    case missingEnvironment(String)
    case missingFile(String)
    case invalidManifest(String)
    case unknownCase(String)
    case outputExists(String)
    case unsupportedSwiftSpec(String)
    case invalidRunID(String)
    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate finite-graph run --case <case-or-all> --output <directory>"
        case .missingEnvironment(let name):
            return "finite-graph is not set up: missing \(name)"
        case .missingFile(let path):
            return "finite-graph prerequisite is missing: \(path)"
        case .invalidManifest(let reason):
            return "invalid finite-graph manifest: \(reason)"
        case .unknownCase(let id):
            return "unknown finite-graph case: \(id)"
        case .outputExists(let path):
            return "output directory already exists: \(path)"
        case .unsupportedSwiftSpec(let id):
            return "unsupported Swift finite-graph spec: \(id)"
        case .invalidRunID(let value):
            return "invalid finite-graph run ID: \(value)"
        }
    }
}
private func runFiniteGraphCheck(arguments: [String]) -> Never {
    guard let command = arguments.first else {
        failFiniteGraphCheck(FiniteGraphCLIError.usage)
    }
    guard command == "run" else {
        failFiniteGraphCheck(FiniteGraphCLIError.usage)
    }
    do {
        let options = try parseFiniteGraphOptions(Array(arguments.dropFirst()))
        let environment = ProcessInfo.processInfo.environment
        let casesPath = try requiredEnvironment("FINITE_GRAPH_CASES", environment)
        let manifest = try decode(FiniteGraphManifest.self, at: URL(fileURLWithPath: casesPath))
        guard manifest.schema == FiniteGraphManifest.schema else {
            throw FiniteGraphCLIError.invalidManifest("unsupported schema")
        }
        let selected: [FiniteGraphManifest.Case]
        if options.caseID == "all" {
            guard !manifest.cases.isEmpty else {
                throw FiniteGraphCLIError.invalidManifest("contains no cases")
            }
            selected = manifest.cases
        } else if let declaration = manifest.cases.first(where: { $0.id == options.caseID }) {
            selected = [declaration]
        } else {
            throw FiniteGraphCLIError.unknownCase(options.caseID)
        }
        let preparedCases = try selected.map { declaration in
            let compilation = try sourceSpecification(declaration.id).compile()
            return (declaration, compilation, compilation.renderedActions())
        }
        let toolRoot = try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", environment)
        let inputRoot = try requiredEnvironment("FINITE_GRAPH_INPUT_ROOT", environment)
        let output = URL(fileURLWithPath: options.output).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw FiniteGraphCLIError.outputExists(output.path)
        }
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let lock = try decode(
            PinnedTLCToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin" else {
            throw FiniteGraphCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw FiniteGraphCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let pin = try referencePin(from: lock, javaArchive: javaArchive)
        let toolDirectory = URL(fileURLWithPath: toolRoot)
        let jar = toolDirectory.appendingPathComponent("downloads/tla2tools.jar")
        let java = toolDirectory.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
        let bridgeClasses = toolDirectory.appendingPathComponent("bridge-classes")
        let javaArchivePath = toolDirectory.appendingPathComponent(
            "downloads/temurin-\(architecture).tar.gz")
        let bridgeSource = projectRoot.appendingPathComponent(lock.bridge.source)
        for artifact in [jar, java, bridgeClasses, javaArchivePath, bridgeSource] where
            !FileManager.default.fileExists(atPath: artifact.path) {
            throw FiniteGraphCLIError.missingFile(artifact.path)
        }
        let referenceArtifacts = try TLCReferenceInspector.inspect(
            artifacts: TLCReferenceArtifacts(
                jar: jar,
                javaArchive: javaArchivePath,
                bridgeSource: bridgeSource,
                bridgeBinary: bridgeClasses
                    .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
                    .appendingPathExtension("class"),
                jarManifest: "",
                runtime: TLCJavaRuntimeIdentity(
                    version: "", vendor: "", architecture: architecture, properties: [:]
                )
            ),
            javaExecutable: java,
            directory: projectRoot
        )
        try pin.validate(referenceArtifacts)
        let runRoot = output.deletingLastPathComponent().appendingPathComponent(
            ".finite-graph-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        if selected.count > 1 {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        }
        var exitCode: Int32 = FiniteGraphExitCode.exact.rawValue
        for (declaration, compilation, renderedActions) in preparedCases {
            let caseOutput = selected.count == 1
                ? output
                : output.appendingPathComponent(declaration.id, isDirectory: true)
            let arguments = ["-workers", "1", "-fp", "1"]
            let finiteGraphCase = try FiniteGraphCase(
                id: declaration.id,
                moduleSHA256: declaration.moduleSHA256,
                cfgSHA256: declaration.cfgSHA256,
                arguments: arguments,
                argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
                workers: 1,
                fingerprintPolynomial: 1,
                deadlock: false,
                operatingSystem: "macos",
                architecture: architecture,
                environment: [:],
                pin: pin,
                renderedActions: renderedActions
            )
            let bundle = try TLCProcessRequest.declaredBundle(
                root: inputPath(declaration.module, within: inputRoot),
                configuration: inputPath(declaration.configuration, within: inputRoot),
                imports: try declaration.imports.map { try inputPath($0, within: inputRoot) }
            )
            let request = TLCProcessRequest(
                javaExecutable: java,
                jar: jar,
                bridgeClasses: bridgeClasses,
                bundle: bundle,
                graphEvents: runRoot.appendingPathComponent("\(declaration.id).events.jsonl"),
                traceOutput: runRoot.appendingPathComponent("\(declaration.id).counterexample.json"),
                replayInput: runRoot.appendingPathComponent("\(declaration.id).counterexample.json"),
                workingDirectory: runRoot,
                arguments: finiteGraphCase.arguments,
                expectedCase: finiteGraphCase,
                runID: options.runID ?? UUID(),
                referencePin: pin,
                referenceArtifacts: referenceArtifacts
            )
            let check = FiniteGraphCheck().run(
                case: finiteGraphCase,
                swiftExploration: {
                    return SwiftExplorationEvidence(
                        caseID: finiteGraphCase.id,
                        exploration: try ModelChecker(
                            compilation: compilation,
                            configuration: try FiniteExplorationConfiguration(
                                maximumStateLimit: 100_000
                            )
                        ).explore()
                    )
                },
                tlcRequest: request,
                replay: .none,
                outputDirectory: caseOutput
            )
            let label = "finite-graph \(declaration.id)"
            if let diagnostic = check.diagnostic {
              let report = diagnostic.report
              fputs("\(label): \(report.whatFailed)\n", stderr)
                fputs("  where: \(report.whereItFailed)\n", stderr)
                fputs("  expected: \(report.expected)\n", stderr)
                fputs("  actual: \(report.actual)\n", stderr)
              fputs("  next: \(report.nextSafeAction)\n", stderr)
            } else if let report = check.comparison?.failureReports.first {
                fputs("\(label): \(report.whatFailed)\n", stderr)
                fputs("  where: \(report.whereItFailed)\n", stderr)
                fputs("  expected: \(report.expected)\n", stderr)
                fputs("  actual: \(report.actual)\n", stderr)
                fputs("  next: \(report.nextSafeAction)\n", stderr)
            } else {
                print("\(label): \(check.exitCode.rawValue) \(check.evidenceDirectory?.path ?? "")")
            }
            if selected.count == 1 {
                exitCode = check.exitCode.rawValue
            } else if check.exitCode != .exact {
                exitCode = max(exitCode, check.exitCode.rawValue)
            }
        }
        exit(exitCode)
    } catch { failFiniteGraphCheck(error) }
}
private func failFiniteGraphCheck(_ error: Error) -> Never {
    fputs("finite-graph: \(error)\n", stderr)
    exit(FiniteGraphExitCode.failure.rawValue)
}
private func governanceURL(_ configuredPath: String?, projectRoot: URL, defaultPath: String) -> URL {
    if let configuredPath, !configuredPath.isEmpty {
        return URL(fileURLWithPath: configuredPath).standardizedFileURL
    }
    return projectRoot.appendingPathComponent(defaultPath)
}
private enum TemporalSymmetryCLIError: Error, CustomStringConvertible {
    case usage
    case missingToolRoot

    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate temporal-symmetry run --output <directory>"
        case .missingToolRoot:
            return "FINITE_GRAPH_TOOL_ROOT is required"
        }
    }
}

private struct TemporalSymmetryOptions {
    let output: URL
}

private func runTemporalSymmetry(arguments: [String]) -> Never {
    guard arguments.first == "run" else {
        failTemporalSymmetry(TemporalSymmetryCLIError.usage)
    }
    let options: TemporalSymmetryOptions
    do {
        options = try parseTemporalSymmetryOptions(Array(arguments.dropFirst()))
    } catch {
        failTemporalSymmetry(error)
    }

    do {
        let projectRoot = try RetainedEvidence.projectRoot(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let environment = ProcessInfo.processInfo.environment
        let casesURL = governanceURL(
            environment["TEMPORAL_SYMMETRY_CASES"], projectRoot: projectRoot,
            defaultPath: "Verification/TemporalSymmetryConformance/cases.json")
        guard let toolRoot = environment["FINITE_GRAPH_TOOL_ROOT"].map(URL.init(fileURLWithPath:)) else {
            throw TemporalSymmetryCLIError.missingToolRoot
        }
        let lock = try decode(
            PinnedTLCToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin" else {
            throw FiniteGraphCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw FiniteGraphCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let records = try TemporalSymmetryCheck().run(.init(
            cases: try decode(TemporalSymmetryCases.self, at: casesURL),
            projectRoot: projectRoot,
            outputDirectory: options.output,
            toolRoot: toolRoot,
            referencePin: try referencePin(from: lock, javaArchive: javaArchive)
        ))
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

private func parseTemporalSymmetryOptions(_ arguments: [String]) throws -> TemporalSymmetryOptions {
    guard arguments.count == 2, arguments[0] == "--output", !arguments[1].isEmpty else {
        throw TemporalSymmetryCLIError.usage
    }
    return TemporalSymmetryOptions(output: URL(fileURLWithPath: arguments[1]).standardizedFileURL)
}

private func failTemporalSymmetry(_ error: Error) -> Never {
    fputs("temporal-symmetry: \(error)\n", stderr)
    exit(2)
}
