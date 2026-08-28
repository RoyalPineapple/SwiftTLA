import Darwin
import Foundation
import os
import SwiftTLA

package enum TLCTraceMode: Equatable, Sendable {
  case none
  case dumpJSON
}

enum TLCInvocationPhase: String, Hashable {
  case primary
  case trace

  var stdoutLog: String {
    self == .primary ? "tlc.stdout.log" : "tlc.\(rawValue).stdout.log"
  }

  var stderrLog: String {
    self == .primary ? "tlc.stderr.log" : "tlc.\(rawValue).stderr.log"
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
  case traceCaptureFailed(completed: TLCProcessRun, failed: TLCProcessResult)
  case traceCaptureExecutionFailed(completed: TLCProcessRun, error: TLCProcessExecutionFailure)
}

package struct TLCProcessRequest: Equatable, Sendable {
  package let javaExecutable: URL
  package let jar: URL
  package let bridgeClasses: URL
  /// The only TLA+ sources that this TLC invocation may receive.
  package let bundle: TLAModuleBundle
  package let graphEvents: URL
  package let traceOutput: URL
  package let workingDirectory: URL
  package let finiteGraphCase: FiniteGraphCase
  package let runID: UUID
  package let timeout: TimeInterval
  package let traceMode: TLCTraceMode
  package let referenceArtifacts: TLCReferenceArtifacts?

  package init(
    javaExecutable: URL,
    jar: URL,
    bridgeClasses: URL,
    bundle: TLAModuleBundle,
    graphEvents: URL,
    traceOutput: URL,
    workingDirectory: URL,
    finiteGraphCase: FiniteGraphCase,
    runID: UUID,
    timeout: TimeInterval = 60,
    traceMode: TLCTraceMode = .none,
    referenceArtifacts: TLCReferenceArtifacts? = nil
  ) {
    self.javaExecutable = javaExecutable
    self.jar = jar
    self.bridgeClasses = bridgeClasses
    self.bundle = bundle
    self.graphEvents = graphEvents
    self.traceOutput = traceOutput
    self.workingDirectory = workingDirectory
    self.finiteGraphCase = finiteGraphCase
    self.runID = runID
    self.timeout = timeout
    self.traceMode = traceMode
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

  private var inputDirectory: URL {
    workingDirectory.appendingPathComponent(
      "input-\(runID.uuidString.lowercased())-\(traceMode)", isDirectory: true)
  }

  private func commandArguments(
    module: URL,
    configuration: URL
  ) -> [String] {
    return [
      "-Dswifttla.tlc.graph.path=\(graphEvents.path)",
      "-Dswifttla.tlc.graph.run-id=\(runID.uuidString.lowercased())",
      "-Dswifttla.tlc.graph.case-id=\(caseID)",
      "-cp", "\(jar.path):\(bridgeClasses.path)",
      "tlc2.TLC", "-dump", "class,org.swifttla.conformance.LosslessStateWriter"
    ] + traceArguments(traceMode) + finiteGraphCase.arguments + ["-config", configuration.path, module.path]
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
    let pin = finiteGraphCase.pin
    guard sameFile(jar, artifacts.jar) else {
      throw FiniteGraphCaseError.pinMismatch("execution TLC JAR")
    }
    let bridgeClassFile =
      bridgeClasses
      .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
      .appendingPathExtension("class")
    guard sameFile(bridgeClassFile, artifacts.bridgeBinary) else {
      throw FiniteGraphCaseError.pinMismatch("execution bridge class")
    }
  }

  private func traceArguments(_ mode: TLCTraceMode) -> [String] {
    switch mode {
    case .none: []
    case .dumpJSON: ["-dumpTrace", "json", traceOutput.path]
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

  package var isViolation: Bool {
    let output = stdout + "\n" + stderr
    return output.localizedCaseInsensitiveContains("error:")
      || output.localizedCaseInsensitiveContains("violation")
  }

  package var reportedExhaustiveCompletion: Bool {
    status == 0
      && (stdout + "\n" + stderr).contains("Model checking completed. No error has been found.")
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
    let result = try executeProcess(
      executable: request.javaExecutable,
      arguments: request.launchArguments,
      directory: request.workingDirectory,
      timeout: request.timeout,
      environment: request.effectiveEnvironment
    )
    try request.finiteGraphCase.pin.validateReportedTLCBanner(result.stdout + "\n" + result.stderr)
    return result
  }
}

package struct TLCProcessRun: Equatable, Sendable {
  package let primary: TLCProcessResult
  package let trace: TLCProcessResult?
}

package struct TLCProcessCapture: Sendable {
  package let run: TLCProcessRun
  package let graph: CompletedGraphRun
}

package struct TLCProcessAdapter: Sendable {
  private let executor: any TLCProcessExecuting

  package init(executor: any TLCProcessExecuting = SystemTLCProcessExecutor()) {
    self.executor = executor
  }

  private func run(_ request: TLCProcessRequest) throws -> TLCProcessRun {
    let primary = try executor.execute(request)
    guard primary.isViolation else {
      return TLCProcessRun(primary: primary, trace: nil)
    }

    let trace: TLCProcessResult
    do {
      trace = try executor.execute(traceRequest(request))
    } catch {
      throw TLCProcessError.traceCaptureExecutionFailed(
        completed: TLCProcessRun(primary: primary, trace: nil),
        error: TLCProcessExecutionFailure(error))
    }
    guard trace.isViolation || trace.status == 0 else {
      throw TLCProcessError.traceCaptureFailed(
        completed: TLCProcessRun(primary: primary, trace: nil), failed: trace)
    }
    return TLCProcessRun(primary: primary, trace: trace)
  }

  package func capture(
    _ request: TLCProcessRequest,
    retainingIn directory: URL
  ) throws -> TLCProcessCapture {
    try RetainedFiles.createDirectory(directory, beneath: directory.deletingLastPathComponent())
    let run: TLCProcessRun
    do {
      run = try self.run(request)
    } catch {
      try retain(error, request: request, in: directory)
      throw error
    }
    try retain(run, request: request, in: directory)
    return try capture(run, request: request)
  }

  private func capture(_ run: TLCProcessRun, request: TLCProcessRequest) throws
    -> TLCProcessCapture {
    let graphEvents = try Data(contentsOf: request.graphEvents)
    let reader = TLCGraphReader(finiteGraphCase: request.finiteGraphCase)
    let stream = try reader.parse(graphEvents)
    guard stream.runID == request.runID else {
      throw TLCGraphEventError.invalidRecord(line: 1, reason: "run ID")
    }
    return TLCProcessCapture(
      run: run,
      graph: try reader.makeCompletedGraphRun(stream, result: run.primary)
    )
  }

  private func retain(
    _ run: TLCProcessRun,
    request: TLCProcessRequest,
    in directory: URL
  ) throws {
    var results: [TLCInvocationPhase: TLCProcessResult] = [.primary: run.primary]
    if let trace = run.trace { results[.trace] = trace }
    try writeProcessRecord(request: request, results: results, failures: [:], to: directory)
    let logs = try RetainedFiles.createDirectory(
      directory.appendingPathComponent("logs"), beneath: directory)
    try retain(run.primary, phase: .primary, in: logs)
    if let trace = run.trace { try retain(trace, phase: .trace, in: logs) }
    try retainRawFiles(from: request, in: directory)
  }

  private func retain(
    _ error: Error,
    request: TLCProcessRequest,
    in directory: URL
  ) throws {
    let lifecycle = processLifecycle(for: error)
    try writeProcessRecord(
      request: request, results: lifecycle.results, failures: lifecycle.failures, to: directory)
    let logs = try RetainedFiles.createDirectory(
      directory.appendingPathComponent("logs"), beneath: directory)
    switch error {
    case TLCProcessError.traceCaptureFailed(let completed, let failed):
      try retain(completed.primary, phase: .primary, in: logs)
      try retain(failed, phase: .trace, in: logs)
    case TLCProcessError.traceCaptureExecutionFailed(let completed, let failure):
      try retain(completed.primary, phase: .primary, in: logs)
      try retain(failure, phase: .trace, in: logs)
    default:
      try retain(TLCProcessExecutionFailure(error), phase: .primary, in: logs)
    }
    try retainRawFiles(from: request, in: directory)
  }

  private func retainRawFiles(from request: TLCProcessRequest, in directory: URL) throws {
    let artifacts = [
      (request.graphEvents, "graph-events.jsonl"),
      (traceGraphEvents(for: request.graphEvents), "graph-events.trace.jsonl"),
      (request.traceOutput, "counterexample.json")
    ]
    for (source, name) in artifacts {
      let destination = directory.appendingPathComponent(name)
      let exists = FileManager.default.fileExists(atPath: source.path)
      if exists {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
      }
    }
  }

  private func traceRequest(_ request: TLCProcessRequest) -> TLCProcessRequest {
    TLCProcessRequest(
      javaExecutable: request.javaExecutable, jar: request.jar,
      bridgeClasses: request.bridgeClasses,
      bundle: request.bundle,
      graphEvents: traceGraphEvents(for: request.graphEvents),
      traceOutput: request.traceOutput,
      workingDirectory: request.workingDirectory,
      finiteGraphCase: request.finiteGraphCase, runID: request.runID,
      timeout: request.timeout, traceMode: .dumpJSON,
      referenceArtifacts: request.referenceArtifacts
    )
  }

  private func processLifecycle(
    for error: Error
  ) -> (
    results: [TLCInvocationPhase: TLCProcessResult],
    failures: [TLCInvocationPhase: TLCProcessExecutionFailure]
  ) {
    switch error {
    case TLCProcessError.traceCaptureFailed(let completed, let failed):
      return ([.primary: completed.primary, .trace: failed], [:])
    case TLCProcessError.traceCaptureExecutionFailed(let completed, let failure):
      return ([.primary: completed.primary], [.trace: failure])
    default:
      return ([:], [.primary: TLCProcessExecutionFailure(error)])
    }
  }

  private func writeProcessRecord(
    request: TLCProcessRequest,
    results: [TLCInvocationPhase: TLCProcessResult],
    failures: [TLCInvocationPhase: TLCProcessExecutionFailure],
    to directory: URL
  ) throws {
    var record: [String: Any] = [
      "caseID": request.caseID,
      "runID": request.runID.uuidString.lowercased(),
      "timeout": request.timeout,
      "inputs": bundleInputJSON(request.bundle),
      "toolPin": pinJSON(request.finiteGraphCase.pin),
      TLCInvocationPhase.primary.rawValue: invocationJSON(
        request: request,
        result: results[.primary],
        failure: failures[.primary])
    ]
    if results[.trace] != nil || failures[.trace] != nil {
      record[TLCInvocationPhase.trace.rawValue] = invocationJSON(
        request: traceRequest(request),
        result: results[.trace],
        failure: failures[.trace])
    }
    try RetainedFiles.writeJSON(record, to: directory.appendingPathComponent("tlc-process.json"))
  }

  private func retain(_ result: TLCProcessResult, phase: TLCInvocationPhase, in directory: URL) throws {
    try RetainedFiles.writeText(
      redactingSecrets(in: result.stdout),
      to: directory.appendingPathComponent(phase.stdoutLog)
    )
    try RetainedFiles.writeText(
      redactingSecrets(in: result.stderr),
      to: directory.appendingPathComponent(phase.stderrLog)
    )
  }

  private func retain(
    _ failure: TLCProcessExecutionFailure,
    phase: TLCInvocationPhase,
    in directory: URL
  ) throws {
    if let stdout = failure.partialStdout, let stderr = failure.partialStderr {
      try RetainedFiles.writeText(
        redactingSecrets(in: stdout),
        to: directory.appendingPathComponent(phase.stdoutLog)
      )
      try RetainedFiles.writeText(
        redactingSecrets(in: stderr),
        to: directory.appendingPathComponent(phase.stderrLog)
      )
    } else {
      try RetainedFiles.writeText(
        redactingSecrets(in: failure.message),
        to: directory.appendingPathComponent("tlc.\(phase.rawValue).failure.log")
      )
    }
  }

  private func traceGraphEvents(for primary: URL) -> URL {
    return primary.deletingPathExtension().appendingPathExtension("trace.jsonl")
  }
}

private func invocationJSON(
  request: TLCProcessRequest,
  result: TLCProcessResult?,
  failure: TLCProcessExecutionFailure?
) -> [String: Any] {
  var record: [String: Any] = [
    "arguments": request.launchArguments.map { redactingSecrets(in: $0) }
  ]
  if let result { record["exitStatus"] = result.status }
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

private func pinJSON(_ pin: TLCReferencePin) -> [String: String] {
  [
    "tag": pin.tag,
    "commit": pin.commit,
    "jarSHA256": pin.jarSHA256,
    "javaDistribution": pin.javaDistribution,
    "javaVersion": pin.javaVersion,
    "javaArchiveSHA256": pin.javaArchiveSHA256,
    "bridgeClass": pin.bridgeClass,
    "bridgeSourceSHA256": pin.bridgeSourceSHA256,
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
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
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

package func executeProcess(
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
  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe
  let outputGroup = DispatchGroup()
  let output = ProcessOutputBuffers()
  outputGroup.enter()
  DispatchQueue.global().async {
    drain(stdoutPipe.fileHandleForReading, into: output.appendStdout)
    outputGroup.leave()
  }
  outputGroup.enter()
  DispatchQueue.global().async {
    drain(stderrPipe.fileHandleForReading, into: output.appendStderr)
    outputGroup.leave()
  }
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
    try? stdoutPipe.fileHandleForReading.close()
    try? stderrPipe.fileHandleForReading.close()
    _ = outputGroup.wait(timeout: .now() + 0.5)
    throw TLCProcessError.timedOut(
      partialStdout: String(data: output.stdout, encoding: .utf8) ?? "<non-UTF-8 output>",
      partialStderr: String(data: output.stderr, encoding: .utf8) ?? "<non-UTF-8 output>"
    )
  }
  try? stdoutPipe.fileHandleForWriting.close()
  try? stderrPipe.fileHandleForWriting.close()
  _ = outputGroup.wait(timeout: .now() + 10)
  return TLCProcessResult(
    status: process.terminationStatus,
    stdout: String(data: output.stdout, encoding: .utf8) ?? "<non-UTF-8 output>",
    stderr: String(data: output.stderr, encoding: .utf8) ?? "<non-UTF-8 output>"
  )
}

private func drain(_ handle: FileHandle, into append: (Data) -> Void) {
  while true {
    let data = handle.availableData
    guard !data.isEmpty else { return }
    append(data)
  }
}

private final class ProcessOutputBuffers: Sendable {
  private let stdoutBuffer = OSAllocatedUnfairLock(initialState: Data())
  private let stderrBuffer = OSAllocatedUnfairLock(initialState: Data())

  var stdout: Data { stdoutBuffer.withLock { $0 } }
  var stderr: Data { stderrBuffer.withLock { $0 } }

  func appendStdout(_ data: Data) { stdoutBuffer.withLock { $0.append(data) } }
  func appendStderr(_ data: Data) { stderrBuffer.withLock { $0.append(data) } }
}
