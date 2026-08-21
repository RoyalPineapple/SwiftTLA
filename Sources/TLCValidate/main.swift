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
if args.first == "public-workflow" {
    runPublicWorkflow(arguments: Array(args.dropFirst()))
}
guard let name = args.first else {
    fputs("""
    Usage: tlc-validate <command>
      core-conformance run|gate ...
      temporal-symmetry run|gate ...
      public-workflow ...
    """, stderr)
    exit(1)
}
fputs("tlc-validate: unknown command \(name)\n", stderr)
exit(1)
private struct PublicWorkflowOptions {
    let output: String
    let hostedCI: Bool
}

private func runPublicWorkflow(arguments: [String]) -> Never {
    do {
        let options = try parsePublicWorkflowOptions(arguments)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try PublicWorkflowConformanceRunner().run(.init(
            projectRoot: root,
            outputRoot: URL(fileURLWithPath: options.output),
            hostedCI: options.hostedCI))
        for check in result.report.checks {
            print("public-workflow \(check.id): \(check.status.rawValue) \(check.actualOutcome?.rawValue ?? "unavailable")")
        }
        print("public-workflow: \(result.report.finalExitClass.rawValue) \(result.reportURL.path)")
        switch result.report.finalExitClass {
        case .success: exit(0)
        case .blocked: exit(1)
        case .unavailable: exit(2)
        }
    } catch {
        fputs("public-workflow: \(error)\n", stderr)
        exit(2)
    }
}

private func parsePublicWorkflowOptions(_ arguments: [String]) throws -> PublicWorkflowOptions {
    var output = ".build/public-workflow-support-gate"
    var hostedCI = false
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--output":
            guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
            output = arguments[index + 1]
            index += 2
        case "--hosted-ci":
            hostedCI = true
            index += 1
        default:
            throw CoreConformanceCLIError.usage
        }
    }
    return PublicWorkflowOptions(output: output, hostedCI: hostedCI)
}
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
enum CoreConformanceCLIError: Error, CustomStringConvertible {
    case usage
    case missingEnvironment(String)
    case missingFile(String)
    case invalidManifest(String)
    case unknownCase(String)
    case outputExists(String)
    case unsupportedSwiftSpec(String)
    case invalidReplayPolicy(String)
    case invalidGateRunID(String)
    case invalidPrerequisite(String)
    case unableToWriteReport(String)
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
        case .invalidGateRunID(let value):
            return "invalid core-support gate run ID: \(value)"
        case .invalidPrerequisite(let value):
            return "invalid core-support prerequisite status: \(value)"
        case .unableToWriteReport(let path):
            return "unable to write core-support admission report: \(path)"
        }
    }
}
private func runCoreConformance(arguments: [String]) -> Never {
    guard let command = arguments.first else {
        failCoreConformance(CoreConformanceCLIError.usage)
    }
    if command == "gate" {
        runCoreSupportGate(arguments: Array(arguments.dropFirst()))
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
        let pin = try TLCReferencePin(
            tag: lock.tlc.tag,
            commit: lock.tlc.commit,
            jarSHA256: lock.tlc.jar.sha256,
            javaDistribution: lock.java.distribution,
            javaVersion: lock.java.version,
            javaArchiveSHA256: javaArchive.sha256,
            bridgeClass: lock.bridge.class,
            bridgeSourceSHA256: lock.bridge.sourceSha256,
            bridgeBinarySHA256: lock.bridge.binarySha256
        )
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
                runID: options.gateRunID ?? UUID(),
                referencePin: pin,
                referenceArtifacts: referenceArtifacts
            )
            let result = CoreConformanceRunner().run(
                case: caseDefinition,
                swiftExploration: {
                    let compilation = try swiftSpec.compile()
                    SwiftExplorationEvidence(
                        caseID: caseDefinition.id,
                        exploration: try ModelChecker(
                            compilation: compilation,
                            configuration: try FiniteExplorationConfiguration(
                                maximumStateLimit: entry.maximumStateLimit
                            )
                        ).explore(),
                        compiledModelIdentity: compilation.identity.value,
                        maximumStateLimit: entry.maximumStateLimit
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
private func runCoreSupportGate(arguments: [String]) -> Never {
    let options: CoreSupportGateOptions
    do {
        options = try parseCoreSupportGateOptions(arguments)
    } catch {
        failCoreConformance(error)
    }
    let environment = ProcessInfo.processInfo.environment
    let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let reportURL = URL(fileURLWithPath: options.report).standardizedFileURL
    let report: CoreSupportAdmission
    let registersLoaded: Bool
    let requestedSupportIsAdmitted: Bool
    do {
        let casesPath = try requiredEnvironment("CORE_CONFORMANCE_CASES", environment)
        let manifest = try decode(CoreConformanceCasesManifest.self, at: URL(fileURLWithPath: casesPath))
        let ledger = try decode(
            CoreDivergenceLedger.self,
            at: governanceURL(
                environment["CORE_CONFORMANCE_DIVERGENCES"],
                projectRoot: projectRoot,
                defaultPath: "Verification/CoreConformance/divergences.json"))
        let surface = try decode(
            CoreSupportSurface.self,
            at: governanceURL(
                environment["CORE_CONFORMANCE_SUPPORT_SURFACE"],
                projectRoot: projectRoot,
                defaultPath: "Verification/CoreConformance/support-surface.json"))
        let evidenceRoot = URL(fileURLWithPath: options.evidence).standardizedFileURL
        let evidence = manifest.cases.map {
            CoreSupportCaseEvidence(
                caseID: $0.id,
                directory: evidenceRoot.appendingPathComponent($0.id, isDirectory: true),
                relativeDirectory: $0.id)
        }
        report = try CoreSupportGate().evaluate(CoreSupportGateInput(
            gateRunID: options.gateRunID,
            manifest: manifest,
            ledger: ledger,
            surface: surface,
            evidence: evidence,
            prerequisiteAvailable: options.prerequisiteAvailable))
        registersLoaded = true
        requestedSupportIsAdmitted = !surface.entries.filter {
            $0.requestedStatus == .requested
        }.isEmpty && surface.entries.filter {
            $0.requestedStatus == .requested
        }.allSatisfy { entry in
            report.entries.first(where: { $0.supportID == entry.id })?.decision == .admitted
        }
    } catch {
        do {
            report = try invalidRegisterReport(gateRunID: options.gateRunID)
        } catch {
            failCoreConformance(error)
        }
        registersLoaded = false
        requestedSupportIsAdmitted = false
        fputs("core-support-gate: register loading failed: \(error)\n", stderr)
    }
    do {
        try ConformanceEvidence.writePrettyCanonical(report, to: reportURL)
    } catch {
        failCoreConformance(CoreConformanceCLIError.unableToWriteReport(reportURL.path))
    }
    for entry in report.entries {
        let reasons = entry.reasonCodes.map(\.rawValue).joined(separator: ",")
        print("core-support-gate \(entry.supportID): \(entry.decision.rawValue) \(reasons)")
    }
    print("core-support-gate: \(report.finalExitClass.rawValue) \(reportURL.path)")
    exit(coreSupportGateExitCode(
        report: report,
        registersLoaded: registersLoaded,
        requestedSupportIsAdmitted: requestedSupportIsAdmitted,
        prerequisiteAvailable: options.prerequisiteAvailable,
        conformanceExitCode: options.conformanceExitCode))
}
/// Exit 1 is reserved for a complete, current evidence evaluation that blocks
/// requested support. Setup, execution, governance, and evidence failures use
/// exit 2 so automation cannot mistake them for a semantic disagreement.
private func coreSupportGateExitCode(
    report: CoreSupportAdmission,
    registersLoaded: Bool,
    requestedSupportIsAdmitted: Bool,
    prerequisiteAvailable: Bool,
    conformanceExitCode: Int32
) -> Int32 {
    let systemReasons: Set<CoreSupportReasonCode> = [
        .invalidRegister,
        .missingPrerequisite,
        .missingEvidence,
        .partialEvidence,
        .foreignRun,
        .manifestDigestMismatch,
        .toolchainDigestMismatch,
        .executionFailed
    ]
    let hasSystemFailure = report.entries.contains { entry in
        !systemReasons.isDisjoint(with: Set(entry.reasonCodes))
    }
    guard registersLoaded,
          prerequisiteAvailable,
          conformanceExitCode != CoreConformanceExitCode.failure.rawValue,
          !hasSystemFailure
    else {
        return CoreConformanceExitCode.failure.rawValue
    }
    if report.finalExitClass == .success, requestedSupportIsAdmitted {
        return conformanceExitCode == CoreConformanceExitCode.exact.rawValue
          ? CoreConformanceExitCode.exact.rawValue
          : CoreConformanceExitCode.failure.rawValue
    }
    return CoreConformanceExitCode.semanticDifference.rawValue
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
private func invalidRegisterReport(gateRunID: UUID) throws -> CoreSupportAdmission {
    let entry = try CoreSupportAdmissionEntry(
        supportID: "governance-register",
        decision: .blocked,
        reasonCodes: [.invalidRegister],
        mandatoryCaseIDs: ["governance-register"],
        divergenceIDs: [])
    return try CoreSupportAdmission(gateRunID: gateRunID, entries: [entry])
}
private enum TemporalSymmetryCLIError: Error, CustomStringConvertible {
    case usage
    case invalidRunID(String)
    case invalidPrerequisite(String)
    case invalidCoreReportID(String)
    case evidenceOutsideProject(String)
    case invalidEvidence(String)
    case unsafeReportDestination(String)
    case unableToWriteReport(String)
    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate temporal-symmetry <run|gate> --evidence <directory> "
                + "--report <file> --run-id <uuid> --core-admission <file> --core-report-id <uuid> "
                + "[--prerequisite available|unavailable]"
        case .invalidRunID(let value):
            return "invalid temporal-symmetry gate run ID: \(value)"
        case .invalidPrerequisite(let value):
            return "invalid temporal-symmetry prerequisite status: \(value)"
        case .invalidCoreReportID(let value):
            return "invalid temporal-symmetry core report ID: \(value)"
        case .evidenceOutsideProject(let path):
            return "temporal-symmetry evidence must be retained inside the project: \(path)"
        case .invalidEvidence(let message):
            return "invalid temporal-symmetry evidence: \(message)"
        case .unsafeReportDestination(let path):
            return "temporal-symmetry report path collides with protected evidence: \(path)"
        case .unableToWriteReport(let path):
            return "unable to write temporal-symmetry admission report: \(path)"
        }
    }
}
private struct TemporalSymmetryGateOptions {
    let evidence: String
    let report: String
    let gateRunID: UUID
    let coreAdmission: String
    let coreReportID: UUID
    let prerequisiteAvailable: Bool
}
private func runTemporalSymmetry(arguments: [String]) -> Never {
    guard let command = arguments.first, command == "run" || command == "gate" else {
        failTemporalSymmetry(TemporalSymmetryCLIError.usage)
    }
    let options: TemporalSymmetryGateOptions
    do {
        options = try parseTemporalSymmetryGateOptions(Array(arguments.dropFirst()))
    } catch {
        failTemporalSymmetry(error)
    }
    let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
    let reportURL = URL(fileURLWithPath: options.report).standardizedFileURL
    do {
        try validateTemporalSymmetryReportDestination(
            reportURL, options: options, projectRoot: projectRoot)
    } catch {
        failTemporalSymmetry(error)
    }
    if command == "run" {
        do {
            try runTemporalSymmetryEvidence(options: options, projectRoot: projectRoot)
        } catch {
            fputs("temporal-symmetry: evidence runner unavailable: \(error)\n", stderr)
        }
    }
    let report: TemporalSymmetryAdmission
    do {
        report = try temporalSymmetryAdmissionReport(options: options, projectRoot: projectRoot)
    } catch {
        fputs("temporal-symmetry: gate input unavailable: \(error)\n", stderr)
        do {
            report = try unavailableTemporalSymmetryReport(gateRunID: options.gateRunID)
        } catch {
            failTemporalSymmetry(error)
        }
    }
    do {
        try ConformanceEvidence.writePrettyCanonical(report, to: reportURL)
    } catch {
        failTemporalSymmetry(TemporalSymmetryCLIError.unableToWriteReport(reportURL.path))
    }
    for entry in report.entries {
        let reasons = entry.reasonCodes.map(\.rawValue).joined(separator: ",")
        print("temporal-symmetry \(entry.supportID): \(entry.decision.rawValue) \(reasons)")
    }
    print("temporal-symmetry: \(report.finalExitClass.rawValue) \(reportURL.path)")
    exit(temporalSymmetryExitCode(report.finalExitClass))
}
private func runTemporalSymmetryEvidence(
    options: TemporalSymmetryGateOptions,
    projectRoot: URL
) throws {
    let environment = ProcessInfo.processInfo.environment
    let casesURL = governanceURL(
        environment["TEMPORAL_SYMMETRY_CASES"], projectRoot: projectRoot,
        defaultPath: "Verification/TemporalSymmetryConformance/cases.json")
    let cases = try decode(TemporalSymmetryCases.self, at: casesURL)
    _ = try projectRelativePath(URL(fileURLWithPath: options.evidence), projectRoot: projectRoot)
    try TemporalSymmetryConformanceRunner().run(TemporalSymmetryConformanceRunnerInput(
        cases: cases,
        gateRunID: options.gateRunID,
        projectRoot: projectRoot,
        outputDirectory: URL(fileURLWithPath: options.evidence).standardizedFileURL,
        toolRoot: environment["CORE_CONFORMANCE_TOOL_ROOT"].map(URL.init(fileURLWithPath:))))
}
private func validateTemporalSymmetryReportDestination(
    _ reportURL: URL,
    options: TemporalSymmetryGateOptions,
    projectRoot: URL
) throws {
    let environment = ProcessInfo.processInfo.environment
    let protected = [
        governanceURL(
            environment["TEMPORAL_SYMMETRY_CASES"], projectRoot: projectRoot,
            defaultPath: "Verification/TemporalSymmetryConformance/cases.json"),
        governanceURL(
            environment["TEMPORAL_SYMMETRY_DIVERGENCES"], projectRoot: projectRoot,
            defaultPath: "Verification/TemporalSymmetryConformance/divergences.json"),
        governanceURL(
            environment["TEMPORAL_SYMMETRY_SUPPORT_SURFACE"], projectRoot: projectRoot,
            defaultPath: "Verification/TemporalSymmetryConformance/support-surface.json"),
        governanceURL(
            environment["TEMPORAL_SYMMETRY_TOOLCHAIN"], projectRoot: projectRoot,
            defaultPath: "Verification/CoreConformance/toolchain.json"),
        URL(fileURLWithPath: options.coreAdmission),
        URL(fileURLWithPath: options.evidence)
    ]
    let candidate = resolvedProspectivePath(reportURL)
    guard protected.allSatisfy({ !pathsOverlap(candidate, resolvedProspectivePath($0)) }) else {
        throw TemporalSymmetryCLIError.unsafeReportDestination(reportURL.path)
    }
}
private func temporalSymmetryAdmissionReport(
    options: TemporalSymmetryGateOptions,
    projectRoot: URL
) throws -> TemporalSymmetryAdmission {
    let environment = ProcessInfo.processInfo.environment
    let casesURL = governanceURL(
        environment["TEMPORAL_SYMMETRY_CASES"], projectRoot: projectRoot,
        defaultPath: "Verification/TemporalSymmetryConformance/cases.json")
    let ledgerURL = governanceURL(
        environment["TEMPORAL_SYMMETRY_DIVERGENCES"], projectRoot: projectRoot,
        defaultPath: "Verification/TemporalSymmetryConformance/divergences.json")
    let surfaceURL = governanceURL(
        environment["TEMPORAL_SYMMETRY_SUPPORT_SURFACE"], projectRoot: projectRoot,
        defaultPath: "Verification/TemporalSymmetryConformance/support-surface.json")
    let toolchainURL = governanceURL(
        environment["TEMPORAL_SYMMETRY_TOOLCHAIN"], projectRoot: projectRoot,
        defaultPath: "Verification/CoreConformance/toolchain.json")
    let cases = try decode(TemporalSymmetryCases.self, at: casesURL)
    let ledger = try decode(TemporalSymmetryDivergenceLedger.self, at: ledgerURL)
    let surface = try decode(TemporalSymmetrySupportSurface.self, at: surfaceURL)
    let manifestSHA256 = try fileSHA256(casesURL)
    let toolchainSHA256 = try fileSHA256(toolchainURL)
    let coreURL = URL(fileURLWithPath: options.coreAdmission).standardizedFileURL
    let corePath = try projectRelativePath(coreURL, projectRoot: projectRoot)
    let coreReport = try decode(CoreSupportAdmission.self, at: coreURL)
    let coreDigest = try fileSHA256(coreURL)
    let coreReference = try TemporalSymmetryCoreAdmissionReference(
        reportID: options.coreReportID,
        gateRunID: coreReport.gateRunID,
        report: try CoreEvidenceReference(path: corePath, sha256: coreDigest))
    let coreContext = try TemporalSymmetryCoreAdmissionContext(
        temporalSymmetryGateRunID: options.gateRunID,
        reportID: coreReference.reportID,
        coreGateRunID: coreReport.gateRunID,
        reportPath: corePath,
        reportSHA256: coreDigest)
    let evidenceRoot = URL(fileURLWithPath: options.evidence).standardizedFileURL
    _ = try projectRelativePath(evidenceRoot, projectRoot: projectRoot)
    let evidence = try temporalSymmetryEvidence(
        cases: cases,
        root: evidenceRoot,
        projectRoot: projectRoot,
        manifestSHA256: manifestSHA256,
        toolchainSHA256: toolchainSHA256)
    return try TemporalSymmetrySupportGate().evaluate(TemporalSymmetryGateInput(
        gateRunID: options.gateRunID,
        coreAdmission: coreReference,
        coreAdmissionContext: coreContext,
        cases: cases,
        ledger: ledger,
        surface: surface,
        evidence: evidence,
        manifestSHA256: manifestSHA256,
        toolchainSHA256: toolchainSHA256,
        prerequisiteAvailable: options.prerequisiteAvailable && coreReport.finalExitClass == .success))
}
private func temporalSymmetryEvidence(
    cases: TemporalSymmetryCases,
    root: URL,
    projectRoot: URL,
    manifestSHA256: String,
    toolchainSHA256: String
) throws -> [TemporalSymmetryCaseEvidence] {
    try cases.cases.compactMap { declaredCase in
        let filename = declaredCase.kind == .temporal
            ? "temporal-comparison.json"
            : "symmetry-orbit-comparison.json"
        let path = root.appendingPathComponent(declaredCase.id, isDirectory: true)
            .appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let reference = try CoreEvidenceReference(
            path: try projectRelativePath(path, projectRoot: projectRoot),
            sha256: try fileSHA256(path))
        let data = try Data(contentsOf: path)
        let comparison: TemporalSymmetryComparisonEvidence
        switch declaredCase.kind {
        case .temporal:
            let temporal = try JSONDecoder().decode(TemporalComparison.self, from: data)
            try validateCompleteGraphEvidence(temporal, declaredCase: declaredCase, projectRoot: projectRoot)
            comparison = .temporal(temporal)
        case .symmetry:
            comparison = .symmetry(try JSONDecoder().decode(SymmetryOrbitComparison.self, from: data))
        }
        return try TemporalSymmetryCaseEvidence(
            comparison: comparison,
            comparisonEvidence: reference,
            manifestSHA256: manifestSHA256,
            toolchainSHA256: toolchainSHA256,
            status: .complete,
            normalizedDifferenceFingerprint: comparison.outcome == .difference ? SHA256.hex(data) : nil)
    }
}
private func validateCompleteGraphEvidence(
    _ comparison: TemporalComparison,
    declaredCase: TemporalSymmetryCase,
    projectRoot: URL
) throws {
    guard let declaration = declaredCase.configuration.completeGraphPass else {
        guard comparison.completeGraphEvidence == nil else {
            throw TemporalSymmetryCLIError.invalidEvidence("unexpected complete graph evidence")
        }
        return
    }
    guard let evidence = comparison.completeGraphEvidence,
          evidence.propertyRunID == comparison.correlation.tlcRunID,
          evidence.sourceInput == declaredCase.sourceInput,
          evidence.configuration == declaration.configuration else {
        throw TemporalSymmetryCLIError.invalidEvidence("invalid complete graph evidence")
    }
    var urls: [String: URL] = [:]
    for reference in [evidence.sourceInput, evidence.configuration, evidence.graphEvents, evidence.result] {
        let url = projectRoot.appendingPathComponent(reference.path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(projectRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: url.path),
              try fileSHA256(url) == reference.sha256 else {
            throw TemporalSymmetryCLIError.invalidEvidence("substituted complete graph artifact")
        }
        urls[reference.path] = url
    }
    let provenance = declaredCase.provenance
    let pin = try TLCReferencePin(
        tag: provenance.tlcTag, commit: provenance.tlcCommit, jarSHA256: provenance.tlcJarSHA256,
        javaDistribution: provenance.javaDistribution, javaVersion: provenance.javaVersion,
        javaArchiveSHA256: provenance.javaArchiveSHA256, bridgeClass: provenance.bridgeClass,
        bridgeSourceSHA256: provenance.bridgeSourceSHA256, bridgeBinarySHA256: provenance.bridgeBinarySHA256)
    let graphCase = try CoreConformanceCase(
        id: declaredCase.id, moduleSHA256: declaredCase.sourceInput.sha256,
        cfgSHA256: declaration.configuration.sha256, arguments: evidence.arguments,
        argumentsSHA256: provenance.argumentsSHA256, workers: 1,
        fingerprintPolynomial: evidence.fingerprintPolynomial, deadlock: false,
        operatingSystem: evidence.operatingSystem, architecture: evidence.architecture,
        environment: evidence.environment, pin: pin)
    let resultURL = try requiredCompleteGraphURL(evidence.result, urls: urls)
    let resultObject = try requiredJSONObject(resultURL)
    guard let status = resultObject["status"] as? Int, status == 0,
          resultObject["reportedExhaustiveCompletion"] as? Bool == true,
          resultObject["isViolation"] as? Bool == false else {
        throw TemporalSymmetryCLIError.invalidEvidence("incomplete complete graph result")
    }
    let graphURL = try requiredCompleteGraphURL(evidence.graphEvents, urls: urls)
    let parser = TLCGraphEventParser(expectedCase: graphCase)
    let graphData = try Data(contentsOf: graphURL)
    let stream = try parser.parse(graphData)
    guard stream.runID == evidence.graphRunID else {
        throw TemporalSymmetryCLIError.invalidEvidence("foreign complete graph run")
    }
    let canonical = try parser.canonicalRun(
        stream,
        result: TLCProcessResult(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    guard canonical.isPassEligible,
          TLCTemporalAdapter.graphID(canonical) == comparison.tlcResult.graphID,
          canonical.graph.initialStateKeys.sorted().map(\.canonicalEncoding) == comparison.tlcResult.initialStateIDs else {
        throw TemporalSymmetryCLIError.invalidEvidence("complete graph does not bind the temporal comparison")
    }
}
private func requiredCompleteGraphURL(_ reference: CoreEvidenceReference, urls: [String: URL]) throws -> URL {
    guard let url = urls[reference.path] else {
        throw TemporalSymmetryCLIError.invalidEvidence("missing complete graph artifact")
    }
    return url
}
private func requiredJSONObject(_ url: URL) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
        throw TemporalSymmetryCLIError.invalidEvidence("malformed complete graph result")
    }
    return object
}
private func unavailableTemporalSymmetryReport(gateRunID: UUID) throws -> TemporalSymmetryAdmission {
    let unavailableReference = try CoreEvidenceReference(
        path: "unavailable/core-admission.json", sha256: String(repeating: "0", count: 64))
    let coreAdmission = try TemporalSymmetryCoreAdmissionReference(
        reportID: UUID(), gateRunID: UUID(), report: unavailableReference)
    let entry = try TemporalSymmetryAdmissionEntry(
        supportID: "governance-register",
        decision: .blocked,
        reasonCodes: [.missingPrerequisite, .invalidRegister],
        mandatoryCaseIDs: ["governance-register"],
        divergenceIDs: [])
    return try TemporalSymmetryAdmission(
        reportID: UUID(),
        gateRunID: gateRunID,
        coreAdmission: coreAdmission,
        manifestSHA256: String(repeating: "0", count: 64),
        toolchainSHA256: String(repeating: "0", count: 64),
        entries: [entry],
        admittedBounds: [:],
        unexplainedDivergenceCount: 0,
        finalExitClass: .unavailable)
}
private func parseTemporalSymmetryGateOptions(_ arguments: [String]) throws -> TemporalSymmetryGateOptions {
    var evidence: String?
    var report: String?
    var gateRunID: UUID?
    var coreAdmission: String?
    var coreReportID: UUID?
    var prerequisiteAvailable = true
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw TemporalSymmetryCLIError.usage }
        let value = arguments[index + 1]
        switch option {
        case "--evidence" where evidence == nil:
            evidence = value
        case "--report" where report == nil:
            report = value
        case "--run-id" where gateRunID == nil:
            guard let parsed = UUID(uuidString: value) else {
                throw TemporalSymmetryCLIError.invalidRunID(value)
            }
            gateRunID = parsed
        case "--core-admission" where coreAdmission == nil:
            coreAdmission = value
        case "--core-report-id" where coreReportID == nil:
            guard let parsed = UUID(uuidString: value) else {
                throw TemporalSymmetryCLIError.invalidCoreReportID(value)
            }
            coreReportID = parsed
        case "--prerequisite":
            switch value {
            case "available": prerequisiteAvailable = true
            case "unavailable": prerequisiteAvailable = false
            default: throw TemporalSymmetryCLIError.invalidPrerequisite(value)
            }
        default:
            throw TemporalSymmetryCLIError.usage
        }
        index += 2
    }
    guard let evidence, !evidence.isEmpty,
          let report, !report.isEmpty,
          let gateRunID,
          let coreAdmission, !coreAdmission.isEmpty,
          let coreReportID
    else {
        throw TemporalSymmetryCLIError.usage
    }
    return TemporalSymmetryGateOptions(
        evidence: evidence,
        report: report,
        gateRunID: gateRunID,
        coreAdmission: coreAdmission,
        coreReportID: coreReportID,
        prerequisiteAvailable: prerequisiteAvailable)
}
private func temporalSymmetryExitCode(_ exitClass: TemporalSymmetryAdmissionExitClass) -> Int32 {
    switch exitClass {
    case .success: return 0
    case .blocked: return 1
    case .unavailable: return 2
    }
}
private func projectRelativePath(_ path: URL, projectRoot: URL) throws -> String {
    let resolved = resolvedProspectivePath(path)
    let root = resolvedProspectivePath(projectRoot)
    guard resolved.path.hasPrefix(root.path + "/") else {
        throw TemporalSymmetryCLIError.evidenceOutsideProject(path.path)
    }
    return String(resolved.path.dropFirst(root.path.count + 1))
}
private func resolvedProspectivePath(_ url: URL) -> URL {
    var candidate = url.standardizedFileURL
    var pendingComponents: [String] = []
    while !FileManager.default.fileExists(atPath: candidate.path) {
        let parent = candidate.deletingLastPathComponent()
        guard parent.path != candidate.path else { break }
        pendingComponents.insert(candidate.lastPathComponent, at: 0)
        candidate = parent
    }
    let existingParent = candidate.resolvingSymlinksInPath().standardizedFileURL
    return pendingComponents.reduce(existingParent) { path, component in
        path.appendingPathComponent(component)
    }.standardizedFileURL
}
private func pathsOverlap(_ first: URL, _ second: URL) -> Bool {
    first.path == second.path
        || first.path.hasPrefix(second.path + "/")
        || second.path.hasPrefix(first.path + "/")
}
private func fileSHA256(_ url: URL) throws -> String {
    SHA256.hex(try Data(contentsOf: url))
}
private func failTemporalSymmetry(_ error: Error) -> Never {
    fputs("temporal-symmetry: \(error)\n", stderr)
    exit(2)
}
