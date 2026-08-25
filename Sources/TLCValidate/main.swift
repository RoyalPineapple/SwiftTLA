import SwiftTLA
import UpstreamParity
import Foundation
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "core-conformance" {
    runCoreConformance(arguments: Array(args.dropFirst()))
}
if args.first == "temporal-symmetry" {
    runTemporalSymmetry(arguments: Array(args.dropFirst()))
}
guard let name = args.first else {
    fputs("""
    Usage: tlc-validate <command>
      core-conformance run ...
      temporal-symmetry run ...
    """, stderr)
    exit(1)
}
fputs("tlc-validate: unknown command \(name)\n", stderr)
exit(1)
struct CoreConformanceToolchain: Decodable {
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
    from toolchain: CoreConformanceToolchain,
    javaArchive: CoreConformanceToolchain.Artifact
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

enum CoreConformanceCLIError: Error, CustomStringConvertible {
    case usage
    case missingEnvironment(String)
    case missingFile(String)
    case invalidManifest(String)
    case unknownCase(String)
    case outputExists(String)
    case unsupportedSwiftSpec(String)
    case invalidReplayPolicy(String)
    case invalidRunID(String)
    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate core-conformance run --case <case-or-all> --output <directory>"
        case .missingEnvironment(let name):
            return "core-conformance is not set up: missing \(name)"
        case .missingFile(let path):
            return "core-conformance prerequisite is missing: \(path)"
        case .invalidManifest(let reason):
            return "invalid core-conformance manifest: \(reason)"
        case .unknownCase(let id):
            return "unknown core-conformance case: \(id)"
        case .outputExists(let path):
            return "output directory already exists: \(path)"
        case .unsupportedSwiftSpec(let id):
            return "unsupported Swift core-conformance spec: \(id)"
        case .invalidReplayPolicy(let policy):
            return "invalid core-conformance replay policy: \(policy)"
        case .invalidRunID(let value):
            return "invalid core-conformance run ID: \(value)"
        }
    }
}
private func runCoreConformance(arguments: [String]) -> Never {
    guard let command = arguments.first else {
        failCoreConformance(CoreConformanceCLIError.usage)
    }
    guard command == "run" else {
        failCoreConformance(CoreConformanceCLIError.usage)
    }
    do {
        let options = try parseCoreConformanceOptions(Array(arguments.dropFirst()))
        let environment = ProcessInfo.processInfo.environment
        let casesPath = try requiredEnvironment("CORE_CONFORMANCE_CASES", environment)
        let manifest = try decode(CoreConformanceCasesManifest.self, at: URL(fileURLWithPath: casesPath))
        guard manifest.schema == CoreConformanceCasesManifest.schema else {
            throw CoreConformanceCLIError.invalidManifest("unsupported schema")
        }
        let selected: [CoreConformanceCasesManifest.Entry]
        if options.caseID == "all" {
            guard !manifest.cases.isEmpty else {
                throw CoreConformanceCLIError.invalidManifest("contains no cases")
            }
            selected = manifest.cases
        } else if let entry = manifest.cases.first(where: { $0.id == options.caseID }) {
            selected = [entry]
        } else {
            throw CoreConformanceCLIError.unknownCase(options.caseID)
        }
        let swiftSpecs = try Dictionary(uniqueKeysWithValues: selected.map { entry in
            (entry.id, try swiftSpec(entry.swiftSpec))
        })
        let invocationMappings = try Dictionary(uniqueKeysWithValues: selected.map { entry in
            guard let spec = swiftSpecs[entry.id] else {
                throw CoreConformanceCLIError.invalidManifest("missing Swift specification for \(entry.id)")
            }
            return (entry.id, try validateMappings(entry, for: spec))
        })
        let toolRoot = try requiredEnvironment("CORE_CONFORMANCE_TOOL_ROOT", environment)
        let inputRoot = try requiredEnvironment("CORE_CONFORMANCE_INPUT_ROOT", environment)
        let output = URL(fileURLWithPath: options.output).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CoreConformanceCLIError.outputExists(output.path)
        }
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let lock = try decode(
            CoreConformanceToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json"))
        guard lock.schema == "TLCReferencePin" else {
            throw CoreConformanceCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw CoreConformanceCLIError.invalidManifest("no locked archive for \(architecture)")
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
            throw CoreConformanceCLIError.missingFile(artifact.path)
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
            ".core-conformance-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        if selected.count > 1 {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        }
        var exitCode: Int32 = CoreConformanceExitCode.exact.rawValue
        for entry in selected {
            guard let swiftSpec = swiftSpecs[entry.id] else {
                throw CoreConformanceCLIError.invalidManifest("missing Swift specification for \(entry.id)")
            }
            guard let actionNames = invocationMappings[entry.id] else {
                throw CoreConformanceCLIError.invalidManifest("missing invocation mapping for \(entry.id)")
            }
            let expectedExit = Int32(entry.expectedExit ?? Int(CoreConformanceExitCode.exact.rawValue))
            guard expectedExit == CoreConformanceExitCode.exact.rawValue ||
                expectedExit == CoreConformanceExitCode.semanticDifference.rawValue
            else {
                throw CoreConformanceCLIError.invalidManifest(
                    "unsupported expected exit \(expectedExit) for \(entry.id)")
            }
            let caseOutput = selected.count == 1
                ? output
                : output.appendingPathComponent(entry.id, isDirectory: true)
            let caseDefinition = try declaredCase(entry, pin: pin, architecture: architecture)
            let bundle = try TLCProcessRequest.declaredBundle(
                root: inputPath(entry.module, within: inputRoot),
                configuration: inputPath(entry.configuration, within: inputRoot),
                imports: try entry.imports.map { try inputPath($0, within: inputRoot) }
            )
            let request = TLCProcessRequest(
                javaExecutable: java,
                jar: jar,
                bridgeClasses: bridgeClasses,
                bundle: bundle,
                graphEvents: runRoot.appendingPathComponent("\(entry.id).events.jsonl"),
                traceOutput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                replayInput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                workingDirectory: runRoot,
                arguments: entry.arguments,
                expectedCase: caseDefinition,
                runID: options.runID ?? UUID(),
                referencePin: pin,
                referenceArtifacts: referenceArtifacts
            )
            let result = CoreConformanceRunner().run(
                case: caseDefinition,
                swiftExploration: {
                    let compilation = try swiftSpec.compile()
                    return SwiftExplorationEvidence(
                        caseID: caseDefinition.id,
                        exploration: try ModelChecker(
                            compilation: compilation,
                            configuration: try FiniteExplorationConfiguration(
                                maximumStateLimit: entry.maximumStateLimit
                            )
                        ).explore()
                    )
                },
                tlcRequest: request,
                replay: try replayPolicy(entry.replay),
                outputDirectory: caseOutput,
                swiftActionNames: actionNames
            )
            let label = expectedExit == CoreConformanceExitCode.semanticDifference.rawValue
                ? "core-conformance negative control \(entry.id)"
                : "core-conformance \(entry.id)"
            if let diagnostic = result.diagnostic {
              let report = diagnostic.report
              fputs("\(label): \(report.whatFailed)\n", stderr)
                fputs("  where: \(report.whereItFailed)\n", stderr)
                fputs("  expected: \(report.expected)\n", stderr)
                fputs("  actual: \(report.actual)\n", stderr)
              fputs("  next: \(report.nextSafeAction)\n", stderr)
            } else if let report = result.comparison?.failureReports.first {
                fputs("\(label): \(report.whatFailed)\n", stderr)
                fputs("  where: \(report.whereItFailed)\n", stderr)
                fputs("  expected: \(report.expected)\n", stderr)
                fputs("  actual: \(report.actual)\n", stderr)
                fputs("  next: \(report.nextSafeAction)\n", stderr)
            } else {
                print("\(label): \(result.exitCode.rawValue) \(result.evidenceDirectory?.path ?? "")")
            }
            if selected.count == 1 {
                exitCode = result.exitCode.rawValue
            } else if result.exitCode.rawValue != expectedExit {
                exitCode = max(exitCode, result.exitCode.rawValue)
            }
        }
        exit(exitCode)
    } catch { failCoreConformance(error) }
}
private func failCoreConformance(_ error: Error) -> Never {
    fputs("core-conformance: \(error)\n", stderr)
    exit(CoreConformanceExitCode.failure.rawValue)
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
            return "CORE_CONFORMANCE_TOOL_ROOT is required"
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
        let projectRoot = try ConformanceEvidence.projectRoot(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let environment = ProcessInfo.processInfo.environment
        let casesURL = governanceURL(
            environment["TEMPORAL_SYMMETRY_CASES"], projectRoot: projectRoot,
            defaultPath: "Verification/TemporalSymmetryConformance/cases.json")
        guard let toolRoot = environment["CORE_CONFORMANCE_TOOL_ROOT"].map(URL.init(fileURLWithPath:)) else {
            throw TemporalSymmetryCLIError.missingToolRoot
        }
        let lock = try decode(
            CoreConformanceToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json"))
        guard lock.schema == "TLCReferencePin" else {
            throw CoreConformanceCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw CoreConformanceCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let records = try TemporalSymmetryConformanceRunner().run(.init(
            cases: try decode(TemporalSymmetryCases.self, at: casesURL),
            runID: UUID(),
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
