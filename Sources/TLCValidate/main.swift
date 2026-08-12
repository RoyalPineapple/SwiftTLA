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
    Usage: tlc-validate <name>
      operators: arithmetic comparison logic sets tuples records functions casexpr choose forall
      parity:    list | <ParityCatalog id>
      oracle:    symmetric-collections (alias: symmetric-oracle)
    """, stderr)
    exit(1)
}

private typealias CoreConformanceManifest = CoreConformanceCasesManifestV1

private struct CoreConformanceToolchain: Decodable {
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

private enum CoreConformanceCLIError: Error, CustomStringConvertible {
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
        let manifest = try decode(CoreConformanceManifest.self, at: URL(fileURLWithPath: casesPath))
        guard manifest.schema == CoreConformanceCasesManifestV1.schema else {
            throw CoreConformanceCLIError.invalidManifest("unsupported schema")
        }
        let selected: [CoreConformanceManifest.Entry]
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
        for entry in selected {
            try validateIdentityMapping(entry.identityMapping, for: try swiftSpec(entry.swiftSpec), caseID: entry.id)
        }
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
        guard lock.schema == "TLCReferencePinV1" else {
            throw CoreConformanceCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw CoreConformanceCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let pin = try TLCReferencePinV1(
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
            !FileManager.default.fileExists(atPath: artifact.path)
        {
            throw CoreConformanceCLIError.missingFile(artifact.path)
        }
        let referenceArtifacts = try TLCReferenceInspectorV1.inspect(
            artifacts: TLCReferenceArtifactsV1(
                jar: jar,
                javaArchive: javaArchivePath,
                bridgeSource: bridgeSource,
                bridgeBinary: bridgeClasses
                    .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
                    .appendingPathExtension("class"),
                jarManifest: "",
                runtime: TLCJavaRuntimeIdentityV1(
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

        var exitCode: Int32 = CoreConformanceExitCodeV1.exact.rawValue
        for entry in selected {
            let expectedExit = Int32(entry.expectedExit ?? Int(CoreConformanceExitCodeV1.exact.rawValue))
            guard expectedExit == CoreConformanceExitCodeV1.exact.rawValue ||
                expectedExit == CoreConformanceExitCodeV1.semanticDifference.rawValue
            else {
                throw CoreConformanceCLIError.invalidManifest(
                    "unsupported expected exit \(expectedExit) for \(entry.id)")
            }
            let caseOutput = selected.count == 1
                ? output
                : output.appendingPathComponent(entry.id, isDirectory: true)
            let declaredCase = try declaredCase(entry, pin: pin, architecture: architecture)
            let request = TLCProcessRequestV1(
                javaExecutable: java,
                jar: jar,
                bridgeClasses: bridgeClasses,
                module: try inputPath(entry.module, within: inputRoot),
                configuration: try inputPath(entry.configuration, within: inputRoot),
                graphEvents: runRoot.appendingPathComponent("\(entry.id).events.jsonl"),
                traceOutput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                replayInput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                workingDirectory: runRoot,
                arguments: entry.arguments,
                expectedCase: declaredCase,
                runID: options.gateRunID ?? UUID(),
                referencePin: pin,
                referenceArtifacts: referenceArtifacts
            )
            let result = CoreConformanceRunnerV1().run(
                case: declaredCase,
                swiftExploration: {
                    SwiftExplorationEvidenceV1(
                        caseID: declaredCase.id,
                        exploration: try ModelChecker(spec: try swiftSpec(entry.swiftSpec)).explore()
                    )
                },
                tlcRequest: request,
                replay: try replayPolicy(entry.replay),
                outputDirectory: caseOutput
            )
            if let diagnostic = result.diagnostic {
                fputs("core-conformance \(entry.id): \(diagnostic.phase.rawValue): \(diagnostic.code)\n", stderr)
            } else {
                print("core-conformance \(entry.id): \(result.exitCode.rawValue) \(result.evidenceDirectory?.path ?? "")")
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
    let report: CoreSupportAdmissionV1
    let registersLoaded: Bool
    let requestedSupportIsAdmitted: Bool
    do {
        let casesPath = try requiredEnvironment("CORE_CONFORMANCE_CASES", environment)
        let manifest = try decode(CoreConformanceManifest.self, at: URL(fileURLWithPath: casesPath))
        let ledger = try decode(
            CoreDivergenceLedgerV1.self,
            at: governanceURL(
                environment["CORE_CONFORMANCE_DIVERGENCES"],
                projectRoot: projectRoot,
                defaultPath: "Verification/CoreConformance/divergences.json"))
        let surface = try decode(
            CoreSupportSurfaceV1.self,
            at: governanceURL(
                environment["CORE_CONFORMANCE_SUPPORT_SURFACE"],
                projectRoot: projectRoot,
                defaultPath: "Verification/CoreConformance/support-surface.json"))
        let evidenceRoot = URL(fileURLWithPath: options.evidence).standardizedFileURL
        let evidence = manifest.cases.map {
            CoreSupportCaseEvidenceV1(
                caseID: $0.id,
                directory: evidenceRoot.appendingPathComponent($0.id, isDirectory: true),
                relativeDirectory: $0.id)
        }
        report = CoreSupportGateV1().evaluate(CoreSupportGateInputV1(
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
        report = invalidRegisterReport(gateRunID: options.gateRunID)
        registersLoaded = false
        requestedSupportIsAdmitted = false
        fputs("core-support-gate: register loading failed: \(error)\n", stderr)
    }

    do {
        try writeAdmissionReport(report, to: reportURL)
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
    report: CoreSupportAdmissionV1,
    registersLoaded: Bool,
    requestedSupportIsAdmitted: Bool,
    prerequisiteAvailable: Bool,
    conformanceExitCode: Int32
) -> Int32 {
    let systemReasons: Set<CoreSupportReasonCodeV1> = [
        .invalidRegister,
        .missingPrerequisite,
        .missingEvidence,
        .partialEvidence,
        .foreignRun,
        .manifestDigestMismatch,
        .toolchainDigestMismatch,
        .executionFailed,
    ]
    let hasSystemFailure = report.entries.contains { entry in
        !systemReasons.isDisjoint(with: Set(entry.reasonCodes))
    }
    guard registersLoaded,
          prerequisiteAvailable,
          conformanceExitCode != CoreConformanceExitCodeV1.failure.rawValue,
          !hasSystemFailure
    else {
        return CoreConformanceExitCodeV1.failure.rawValue
    }
    if report.finalExitClass == .success, requestedSupportIsAdmitted {
        return conformanceExitCode == CoreConformanceExitCodeV1.exact.rawValue
          ? CoreConformanceExitCodeV1.exact.rawValue
          : CoreConformanceExitCodeV1.failure.rawValue
    }
    return CoreConformanceExitCodeV1.semanticDifference.rawValue
}

private func failCoreConformance(_ error: Error) -> Never {
    fputs("core-conformance: \(error)\n", stderr)
    exit(CoreConformanceExitCodeV1.failure.rawValue)
}

private func governanceURL(_ configuredPath: String?, projectRoot: URL, defaultPath: String) -> URL {
    if let configuredPath, !configuredPath.isEmpty {
        return URL(fileURLWithPath: configuredPath).standardizedFileURL
    }
    return projectRoot.appendingPathComponent(defaultPath)
}

private func invalidRegisterReport(gateRunID: UUID) -> CoreSupportAdmissionV1 {
    let entry = try! CoreSupportAdmissionEntryV1(
        supportID: "governance-register",
        decision: .blocked,
        reasonCodes: [.invalidRegister],
        mandatoryCaseIDs: ["governance-register"],
        divergenceIDs: [])
    return try! CoreSupportAdmissionV1(gateRunID: gateRunID, entries: [entry])
}

private func writeAdmissionReport(_ report: CoreSupportAdmissionV1, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(report)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
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
            return "Usage: tlc-validate temporal-symmetry <run|gate> --evidence <directory> --report <file> --run-id <uuid> --core-admission <file> --core-report-id <uuid> [--prerequisite available|unavailable]"
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
    let report: TemporalSymmetryAdmissionV1
    do {
        report = try temporalSymmetryAdmissionReport(options: options, projectRoot: projectRoot)
    } catch {
        fputs("temporal-symmetry: gate input unavailable: \(error)\n", stderr)
        report = unavailableTemporalSymmetryReport(gateRunID: options.gateRunID)
    }

    do {
        try writeTemporalSymmetryAdmissionReport(report, to: reportURL)
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
    let cases = try decode(TemporalSymmetryCasesV1.self, at: casesURL)
    _ = try projectRelativePath(URL(fileURLWithPath: options.evidence), projectRoot: projectRoot)
    try TemporalSymmetryConformanceRunnerV1().run(TemporalSymmetryConformanceRunnerInputV1(
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
        URL(fileURLWithPath: options.evidence),
    ]
    let candidate = resolvedProspectivePath(reportURL)
    guard protected.allSatisfy({ !pathsOverlap(candidate, resolvedProspectivePath($0)) }) else {
        throw TemporalSymmetryCLIError.unsafeReportDestination(reportURL.path)
    }
}

private func temporalSymmetryAdmissionReport(
    options: TemporalSymmetryGateOptions,
    projectRoot: URL
) throws -> TemporalSymmetryAdmissionV1 {
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
    let cases = try decode(TemporalSymmetryCasesV1.self, at: casesURL)
    let ledger = try decode(TemporalSymmetryDivergenceLedgerV1.self, at: ledgerURL)
    let surface = try decode(TemporalSymmetrySupportSurfaceV1.self, at: surfaceURL)
    let manifestSHA256 = try fileSHA256(casesURL)
    let toolchainSHA256 = try fileSHA256(toolchainURL)

    let coreURL = URL(fileURLWithPath: options.coreAdmission).standardizedFileURL
    let corePath = try projectRelativePath(coreURL, projectRoot: projectRoot)
    let coreReport = try decode(CoreSupportAdmissionV1.self, at: coreURL)
    let coreDigest = try fileSHA256(coreURL)
    let coreReference = try TemporalSymmetryCoreAdmissionReferenceV1(
        reportID: options.coreReportID,
        gateRunID: coreReport.gateRunID,
        report: try CoreEvidenceReferenceV1(path: corePath, sha256: coreDigest))
    let coreContext = try TemporalSymmetryCoreAdmissionContextV1(
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
    return TemporalSymmetrySupportGateV1().evaluate(TemporalSymmetryGateInputV1(
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
    cases: TemporalSymmetryCasesV1,
    root: URL,
    projectRoot: URL,
    manifestSHA256: String,
    toolchainSHA256: String
) throws -> [TemporalSymmetryCaseEvidenceV1] {
    try cases.cases.compactMap { declaredCase in
        let filename = declaredCase.kind == .temporal
            ? "temporal-comparison.json"
            : "symmetry-orbit-comparison.json"
        let path = root.appendingPathComponent(declaredCase.id, isDirectory: true)
            .appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let reference = try CoreEvidenceReferenceV1(
            path: try projectRelativePath(path, projectRoot: projectRoot),
            sha256: try fileSHA256(path))
        let data = try Data(contentsOf: path)
        let comparison: TemporalSymmetryComparisonEvidenceV1
        switch declaredCase.kind {
        case .temporal:
            let temporal = try JSONDecoder().decode(TemporalComparisonV1.self, from: data)
            try validateCompleteGraphEvidence(temporal, declaredCase: declaredCase, projectRoot: projectRoot)
            comparison = .temporal(temporal)
        case .symmetry:
            comparison = .symmetry(try JSONDecoder().decode(SymmetryOrbitComparisonV1.self, from: data))
        }
        return try TemporalSymmetryCaseEvidenceV1(
            comparison: comparison,
            comparisonEvidence: reference,
            manifestSHA256: manifestSHA256,
            toolchainSHA256: toolchainSHA256,
            status: .complete,
            normalizedDifferenceFingerprint: comparison.outcome == .difference ? SHA256V1.hex(data) : nil)
    }
}

private func validateCompleteGraphEvidence(
    _ comparison: TemporalComparisonV1,
    declaredCase: TemporalSymmetryCaseV1,
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
    let pin = try TLCReferencePinV1(
        tag: provenance.tlcTag, commit: provenance.tlcCommit, jarSHA256: provenance.tlcJarSHA256,
        javaDistribution: provenance.javaDistribution, javaVersion: provenance.javaVersion,
        javaArchiveSHA256: provenance.javaArchiveSHA256, bridgeClass: provenance.bridgeClass,
        bridgeSourceSHA256: provenance.bridgeSourceSHA256, bridgeBinarySHA256: provenance.bridgeBinarySHA256)
    let graphCase = try CoreConformanceCaseV1(
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
    let parser = TLCGraphEventParserV1(expectedCase: graphCase)
    let stream = try parser.parse(Data(contentsOf: graphURL))
    guard stream.runID == evidence.graphRunID else {
        throw TemporalSymmetryCLIError.invalidEvidence("foreign complete graph run")
    }
    let canonical = try parser.parseCanonicalRun(
        Data(contentsOf: graphURL),
        result: TLCProcessResultV1(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    guard canonical.isPassEligible,
          TLCTemporalAdapterV1.graphID(canonical) == comparison.tlcResult.graphID,
          canonical.graph.initialStateKeys.sorted().map(\.canonicalEncoding) == comparison.tlcResult.initialStateIDs else {
        throw TemporalSymmetryCLIError.invalidEvidence("complete graph does not bind the temporal comparison")
    }
}

private func requiredCompleteGraphURL(_ reference: CoreEvidenceReferenceV1, urls: [String: URL]) throws -> URL {
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

private func unavailableTemporalSymmetryReport(gateRunID: UUID) -> TemporalSymmetryAdmissionV1 {
    let unavailableReference = try! CoreEvidenceReferenceV1(
        path: "unavailable/core-admission.json", sha256: String(repeating: "0", count: 64))
    let coreAdmission = try! TemporalSymmetryCoreAdmissionReferenceV1(
        reportID: UUID(), gateRunID: UUID(), report: unavailableReference)
    let entry = try! TemporalSymmetryAdmissionEntryV1(
        supportID: "governance-register",
        decision: .blocked,
        reasonCodes: [.missingPrerequisite, .invalidRegister],
        mandatoryCaseIDs: ["governance-register"],
        divergenceIDs: [])
    return try! TemporalSymmetryAdmissionV1(
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

private func writeTemporalSymmetryAdmissionReport(_ report: TemporalSymmetryAdmissionV1, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(report)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

private func temporalSymmetryExitCode(_ exitClass: TemporalSymmetryAdmissionExitClassV1) -> Int32 {
    switch exitClass {
    case .success: return 0
    case .blocked: return 1
    case .unavailable: return 2
    }
}

private func projectRelativePath(_ path: URL, projectRoot: URL) throws -> String {
    let resolved = path.resolvingSymlinksInPath().standardizedFileURL
    let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
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
    SHA256V1.hex(try Data(contentsOf: url))
}

private func failTemporalSymmetry(_ error: Error) -> Never {
    fputs("temporal-symmetry: \(error)\n", stderr)
    exit(2)
}

private struct CoreSupportGateOptions {
    let evidence: String
    let report: String
    let gateRunID: UUID
    let prerequisiteAvailable: Bool
    let conformanceExitCode: Int32
}

private func validateIdentityMapping(
    _ mapping: CoreConformanceCasesManifestV1.Entry.IdentityMapping,
    for spec: TLASpec,
    caseID: String
) throws {
    try validateIdentityMapping(
        mapping.variables,
        expectedNames: Set(spec.variables.map(\.name)),
        kind: "variable",
        caseID: caseID
    )
    try validateIdentityMapping(
        mapping.actions,
        expectedNames: Set(spec.actions.map(\.name)),
        kind: "action",
        caseID: caseID
    )
}

private func validateIdentityMapping(
    _ mapping: [String: String],
    expectedNames: Set<String>,
    kind: String,
    caseID: String
) throws {
    guard Set(mapping.keys) == expectedNames,
          Set(mapping.values) == expectedNames,
          mapping.allSatisfy({ $0.key == $0.value })
    else {
        throw CoreConformanceCLIError.invalidManifest(
            "case \(caseID) has an incomplete or non-identity \(kind) mapping"
        )
    }
}

private func parseCoreConformanceOptions(
    _ arguments: [String]
) throws -> (caseID: String, output: String, gateRunID: UUID?) {
    var caseID: String?
    var output: String?
    var gateRunID: UUID?
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        switch option {
        case "--case" where caseID == nil:
            caseID = arguments[index + 1]
        case "--output" where output == nil:
            output = arguments[index + 1]
        case "--run-id" where gateRunID == nil:
            guard let value = UUID(uuidString: arguments[index + 1]) else {
                throw CoreConformanceCLIError.invalidGateRunID(arguments[index + 1])
            }
            gateRunID = value
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let caseID, !caseID.isEmpty, let output, !output.isEmpty else {
        throw CoreConformanceCLIError.usage
    }
    return (caseID, output, gateRunID)
}

private func parseCoreSupportGateOptions(_ arguments: [String]) throws -> CoreSupportGateOptions {
    var evidence: String?
    var report: String?
    var gateRunID: UUID?
    var prerequisiteAvailable = true
    var conformanceExitCode = CoreConformanceExitCodeV1.exact.rawValue
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        let value = arguments[index + 1]
        switch option {
        case "--evidence" where evidence == nil:
            evidence = value
        case "--report" where report == nil:
            report = value
        case "--run-id" where gateRunID == nil:
            guard let parsed = UUID(uuidString: value) else {
                throw CoreConformanceCLIError.invalidGateRunID(value)
            }
            gateRunID = parsed
        case "--prerequisite":
            switch value {
            case "available": prerequisiteAvailable = true
            case "unavailable": prerequisiteAvailable = false
            default: throw CoreConformanceCLIError.invalidPrerequisite(value)
            }
        case "--conformance-exit":
            guard let parsed = Int32(value),
                  parsed == CoreConformanceExitCodeV1.exact.rawValue
                    || parsed == CoreConformanceExitCodeV1.semanticDifference.rawValue
                    || parsed == CoreConformanceExitCodeV1.failure.rawValue
            else { throw CoreConformanceCLIError.invalidPrerequisite(value) }
            conformanceExitCode = parsed
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let evidence, !evidence.isEmpty,
          let report, !report.isEmpty,
          let gateRunID
    else { throw CoreConformanceCLIError.usage }
    return CoreSupportGateOptions(
        evidence: evidence,
        report: report,
        gateRunID: gateRunID,
        prerequisiteAvailable: prerequisiteAvailable,
        conformanceExitCode: conformanceExitCode)
}

private func requiredEnvironment(_ name: String, _ environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw CoreConformanceCLIError.missingEnvironment(name)
    }
    return value
}

private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CoreConformanceCLIError.missingFile(url.path)
    }
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private func normalizedArchitecture() throws -> String {
    var information = utsname()
    uname(&information)
    let architecture = withUnsafePointer(to: &information.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    switch architecture {
    case "arm64", "aarch64": return "arm64"
    case "x86_64", "amd64": return "x86_64"
    default: throw CoreConformanceCLIError.invalidManifest("unsupported architecture \(architecture)")
    }
}

private func declaredCase(
    _ entry: CoreConformanceCasesManifestV1.Entry,
    pin: TLCReferencePinV1,
    architecture: String
) throws -> CoreConformanceCaseV1 {
    try CoreConformanceCaseV1(
        id: entry.id,
        moduleSHA256: entry.moduleSHA256,
        cfgSHA256: entry.cfgSHA256,
        arguments: entry.arguments,
        argumentsSHA256: entry.argumentsSHA256,
        workers: entry.workers,
        fingerprintPolynomial: entry.fingerprintPolynomial,
        deadlock: entry.deadlock,
        operatingSystem: "macos",
        architecture: architecture,
        environment: [:],
        pin: pin,
        governance: entry.governance
    )
}

private func inputPath(_ relativePath: String, within root: String) throws -> URL {
    guard !relativePath.hasPrefix("/") else {
        throw CoreConformanceCLIError.invalidManifest("input paths must be relative")
    }
    let rootURL = URL(fileURLWithPath: root).standardizedFileURL
    let path = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    guard path.path.hasPrefix(rootURL.path + "/") else {
        throw CoreConformanceCLIError.invalidManifest("input path escapes the pinned checkout")
    }
    return path
}

private func swiftSpec(_ identifier: String) throws -> TLASpec {
    switch identifier {
    case "hour-clock": return Example.hourClock.spec
    case "die-hard-type-ok": return Example.dieHardTypeOK.spec
    default: throw CoreConformanceCLIError.unsupportedSwiftSpec(identifier)
    }
}

private func replayPolicy(_ value: String) throws -> TLCReplayPolicyV1 {
    switch value {
    case "none": return .none
    case "required": return .required
    default: throw CoreConformanceCLIError.invalidReplayPolicy(value)
    }
}


if name == "check-all" {
    var ok = 0; var fail = 0
    print("=== SwiftTLA ModelChecker vs TLC ===")
    for entry in Example.all {
        let mc = ModelChecker(spec: entry.spec, maxStates: 50000)
        do {
            let count = try mc.exploreGraph().states.count
            let result = try mc.check()
            let match = count == entry.expectedDistinct && { if case .ok = result { true } else { false } }()
            if match {
                print("OK   \(entry.id) — \(count) states")
                ok += 1
            } else {
                print("FAIL \(entry.id) — got \(count), TLC=\(entry.expectedDistinct), \(result)")
                fail += 1
            }
        } catch {
            print("ERR  \(entry.id) — \(error)")
            fail += 1
        }
    }
    print("=== \(ok) passed, \(fail) failed, 0 skipped ===")
    exit(fail > 0 ? 1 : 0)
}


if name == "bundle" {
    guard let id = args.count >= 2 ? args[1] : nil else { exit(1) }
    guard let entry = Example.all.first(where: { $0.id == id }) else { exit(1) }
    let b = entry.spec.tlaBundle
    print("=== TLA ===")
    print(b.tla)
    print("=== CFG ===")
    print(b.cfg)
    exit(0)
}


if name == "test-game-of-life" || name == "test-lazy" {
    let spec = Example.gameOfLife.spec
    let mc = ModelChecker(spec: spec, maxStates: 100)
    do { let r = try mc.check(); print("OK: \(r)") }
    catch { print("ERR: \(error)") }
    exit(0)
}

if name == "symmetric-collections" || name == "symmetric-oracle" {
    do {
        try runSymmetricCollectionOracle()
    } catch {
        fputs("Symmetric collection TLC oracle failed: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

if name == "list" {
    for e in Example.all {
        print("\(e.id)\t\(e.expectedDistinct)\t\(e.notes)")
    }
    exit(0)
}

let output: String

switch name {
case "arithmetic":
    let x = Var<Int>("x")
    output = TLASpec("arithmetic") {
        Variable(x, 0)
        Action("add") { x.becomes(x + 1).when(x < 2) }
        Action("sub") { x.becomes(x - 1).when(x > 0) }
        Action("mul") { x.becomes(x * 2).when(x == 1) }
        Action("div") { x.becomes(x / 2).when(x == 2) }
        Action("mod") { x.becomes(x % 3).when(x == 0) }
        Action("neg") { x.becomes(-x).when(x == 1) }
    }.tlaModule

case "comparison":
    let x = Var<Int>("x")
    output = TLASpec("comparison") {
        Variable(x, 0)
        Action("eq") { x.becomes(1).when(x == 0) }
        Action("neq") { x.becomes(2).when(x != 0) || x.becomes(0).when(x == 1) }
        Action("lt") { x.becomes(3).when(x < 2) }
        Action("gt") { x.becomes(4).when(x > 1) || x.becomes(0).when(x == 3) }
    }.tlaModule

case "logic":
    let a = Var<Bool>("a")
    let b = Var<Bool>("b")
    output = TLASpec("logic") {
        Variable(a, false); Variable(b, false)
        Action("toggle") {
            (a == false) && (b == false) && a.becomes(true) ||
            (a == true) && a.becomes(false) && b.becomes(true)
        }
    }.tlaModule

case "sets":
    let s = Var<TLASetType>("s")
    output = TLASpec("sets") {
        Variable(s, TLAValue.set([.int(0), .int(1)]))
        Action("remove") {
            s.cardinality > 0
                && s.becomes(s.subtracting(StateExpr.singleton(0))).when(s.cardinality == 2)
        }
        Action("shrink") {
            s.cardinality == 1 && s.becomes(StateExpr.setLiteral([]))
        }
    }.tlaModule

case "tuples":
    let val = Var<Int>("val")
    output = TLASpec("tuples") {
        Variable(val, 0)
        Action("set") { val.becomes(StateExpr.tuple([1, 2]).count).when(val == 0) }
        Action("access") { val.becomes(StateExpr.tuple([5, 6]).at(1)).when(val == 2) }
    }.tlaModule

case "records":
    let r = Var<Int>("r")
    output = TLASpec("records") {
        Variable(r, 0)
        Action("set") {
            r.becomes(StateExpr.record(["a": 3, "b": 7]).domain.cardinality).when(r == 0)
        }
    }.tlaModule

case "functions":
    let f = Var<Int>("f")
    output = TLASpec("functions") {
        Variable(f, 0)
        Action("apply") {
            f.becomes(StateExpr.function(domain: StateExpr.set([1]), 42).applying(1)).when(f == 0)
        }
    }.tlaModule

case "casexpr":
    let x = Var<Int>("x")
    output = TLASpec("casexpr") {
        Variable(x, 0)
        Action("classify") {
            x.becomes(StateExpr.firstMatch(
                (when: x == 0, then: 10),
                (when: x == 1, then: 20),
                fallback: 99
            )).when(x < 2)
        }
    }.tlaModule

case "choose":
    let picked = Var<Int>("picked")
    let q = Var<TLASetType>("q")
    output = TLASpec("choose") {
        Variable(picked, 0)
        Variable(q, TLAValue.set([.int(0), .int(1)]))
        Action("pick") {
            q.cardinality > 0
                && choose(picked, from: q)
                && q.becomes(q.subtracting(StateExpr.singleton(picked)))
        }
    }.tlaModule

case "forall":
    let ok = Var<Bool>("ok")
    let s = StateExpr.set([1, 2])
    output = TLASpec("forall") {
        Variable(ok, false)
        Action("check") { StateExpr.for(allIn: s, 1 >= 0) && ok.becomes(true) }
    }.tlaModule

default:
    if let entry = Example.all.first(where: { $0.id == name }) {
        output = entry.spec.tlaModule
    } else {
        fputs("Unknown spec: \(name)\n", stderr)
        fputs("Run: tlc-validate list\n", stderr)
        exit(1)
    }
}

print(output, terminator: "")

private struct OracleDevice: Identifiable {
    let id: Int
}

private struct TLCExecution {
    let status: Int32
    let output: String

    var distinctStates: Int? {
        let expression = try? NSRegularExpression(
            pattern: "([0-9]+) distinct states (?:found|generated)",
            options: []
        )
        guard let match = expression?.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ),
        let range = Range(match.range(at: 1), in: output)
        else { return nil }
        return Int(output[range])
    }
}

private enum SymmetricCollectionOracleError: Error, CustomStringConvertible {
    case missingTLCJar(String)
    case missingJavaRuntime([String])
    case missingStateCount(String)
    case swiftTLCMismatch(scope: Int, swift: Int, tlc: Int)
    case quotedStringControlAccepted(String)

    var description: String {
        switch self {
        case .missingTLCJar(let path):
            return "TLC jar not found at \(path); run scripts/setup-tlc.sh or set TLA_TOOLS_JAR."
        case .missingJavaRuntime(let candidates):
            let checked = candidates.joined(separator: ", ")
            return "No executable Java runtime found for TLC. Checked \(checked); set TLC_JAVA or JAVA_HOME, "
                + "or install the repository-configured OpenJDK 21."
        case .missingStateCount(let output):
            return "TLC did not report its distinct-state count:\n\(output)"
        case .swiftTLCMismatch(let scope, let swift, let tlc):
            return "scope \(scope): Swift checker found \(swift) orbit states but TLC found \(tlc)."
        case .quotedStringControlAccepted(let output):
            return "quoted-string symmetry control unexpectedly succeeded:\n\(output)"
        }
    }
}

private func runSymmetricCollectionOracle() throws {
    let jarPath = ProcessInfo.processInfo.environment["TLA_TOOLS_JAR"]
        ?? FileManager.default.currentDirectoryPath + "/.build/tla-tools/tla2tools.jar"
    guard FileManager.default.fileExists(atPath: jarPath) else {
        throw SymmetricCollectionOracleError.missingTLCJar(jarPath)
    }

    for scope in 2...4 {
        let spec = symmetricOracleSpec(scope: scope)
        let swiftStates = try ModelChecker(spec: spec).exploreGraph().states.count
        let execution = try executeTLC(bundle: spec.tlaBundle, moduleName: spec.name, jarPath: jarPath)
        guard let tlcStates = execution.distinctStates else {
            throw SymmetricCollectionOracleError.missingStateCount(execution.output)
        }
        guard execution.status == 0, tlcStates == swiftStates else {
            throw SymmetricCollectionOracleError.swiftTLCMismatch(
                scope: scope,
                swift: swiftStates,
                tlc: tlcStates
            )
        }
        print("OK   symmetric scope \(scope) — Swift/TLC \(swiftStates) orbit states")
    }

    let control = quotedStringSymmetryControl(scope: 2)
    let execution = try executeTLC(bundle: control, moduleName: "SymmetricOracle2", jarPath: jarPath)
    guard execution.status != 0 else {
        throw SymmetricCollectionOracleError.quotedStringControlAccepted(execution.output)
    }
    print("OK   quoted-string symmetry control rejected by TLC")
}

private func symmetricOracleSpec(scope: Int) -> TLASpec {
    let devices = DictionaryVar<OracleDevice, Int>("devices", scope: scope)
    return TLASpec("SymmetricOracle\(scope)") {
        devices
        CollectionAction("advance", on: devices) { member in
            devices[member] == 0 && devices.update(member, to: 1)
        }
        Invariant("ValidPhase") { devices.allSatisfy { $0 == 0 || $0 == 1 } }
    }
}

private func quotedStringSymmetryControl(scope: Int) -> (tla: String, cfg: String) {
    let bundle = symmetricOracleSpec(scope: scope).tlaBundle
    let members = (0..<scope).map { "DevicesMember\($0)" }
    var tla = bundle.tla.replacingOccurrences(
        of: "CONSTANTS \(members.joined(separator: ", "))\n",
        with: ""
    )
    for member in members {
        tla = tla.replacingOccurrences(of: member, with: "\"\(member)\"")
    }
    let cfg = bundle.cfg
        .split(separator: "\n")
        .filter { !$0.hasPrefix("CONSTANT ") }
        .joined(separator: "\n") + "\n"
    return (tla, cfg)
}

private func executeTLC(
    bundle: (tla: String, cfg: String),
    moduleName: String,
    jarPath: String
) throws -> TLCExecution {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftTLA-TLC-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let tlaURL = directory.appendingPathComponent("\(moduleName).tla")
    let cfgURL = directory.appendingPathComponent("\(moduleName).cfg")
    try bundle.tla.write(to: tlaURL, atomically: true, encoding: .utf8)
    try bundle.cfg.write(to: cfgURL, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: try resolveTLCJava())
    process.arguments = ["-cp", jarPath, "tlc2.TLC", "-nowarning", "-config", cfgURL.path, tlaURL.path]
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return TLCExecution(status: process.terminationStatus, output: output)
}

private func resolveTLCJava() throws -> String {
    let environment = ProcessInfo.processInfo.environment
    var candidates = [String]()
    if let java = environment["TLC_JAVA"] {
        candidates.append(java)
    }
    if let javaHome = environment["JAVA_HOME"] {
        candidates.append("\(javaHome)/bin/java")
    }
    candidates += [
        "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java",
        "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
    ]
    if let path = environment["PATH"] {
        candidates += path.split(separator: ":").map { "\($0)/java" }
    }
    if let java = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
        return java
    }
    throw SymmetricCollectionOracleError.missingJavaRuntime(candidates)
}
