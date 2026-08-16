import AlgorithmConformance
import Foundation
import UpstreamParity

private struct PlusCalOracleOptions {
  let fixtureID: String
  let output: URL
}

/// Runs an isolated external-lowering comparison. It is intentionally not a
/// CoreConformance case or support claim: it proves only one bounded
/// Algorithm-to-PlusCal translation relationship.
func runPlusCalOracle(arguments: [String]) -> Never {
  let output: URL?
  do {
    let options = try parsePlusCalOracleOptions(arguments)
    output = options.output
    try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: false)
    let fixture = try oracleFixture(id: options.fixtureID)
    let result = try runPlusCalOracle(fixture: fixture, output: options.output)
    print("pluscal-oracle \(fixture.id): \(result.comparison.isConformant ? "exact" : "difference") \(options.output.path)")
    exit(result.comparison.isConformant ? 0 : 1)
  } catch {
    let report = plusCalOracleFailureReport(error, output: output)
    if let output {
      try? writeOracleJSON(["report": reportJSON(report)], to: output.appendingPathComponent("diagnostic.json"))
    }
    fputs("pluscal-oracle: \(report.whatFailed)\n", stderr)
    fputs("  where: \(report.whereItFailed)\n", stderr)
    fputs("  expected: \(report.expected)\n", stderr)
    fputs("  actual: \(report.actual)\n", stderr)
    fputs("  changed: \(report.systemChange)\n", stderr)
    fputs("  next: \(report.nextSafeAction)\n", stderr)
    exit(2)
  }
}

private func parsePlusCalOracleOptions(_ arguments: [String]) throws -> PlusCalOracleOptions {
  guard arguments.first == "run" else { throw PlusCalOracleCommandError.usage }
  var fixtureID: String?
  var output: URL?
  var index = 1
  while index < arguments.count {
    switch arguments[index] {
    case "--case":
      guard index + 1 < arguments.count else { throw PlusCalOracleCommandError.usage }
      fixtureID = arguments[index + 1]
      index += 2
    case "--output":
      guard index + 1 < arguments.count else { throw PlusCalOracleCommandError.usage }
      output = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
      index += 2
    default:
      throw PlusCalOracleCommandError.usage
    }
  }
  guard let fixtureID, !fixtureID.isEmpty, let output else {
    throw PlusCalOracleCommandError.usage
  }
  guard !FileManager.default.fileExists(atPath: output.path) else {
    throw PlusCalOracleCommandError.outputExists(output.path)
  }
  return .init(fixtureID: fixtureID, output: output)
}

private func oracleFixture(id: String) throws -> AlgorithmConformanceFixture {
  guard let fixture = AlgorithmConformanceRegistry.fixture(id: id) else {
    throw PlusCalOracleCommandError.unknownFixture(id)
  }
  return fixture
}

private func runPlusCalOracle(
  fixture: AlgorithmConformanceFixture,
  output: URL
) throws -> PlusCalOracleResult {
  let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
  let tools = try resolveOracleTools(projectRoot: projectRoot)
  let direct = output.appendingPathComponent("swift-lowered", isDirectory: true)
  let source = output.appendingPathComponent("pluscal-source", isDirectory: true)
  let translated = output.appendingPathComponent("pluscal-translated", isDirectory: true)
  try FileManager.default.createDirectory(at: direct, withIntermediateDirectories: false)
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)

  let moduleName = fixture.specification().name
  let directModule = direct.appendingPathComponent("\(moduleName).tla")
  let directConfiguration = direct.appendingPathComponent("\(moduleName).cfg")
  try Data(fixture.specification().tlaModule.utf8).write(to: directModule, options: .atomic)
  try Data(fixture.configuration.utf8).write(to: directConfiguration, options: .atomic)

  let sourceModule = source.appendingPathComponent("\(moduleName).tla")
  let sourceConfiguration = source.appendingPathComponent("\(moduleName).cfg")
  try Data(fixture.plusCalModule().utf8).write(to: sourceModule, options: .atomic)
  try Data(fixture.configuration.utf8).write(to: sourceConfiguration, options: .atomic)

  let translation = try SystemPlusCalTranslationExecutorV1().execute(.init(
    javaExecutable: tools.java, jar: tools.jar, module: sourceModule,
    configuration: sourceConfiguration, stagingDirectory: translated
  ))
  try writeOracleJSON([
    "command": [tools.java.path] + ["-cp", tools.jar.path, "pcal.trans", "-unixEOL", translation.stagedModule.path],
    "status": translation.status,
    "stdout": translation.stdout,
    "stderr": translation.stderr,
    "originalModuleSHA256": translation.originalModuleSHA256,
    "stagedModuleSHA256": translation.stagedModuleSHA256,
    "stagedOutputChanged": translation.stagedOutputChanged,
    "originalConfigurationSHA256": translation.originalConfigurationSHA256,
    "stagedConfigurationSHA256": translation.stagedConfigurationSHA256,
    "stagedConfigurationChanged": translation.stagedConfigurationChanged
  ], to: output.appendingPathComponent("translation.json"))

  let directRun = try runOracleTLC(
    id: "\(fixture.id)-swift-lowered", module: directModule, configuration: directConfiguration,
    directory: direct, tools: tools
  )
  let plusCalRun = try runOracleTLC(
    id: "\(fixture.id)-pluscal", module: translation.stagedModule,
    configuration: translation.stagedConfiguration, directory: translated, tools: tools
  )
  let comparison = exactFiniteTLCGraphV1(expected: directRun, actual: plusCalRun)
  try writeOracleJSON([
    "relation": "exactFiniteTLCGraphV1",
    "conformant": comparison.isConformant,
    "differences": comparison.differences.map { ["category": $0.category.rawValue] }
  ], to: output.appendingPathComponent("comparison.json"))
  if !comparison.isConformant {
    try writeOracleJSON(
      ["reports": comparison.failureReports.map(reportJSON)],
      to: output.appendingPathComponent("comparison-diagnostics.json")
    )
  }
  return .init(comparison: comparison)
}

private struct PlusCalOracleResult {
  let comparison: ExactFiniteTLCComparisonV1
}

private struct PlusCalOracleTools {
  let java: URL
  let jar: URL
  let bridgeClasses: URL
  let pin: TLCReferencePinV1
  let artifacts: TLCReferenceArtifactsV1
  let architecture: String
}

private func resolveOracleTools(projectRoot: URL) throws -> PlusCalOracleTools {
  let environment = ProcessInfo.processInfo.environment
  let toolRoot = URL(fileURLWithPath: try requiredEnvironment("CORE_CONFORMANCE_TOOL_ROOT", environment))
  let lock = try decode(
    CoreConformanceToolchain.self,
    at: projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json")
  )
  guard lock.schema == "TLCReferencePinV1" else {
    throw PlusCalOracleCommandError.invalidToolchain("unsupported toolchain schema \(lock.schema)")
  }
  let architecture = try normalizedArchitecture()
  guard let archive = lock.java.archives[architecture] else {
    throw PlusCalOracleCommandError.invalidToolchain("no Java archive for \(architecture)")
  }
  let pin = try TLCReferencePinV1(
    tag: lock.tlc.tag, commit: lock.tlc.commit, jarSHA256: lock.tlc.jar.sha256,
    javaDistribution: lock.java.distribution, javaVersion: lock.java.version,
    javaArchiveSHA256: archive.sha256, bridgeClass: lock.bridge.class,
    bridgeSourceSHA256: lock.bridge.sourceSha256, bridgeBinarySHA256: lock.bridge.binarySha256
  )
  let java = toolRoot.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
  let jar = toolRoot.appendingPathComponent("downloads/tla2tools.jar")
  let bridgeClasses = toolRoot.appendingPathComponent("bridge-classes")
  let javaArchive = toolRoot.appendingPathComponent("downloads/temurin-\(architecture).tar.gz")
  let bridgeSource = projectRoot.appendingPathComponent(lock.bridge.source)
  let bridgeBinary = bridgeClasses
    .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
    .appendingPathExtension("class")
  for artifact in [java, jar, bridgeClasses, javaArchive, bridgeSource, bridgeBinary] where
    !FileManager.default.fileExists(atPath: artifact.path) {
    throw PlusCalOracleCommandError.missingTool(artifact.path)
  }
  let artifacts = try TLCReferenceInspectorV1.inspect(
    artifacts: .init(jar: jar, javaArchive: javaArchive, bridgeSource: bridgeSource,
                     bridgeBinary: bridgeBinary, jarManifest: "",
                     runtime: .init(version: "", vendor: "", architecture: architecture, properties: [:])),
    javaExecutable: java, directory: projectRoot
  )
  try pin.validate(artifacts)
  return .init(java: java, jar: jar, bridgeClasses: bridgeClasses, pin: pin, artifacts: artifacts, architecture: architecture)
}

private func runOracleTLC(
  id: String,
  module: URL,
  configuration: URL,
  directory: URL,
  tools: PlusCalOracleTools
) throws -> CanonicalRunV1 {
  let declared = try CoreConformanceCaseV1(
    id: id,
    moduleSHA256: SHA256V1.hex(try Data(contentsOf: module)),
    cfgSHA256: SHA256V1.hex(try Data(contentsOf: configuration)),
    arguments: ["-workers", "1", "-fp", "1"],
    argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(["-workers", "1", "-fp", "1"]),
    workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
    architecture: tools.architecture, environment: [:], pin: tools.pin
  )
  let request = TLCProcessRequestV1(
    javaExecutable: tools.java, jar: tools.jar, bridgeClasses: tools.bridgeClasses,
    module: module, configuration: configuration,
    graphEvents: directory.appendingPathComponent("tlc.events.jsonl"),
    traceOutput: directory.appendingPathComponent("tlc.counterexample.json"),
    replayInput: directory.appendingPathComponent("tlc.counterexample.json"),
    workingDirectory: directory, arguments: declared.arguments, expectedCase: declared,
    runID: UUID(), referencePin: tools.pin, referenceArtifacts: tools.artifacts
  )
  do {
    let process = try TLCProcessAdapterV1().run(request, replay: .none)
    try writeOracleJSON([
      "status": process.primary.status,
      "stdout": process.primary.stdout,
      "stderr": process.primary.stderr,
      "reportedExhaustiveCompletion": process.primary.reportedExhaustiveCompletion
    ], to: directory.appendingPathComponent("tlc-result.json"))
    let canonical = try TLCGraphEventParserV1(expectedCase: declared).parseCanonicalRun(
      try Data(contentsOf: request.graphEvents), result: process.primary
    )
    try writeOracleJSON(canonicalJSON(canonical), to: directory.appendingPathComponent("canonical-graph.json"))
    return canonical
  } catch {
    try? writeOracleJSON(
      ["report": reportJSON(tlcFailureReport(error, request: request))],
      to: directory.appendingPathComponent("tlc-diagnostic.json")
    )
    throw error
  }
}

private func canonicalJSON(_ run: CanonicalRunV1) -> [String: Any] {
  [
    "schema": run.schema.rawValue,
    "initialStates": run.graph.initialStateKeys.sorted().map(\.canonicalEncoding),
    "states": run.graph.states.keys.sorted().map(\.canonicalEncoding),
    "edges": run.graph.edgeOccurrences.keys.sorted().map { edge in
      ["edge": edge.canonicalEncoding, "count": run.graph.edgeOccurrences[edge] ?? 0]
    },
    "observableActions": run.observableActions.sorted(),
    "outcome": String(describing: run.outcome)
  ]
}

private func plusCalOracleFailureReport(_ error: Error, output: URL?) -> ConformanceFailureReportV1 {
  if let translation = error as? PlusCalTranslationErrorV1 {
    let diagnostic = translation.diagnostic
    return .init(
      whatFailed: diagnostic.failedConcept, whereItFailed: diagnostic.filePath,
      expected: diagnostic.expected, actual: diagnostic.actual, systemChange: diagnostic.outputStatus,
      nextSafeAction: diagnostic.nextSafeAction,
      evidence: [
        .init(role: "canonical module", location: diagnostic.originalModule.path),
        .init(role: "staged module", location: diagnostic.stagedModule.path),
        .init(role: "canonical configuration", location: diagnostic.originalConfiguration.path),
        .init(role: "staged configuration", location: diagnostic.stagedConfiguration.path)
      ], toolOutput: [.init(stream: "stdout", content: diagnostic.stdout), .init(stream: "stderr", content: diagnostic.stderr)]
    )
  }
  let evidence = output.map { [ConformanceEvidenceLocationV1(role: "oracle output", location: $0.path)] } ?? []
  return .init(
    whatFailed: "PlusCal oracle could not complete.", whereItFailed: "isolated external-lowering comparison",
    expected: "Two pinned TLC runs and one exact finite graph comparison.",
    actual: String(describing: error),
    systemChange: "No support claim was published; any completed artifacts remain in the declared output directory.",
    nextSafeAction: "Inspect the retained source, translated module, TLC output, and diagnostic before changing the formal model.",
    evidence: evidence
  )
}

private func tlcFailureReport(
  _ error: Error,
  request: TLCProcessRequestV1
) -> ConformanceFailureReportV1 {
  if let processError = error as? TLCProcessErrorV1 {
    return processError.failureReport(for: request)
  }
  return .init(
    whatFailed: "TLC canonical-graph capture could not complete.",
    whereItFailed: "isolated PlusCal oracle TLC run for \(request.caseID)",
    expected: "TLC emits a complete graph-event stream that can be parsed as a canonical finite graph.",
    actual: String(describing: error),
    systemChange: "No comparison was published; the module, configuration, and any partial TLC output remain in the run directory.",
    nextSafeAction: "Inspect the retained module, configuration, tlc-result.json, graph-event stream, and translator evidence before changing the formal model.",
    evidence: [
      .init(role: "TLA+ module", location: request.module.path),
      .init(role: "TLC configuration", location: request.configuration.path),
      .init(role: "TLC graph event output", location: request.graphEvents.path),
      .init(role: "TLC result", location: request.workingDirectory.appendingPathComponent("tlc-result.json").path)
    ]
  )
}

private func reportJSON(_ report: ConformanceFailureReportV1) -> [String: Any] {
  [
    "whatFailed": report.whatFailed, "whereItFailed": report.whereItFailed,
    "expected": report.expected, "actual": report.actual, "systemChange": report.systemChange,
    "nextSafeAction": report.nextSafeAction,
    "evidence": report.evidence.map { ["role": $0.role, "location": $0.location] },
    "toolOutput": report.toolOutput.map { ["stream": $0.stream, "content": $0.content] }
  ]
}

private func writeOracleJSON(_ object: Any, to url: URL) throws {
  let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: url, options: .atomic)
}

private enum PlusCalOracleCommandError: Error, CustomStringConvertible {
  case usage
  case outputExists(String)
  case unknownFixture(String)
  case missingTool(String)
  case invalidToolchain(String)

  var description: String {
    switch self {
    case .usage: "Usage: tlc-validate pluscal-oracle run --case <id> --output <fresh-directory>"
    case .outputExists(let path): "Oracle output already exists: \(path)"
    case .unknownFixture(let id): "No registered PlusCal oracle fixture named '\(id)'."
    case .missingTool(let path): "Pinned PlusCal/TLC tool input is missing: \(path)"
    case .invalidToolchain(let detail): "Pinned PlusCal/TLC toolchain is invalid: \(detail)"
    }
  }
}
