import Darwin
import Foundation
import SwiftTLA

package enum TLCInvocationKind: Equatable, Sendable {
  case finiteGraph
  case propertyCheck
}

package enum TLCExecutionOutcome: Equatable, Sendable {
  case completed
  case assumptionViolation
  case deadlock
  case safetyViolation
  case livenessViolation
  case temporalTautology
  case assertionViolation
  case failed(exitStatus: Int32)

  fileprivate init(process: TLCProcessResult, invocation: TLCInvocationKind) {
    let exitStatus = process.status
    // The pinned TLC maps EC.TLC_LIVE_FORMULA_TAUTOLOGY (2253) to status 77.
    // This proves a temporal claim, not completion of state-space exploration.
    if exitStatus == 77, process.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let errors = process.stdout.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("Error:") }
      if errors == ["Error: Temporal formula is a tautology (its negation is unsatisfiable)."] {
        self = .temporalTautology
        return
      }
    }
    switch (exitStatus, invocation) {
    case (0, _): self = .completed
    case (10, _): self = .assumptionViolation
    case (11, _): self = .deadlock
    case (12, _): self = .safetyViolation
    case (13, .propertyCheck):
      let errors = process.stdout.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("Error:") }
      // TLC uses status 13 for both temporal and finite action-property failures.
      if errors.count == 2,
         errors[0].hasPrefix("Error: Action property "), errors[0].hasSuffix(" is violated."),
         errors[1] == "Error: The behavior up to this point is:",
         process.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self = .safetyViolation
      } else {
        self = .livenessViolation
      }
    case (14, _): self = .assertionViolation
    default: self = .failed(exitStatus: exitStatus)
    }
  }

}

package struct TLCProcessExecutionFailure: Equatable, Sendable {
  package let message: String
  package let partialStdout: String?
  package let partialStderr: String?

  package init(_ error: Error) {
    if case TLCProcessError.timedOut(let stdout, let stderr) = error {
      message = String(describing: error)
      partialStdout = stdout
      partialStderr = stderr
    } else {
      message = String(describing: error)
      partialStdout = nil
      partialStderr = nil
    }
  }
}

/// A rendered source dependency required by an emitted TLC module bundle was absent.
///
/// TLA+ reports this only after TLC starts. SwiftTLA validates it before launch
/// so a user sees the importing source line and the missing file directly.
package enum TLCModuleBundleError: Error, Equatable, Sendable {
  case unreadableModule(path: String, reason: String)
  case invalidDeclaredClosure(TLAModuleBundleIntegrityError)
  case missingImportedModule(
    module: String,
    importedBy: String,
    line: Int,
    expectedFile: String
  )
}

package enum TLCProcessError: Error, Equatable, Sendable {
  case timedOut(partialStdout: String, partialStderr: String)
  case failedToStart(String)
  case invalidModuleBundle(TLCModuleBundleError)
}

package struct TLCProcessRequest: Equatable, Sendable {
  package let javaExecutable: URL
  package let jar: URL
  package let bridgeJar: URL
  /// The only TLA+ sources that this TLC invocation may receive.
  package let bundle: TLAModuleBundle
  package let graphEvents: URL
  package let traceOutput: URL
  package let workingDirectory: URL
  package let finiteGraphCase: FiniteGraphCase
  package let runID: UUID
  package let timeout: TimeInterval
  package let invocation: TLCInvocationKind
  package let referenceArtifacts: TLCReferenceArtifacts?

  package init(
    javaExecutable: URL,
    jar: URL,
    bridgeJar: URL,
    bundle: TLAModuleBundle,
    graphEvents: URL,
    traceOutput: URL,
    workingDirectory: URL,
    finiteGraphCase: FiniteGraphCase,
    runID: UUID,
    timeout: TimeInterval = 60,
    invocation: TLCInvocationKind,
    referenceArtifacts: TLCReferenceArtifacts? = nil
  ) {
    self.javaExecutable = javaExecutable
    self.jar = jar
    self.bridgeJar = bridgeJar
    self.bundle = bundle
    self.graphEvents = graphEvents
    self.traceOutput = traceOutput
    self.workingDirectory = workingDirectory
    self.finiteGraphCase = finiteGraphCase
    self.runID = runID
    self.timeout = timeout
    self.invocation = invocation
    self.referenceArtifacts = referenceArtifacts
  }

  package var caseID: String { finiteGraphCase.id }

  package var effectiveEnvironment: [String: String] { finiteGraphCase.environment }
  package var moduleFileName: String { "\(bundle.root.name).tla" }
  package var configurationFileName: String { "\(bundle.root.name).cfg" }

  package var launchArguments: [String] {
    return commandArguments(
      module: inputDirectory.appendingPathComponent(moduleFileName),
      configuration: inputDirectory.appendingPathComponent(configurationFileName))
  }

  fileprivate var inputDirectory: URL {
    workingDirectory.appendingPathComponent(
      "input-\(runID.uuidString.lowercased())", isDirectory: true)
  }

  private func commandArguments(
    module: URL,
    configuration: URL
  ) -> [String] {
    let graphOptions = invocation == .finiteGraph ? [
      "-Dswifttla.tlc.graph.path=\(graphEvents.path)",
      "-Dswifttla.tlc.graph.run-id=\(runID.uuidString.lowercased())",
      "-Dswifttla.tlc.graph.case-id=\(caseID)"
    ] : []
    let graphDump = invocation == .finiteGraph
      ? ["-dump", "class,org.swifttla.conformance.LosslessStateWriter"] : []
    let argumentGroups: [[String]] = [
      graphOptions,
      ["-cp", "\(jar.path):\(bridgeJar.path)", "tlc2.TLC"],
      graphDump,
      ["-dumpTrace", "json", traceOutput.path],
      finiteGraphCase.arguments,
      ["-config", configuration.path, module.path]
    ]
    return argumentGroups.flatMap { $0 }
  }

  package func validateLaunchBinding(module: URL, configuration: URL) throws {
    try finiteGraphCase.validateLaunch(module: module, configuration: configuration)
  }

  /// Validates the declared module closure before TLC launch.
  package func validateDeclaredBundle() throws {
    do {
      try bundle.validateDeclaredClosure()
    } catch {
      if let error = error as? TLAModuleBundleIntegrityError {
        throw TLCProcessError.invalidModuleBundle(.invalidDeclaredClosure(error))
      }
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: bundle.root.name + ".tla", reason: redactingSecrets(in: error.localizedDescription)
      ))
    }
  }

  /// Writes exactly the declared bundle to a fresh directory for one TLC invocation.
  /// Nothing else in the source checkout can become an accidental TLC import.
  package func stageDeclaredBundle() throws -> (module: URL, configuration: URL) {
    guard let cfg = bundle.root.cfg else {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: bundle.root.name + ".cfg", reason: "the declared root has no TLC configuration"
      ))
    }
    try validateDeclaredBundle()
    let input = inputDirectory
    guard !FileManager.default.fileExists(atPath: input.path) else {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: input.path, reason: "the declared TLC input directory already exists"
      ))
    }
    do {
      try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
      for file in bundle.files {
        try Data(file.tla.utf8).write(
          to: input.appendingPathComponent("\(file.name).tla"), options: .atomic)
      }
      try Data(cfg.utf8).write(
        to: input.appendingPathComponent("\(bundle.root.name).cfg"), options: .atomic)
      return (
        input.appendingPathComponent("\(bundle.root.name).tla"),
        input.appendingPathComponent("\(bundle.root.name).cfg")
      )
    } catch {
      try? FileManager.default.removeItem(at: input)
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: input.path, reason: redactingSecrets(in: error.localizedDescription)
      ))
    }
  }

  /// Reads an explicitly declared root, configuration, and complete import closure.
  /// The dependency edges define the bundle staged for TLC.
  package static func declaredBundle(
    root: URL,
    configuration: URL,
    imports: [URL] = [],
    dependencies: [TLAModuleBundle.ModuleDependency] = []
  ) throws -> TLAModuleBundle {
    let rootFile = TLAModuleFile(
      name: root.deletingPathExtension().lastPathComponent,
      tla: try readUTF8(root),
      cfg: try readUTF8(configuration)
    )
    let importedFiles = try imports.map { url in
      let module = url.deletingPathExtension().lastPathComponent
      guard FileManager.default.fileExists(atPath: url.path) else {
        let importer = dependencies.first(where: {
          $0.importedModule == module
        })?.importingModule ?? root.deletingPathExtension().lastPathComponent
        throw TLCProcessError.invalidModuleBundle(.missingImportedModule(
          module: module,
          importedBy: "\(importer).tla",
          line: 0,
          expectedFile: url.path
        ))
      }
      return TLAModuleFile(name: module, tla: try readUTF8(url))
    }
    return TLAModuleBundle.external(
      root: rootFile,
      imports: importedFiles,
      dependencies: dependencies
    )
  }

  private static func readUTF8(_ url: URL) throws -> String {
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: url.path, reason: redactingSecrets(in: error.localizedDescription)
      ))
    }
  }

  package func validateReferenceBinding(artifacts: TLCReferenceArtifacts) throws {
    guard sameFile(jar, artifacts.jar) else {
      throw FiniteGraphCaseError.pinMismatch("execution TLC JAR")
    }
    guard sameFile(bridgeJar, artifacts.bridgeBinary) else {
      throw FiniteGraphCaseError.pinMismatch("execution bridge JAR")
    }
  }

  private func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL
      == rhs.resolvingSymlinksInPath().standardizedFileURL
  }

}

package struct TLCProcessResult: Equatable, Sendable {
  package let status: Int32
  package let stdout: String
  package let stderr: String

  package init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

package protocol TLCProcessExecuting: Sendable {
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult
}

package struct SystemTLCProcessExecutor: TLCProcessExecuting {
  package init() {}

  package func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    let input = try request.stageDeclaredBundle()
    try request.validateLaunchBinding(module: input.module, configuration: input.configuration)
    guard let artifacts = request.referenceArtifacts else {
      throw FiniteGraphCaseError.missingArtifact("reference artifacts")
    }
    try request.validateReferenceBinding(artifacts: artifacts)
    let pin = request.finiteGraphCase.pin
    try pin.validate(
      TLCReferenceInspector.inspect(
        artifacts: artifacts, javaExecutable: request.javaExecutable,
        directory: request.workingDirectory
      ))
    let process = try executeProcess(
      executable: request.javaExecutable,
      arguments: request.launchArguments,
      directory: request.workingDirectory,
      timeout: request.timeout,
      environment: request.effectiveEnvironment
    )
    try request.finiteGraphCase.pin.validateReportedTLCBanner(process.stdout + "\n" + process.stderr)
    return process
  }
}

package struct TLCProcessCapture: Sendable {
  package let request: TLCProcessRequest
  package let outcome: TLCExecutionOutcome
  package let graph: GraphRun
  package var unavailableCheckBundle: TLAModuleBundle?

  package init(reading request: TLCProcessRequest, outcome: TLCExecutionOutcome, retainedIn directory: URL) throws {
    let reader = TLCGraphReader(finiteGraphCase: request.finiteGraphCase)
    let stream = try reader.parse(contentsOf: directory.appendingPathComponent("graph-events.jsonl"))
    guard stream.runID == request.runID else {
      throw TLCGraphEventError.invalidRecord(line: 1, reason: "run ID")
    }
    self.request = request
    self.outcome = outcome
    self.graph = try reader.makeGraphRun(stream, outcome: outcome)
  }
}

package struct TLCProcessAdapter: Sendable {
  private let executor: any TLCProcessExecuting

  package init(executor: any TLCProcessExecuting = SystemTLCProcessExecutor()) {
    self.executor = executor
  }

  package func capture(
    _ request: TLCProcessRequest,
    retainingIn directory: URL
  ) throws -> TLCProcessCapture {
    let outcome = try run(request, retainingIn: directory)
    return try TLCProcessCapture(reading: request, outcome: outcome, retainedIn: directory)
  }

  package func run(
    _ request: TLCProcessRequest,
    retainingIn directory: URL
  ) throws -> TLCExecutionOutcome {
    try RetainedFiles.createDirectory(directory, beneath: directory.deletingLastPathComponent())
    try clearTraceOutput(for: request, retainingIn: directory)
    let process: TLCProcessResult
    do {
      process = try executor.execute(request)
    } catch {
      try retain(request, failure: TLCProcessExecutionFailure(error), in: directory)
      throw error
    }
    try retain(request, process: process, in: directory)
    return TLCExecutionOutcome(process: process, invocation: request.invocation)
  }

  private func clearTraceOutput(for request: TLCProcessRequest, retainingIn directory: URL) throws {
    let root = request.workingDirectory.resolvingSymlinksInPath().standardizedFileURL
    let trace = try RetainedFiles.resolve(request.traceOutput, beneath: root)
    let retained = directory.resolvingSymlinksInPath().standardizedFileURL
    let protected = [request.javaExecutable, request.jar, request.bridgeJar, request.graphEvents]
      .map { $0.resolvingSymlinksInPath().standardizedFileURL }
    guard trace != root, trace != retained, !trace.path.hasPrefix(retained.path + "/"),
          !protected.contains(trace) else {
      throw EvidenceFormatError.invalidField(record: request.traceOutput.path, field: "trace output aliases an input or retained output")
    }
    if (try? FileManager.default.destinationOfSymbolicLink(atPath: request.traceOutput.path)) != nil {
      throw EvidenceFormatError.invalidField(record: request.traceOutput.path, field: "trace output is a symbolic link")
    }
    guard FileManager.default.fileExists(atPath: request.traceOutput.path) else { return }
    let values = try request.traceOutput.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw EvidenceFormatError.invalidField(record: request.traceOutput.path, field: "trace output must be a regular file")
    }
    try FileManager.default.removeItem(at: trace)
  }

  private func retain(
    _ request: TLCProcessRequest,
    process: TLCProcessResult? = nil,
    failure: TLCProcessExecutionFailure? = nil,
    in directory: URL
  ) throws {
    let record: [String: Any] = [
      "caseID": request.caseID,
      "runID": request.runID.uuidString.lowercased(),
      "timeout": request.timeout,
      "inputs": bundleInputJSON(request.bundle),
      "configuration": request.bundle.cfg,
      "toolPin": pinJSON(request.finiteGraphCase.pin),
      "invocation": invocationJSON(request: request, process: process, failure: failure)
    ]
    try RetainedFiles.writeJSON(record, to: directory.appendingPathComponent("tlc-process.json"))
    let logs = try RetainedFiles.createDirectory(directory.appendingPathComponent("logs"), beneath: directory)
    if let stdout = process?.stdout ?? failure?.partialStdout {
      try RetainedFiles.writeText(redactingSecrets(in: stdout), to: logs.appendingPathComponent("tlc.stdout.log"))
    }
    if let stderr = process?.stderr ?? failure?.partialStderr {
      try RetainedFiles.writeText(redactingSecrets(in: stderr), to: logs.appendingPathComponent("tlc.stderr.log"))
    }
    if let failure {
      try RetainedFiles.writeText(redactingSecrets(in: failure.message), to: logs.appendingPathComponent("tlc.failure.log"))
    }
    let graphFiles = request.invocation == .finiteGraph ? [(request.graphEvents, "graph-events.jsonl")] : []
    for (source, name) in graphFiles + [(request.traceOutput, "counterexample.json")] {
      guard FileManager.default.fileExists(atPath: source.path) else { continue }
      let destination = directory.appendingPathComponent(name)
      if name == "graph-events.jsonl" {
        let root = request.workingDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = try RetainedFiles.resolve(source, beneath: root)
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let protected = [request.javaExecutable, request.jar, request.bridgeJar, request.traceOutput, destination]
          .map { $0.resolvingSymlinksInPath().standardizedFileURL }
        let inputs = request.inputDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              resolved != root, !protected.contains(resolved),
              resolved != inputs, !resolved.path.hasPrefix(inputs.path + "/") else {
          throw EvidenceFormatError.invalidField(record: source.path, field: "graph output must be a distinct regular working file")
        }
      }
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      if name == "graph-events.jsonl" {
        // The retained file owns the complete stream; later runs can reuse the working path.
        try FileManager.default.moveItem(at: source, to: destination)
      } else {
        try FileManager.default.copyItem(at: source, to: destination)
      }
    }
  }
}

private func invocationJSON(
  request: TLCProcessRequest,
  process: TLCProcessResult?,
  failure: TLCProcessExecutionFailure?
) -> [String: Any] {
  var record: [String: Any] = [
    "arguments": request.launchArguments.map { redactingSecrets(in: $0) }
  ]
  if let process { record["exitStatus"] = process.status }
  if let failure { record["executionError"] = redactingSecrets(in: failure.message) }
  return record
}

private func bundleInputJSON(_ bundle: TLAModuleBundle) -> [[String: String]] {
  var inputs = bundle.files.map {
    ["file": "\($0.name).tla", "sha256": SHA256.hex(Data($0.tla.utf8))]
  }
  if let cfg = bundle.root.cfg {
    inputs.append([
      "file": "\(bundle.root.name).cfg",
      "sha256": SHA256.hex(Data(cfg.utf8))
    ])
  }
  return inputs
}

private func pinJSON(_ pin: TLCReferencePin) -> [String: Any] {
  [
    "tag": pin.tag,
    "commit": pin.commit,
    "jarSHA256": pin.jarSHA256,
    "javaDistribution": pin.javaDistribution,
    "javaVersion": pin.javaVersion,
    "javaArchiveSHA256": pin.javaArchiveSHA256,
    "bridgeClass": pin.bridgeClass,
    "bridgeSourceHashes": pin.bridgeSourceHashes,
    "bridgeBinarySHA256": pin.bridgeBinarySHA256
  ]
}

package enum TLCReferenceInspector {
  package static func inspect(
    artifacts: TLCReferenceArtifacts,
    javaExecutable: URL,
    directory: URL
  )
    throws -> TLCReferenceArtifacts {
    let manifest = try executeProcess(
      executable: URL(fileURLWithPath: "/usr/bin/unzip"),
      arguments: ["-p", artifacts.jar.path, "META-INF/MANIFEST.MF"], directory: directory,
      timeout: 10
    )
    guard manifest.status == 0 else {
      throw FiniteGraphCaseError.pinMismatch("TLC JAR manifest")
    }
    let runtime = try executeProcess(
      executable: javaExecutable, arguments: ["-XshowSettings:properties", "-version"],
      directory: directory, timeout: 10
    )
    guard runtime.status == 0 else { throw FiniteGraphCaseError.pinMismatch("Java runtime") }
    let properties = parseProperties(runtime.stdout + "\n" + runtime.stderr)
    let architecture: String
    switch properties["os.arch"] {
    case "aarch64", "arm64": architecture = "arm64"
    case "amd64", "x86_64": architecture = "x86_64"
    default: throw FiniteGraphCaseError.pinMismatch("Java architecture")
    }
    guard let version = properties["java.runtime.version"], let vendor = properties["java.vendor"]
    else {
      throw FiniteGraphCaseError.pinMismatch("Java runtime properties")
    }
    return TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSources: artifacts.bridgeSources,
      bridgeBinary: artifacts.bridgeBinary,
      jarManifest: manifest.stdout,
      runtime: TLCJavaRuntimeIdentity(
        version: version, vendor: vendor, architecture: architecture, properties: properties)
    )
  }

  private static func parseProperties(_ output: String) -> [String: String] {
    output.split(separator: "\n").reduce(into: [:]) { properties, line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let separator = trimmed.range(of: " = ") else { return }
      properties[String(trimmed[..<separator.lowerBound])] = String(
        trimmed[separator.upperBound...])
    }
  }
}

func executeProcess(
  executable: URL,
  arguments: [String],
  directory: URL,
  timeout: TimeInterval,
  environment: [String: String]? = nil
) throws -> TLCProcessResult {
  let process = Process()
  process.executableURL = executable
  process.currentDirectoryURL = directory
  process.arguments = arguments
  process.environment = environment
  let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(
    at: outputDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: outputDirectory) }
  let stdoutURL = outputDirectory.appendingPathComponent("stdout")
  let stderrURL = outputDirectory.appendingPathComponent("stderr")
  try Data().write(to: stdoutURL)
  try Data().write(to: stderrURL)
  let stdout = try FileHandle(forWritingTo: stdoutURL)
  defer { try? stdout.close() }
  let stderr = try FileHandle(forWritingTo: stderrURL)
  defer { try? stderr.close() }
  // Files need no pipe-draining workers and cannot block waiting for an
  // inherited descriptor to close after the launched process exits.
  process.standardOutput = stdout
  process.standardError = stderr
  let termination = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in termination.signal() }
  do {
    try process.run()
  } catch {
    throw TLCProcessError.failedToStart(error.localizedDescription)
  }
  if termination.wait(timeout: .now() + timeout) == .timedOut {
    process.terminate()
    if termination.wait(timeout: .now() + 0.5) == .timedOut {
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
      _ = termination.wait(timeout: .now() + 0.5)
    }
    throw TLCProcessError.timedOut(
      partialStdout: try String(contentsOf: stdoutURL, encoding: .utf8),
      partialStderr: try String(contentsOf: stderrURL, encoding: .utf8)
    )
  }
  return TLCProcessResult(
    status: process.terminationStatus,
    stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
    stderr: try String(contentsOf: stderrURL, encoding: .utf8)
  )
}

extension TLCProcessRequest {
  package func selecting(
    bundle: TLAModuleBundle,
    work: URL, runID: UUID, invocation: TLCInvocationKind
  ) throws -> TLCProcessRequest {
    let configuration = finiteGraphCase
    let selected = try FiniteGraphCase(id: configuration.id, exploration: configuration.exploration,
      moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)), cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: configuration.arguments, environment: configuration.environment, pin: configuration.pin,
      renderedActions: configuration.renderedActions, symmetryGenerators: configuration.symmetryGroup)
    return TLCProcessRequest(javaExecutable: javaExecutable, jar: jar,
      bridgeJar: bridgeJar, bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      workingDirectory: work, finiteGraphCase: selected, runID: runID, timeout: timeout,
      invocation: invocation, referenceArtifacts: referenceArtifacts)
  }

}
