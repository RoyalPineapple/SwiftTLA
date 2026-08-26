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
  package let arguments: [String]
  package let expectedCase: FiniteGraphCase
  package let runID: UUID
  package let timeout: TimeInterval
  package let traceMode: TLCTraceMode
  package let referencePin: TLCReferencePin?
  package let referenceArtifacts: TLCReferenceArtifacts?

  package init(
    javaExecutable: URL,
    jar: URL,
    bridgeClasses: URL,
    bundle: TLAModuleBundle,
    graphEvents: URL,
    traceOutput: URL,
    workingDirectory: URL,
    arguments: [String],
    expectedCase: FiniteGraphCase,
    runID: UUID,
    timeout: TimeInterval = 60,
    traceMode: TLCTraceMode = .none,
    referencePin: TLCReferencePin? = nil,
    referenceArtifacts: TLCReferenceArtifacts? = nil
  ) {
    self.javaExecutable = javaExecutable
    self.jar = jar
    self.bridgeClasses = bridgeClasses
    self.bundle = bundle
    self.graphEvents = graphEvents
    self.traceOutput = traceOutput
    self.workingDirectory = workingDirectory
    self.arguments = arguments
    self.expectedCase = expectedCase
    self.runID = runID
    self.timeout = timeout
    self.traceMode = traceMode
    self.referencePin = referencePin
    self.referenceArtifacts = referenceArtifacts
  }

  package var caseID: String { expectedCase.id }

  package var effectiveEnvironment: [String: String] { expectedCase.environment }
  package var moduleFileName: String { "\(bundle.root.name).tla" }
  package var configurationFileName: String { "\(bundle.root.name).cfg" }

  package func commandArguments(
    module: URL,
    configuration: URL
  ) throws -> [String] {
    return [
      "-Dswifttla.tlc.graph.path=\(graphEvents.path)",
      "-Dswifttla.tlc.graph.provenance=\(try provenanceJSON())",
      "-Dswifttla.tlc.graph.run-id=\(runID.uuidString.lowercased())",
      "-Dswifttla.tlc.graph.case-id=\(caseID)",
      "-cp", "\(jar.path):\(bridgeClasses.path)",
      "tlc2.TLC", "-dump", "class,org.swifttla.conformance.LosslessStateWriter"
    ] + traceArguments(traceMode) + arguments + ["-config", configuration.path, module.path]
  }

  package func validateLaunchBinding(module: URL, configuration: URL) throws {
    try expectedCase.validateLaunch(
      module: module, configuration: configuration, arguments: arguments, caseID: caseID
    )
  }

  /// Validates the declared module closure before TLC launch.
  package func validateDeclaredBundle() throws {
    do {
      try bundle.validateDeclaredClosure()
    } catch {
      if let error = error as? TLCModuleBundleError {
        throw TLCProcessError.invalidModuleBundle(error)
      }
      if case TLAModuleBundleIntegrityError.missingModule(let dependency, let importedBy, let line) = error {
        throw TLCProcessError.invalidModuleBundle(.missingImportedModule(
          module: dependency,
          importedBy: "\(importedBy).tla",
          line: line,
          expectedFile: "\(dependency).tla"
        ))
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
    let input = workingDirectory.appendingPathComponent(
      "input-\(runID.uuidString.lowercased())-\(traceMode)", isDirectory: true)
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

  /// Reads an explicitly declared root, configuration, and import list.
  /// This is the only URL-to-bundle boundary; it never enumerates a directory.
  package static func declaredBundle(
    root: URL,
    configuration: URL,
    imports: [URL] = []
  ) throws -> TLAModuleBundle {
    do {
      let rootFile = TLAModuleFile(
        name: root.deletingPathExtension().lastPathComponent,
        tla: try String(contentsOf: root, encoding: .utf8),
        cfg: try String(contentsOf: configuration, encoding: .utf8)
      )
      let importedFiles = try imports.map { url in
        TLAModuleFile(
          name: url.deletingPathExtension().lastPathComponent,
          tla: try String(contentsOf: url, encoding: .utf8)
        )
      }
      return TLAModuleBundle.external(root: rootFile, imports: importedFiles)
    } catch {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: root.path, reason: redactingSecrets(in: error.localizedDescription)
      ))
    }
  }

  package func validateReferenceBinding(pin: TLCReferencePin, artifacts: TLCReferenceArtifacts)
    throws {
    guard expectedCase.pin == pin else {
      throw FiniteGraphCaseError.pinMismatch("declared case reference pin")
    }
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

  private func provenanceJSON() throws -> String {
    let pin = expectedCase.pin
    let provenance: [String: Any] = [
      "tlcTag": pin.tag, "tlcCommit": pin.commit, "tlcJarSha256": pin.jarSHA256,
      "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
      "javaArchiveSha256": pin.javaArchiveSHA256, "bridgeClass": pin.bridgeClass,
      "bridgeSourceSha256": pin.bridgeSourceSHA256, "bridgeBinarySha256": pin.bridgeBinarySHA256,
      "moduleSha256": expectedCase.moduleSHA256, "cfgSha256": expectedCase.cfgSHA256,
      "arguments": expectedCase.arguments, "argumentsSha256": expectedCase.argumentsSHA256,
      "workers": expectedCase.workers, "fingerprintPolynomial": expectedCase.fingerprintPolynomial,
      "deadlock": expectedCase.deadlock, "os": expectedCase.operatingSystem,
      "architecture": expectedCase.architecture, "environment": expectedCase.environment
    ]
    let data = try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
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
  private let validatesReferences: Bool

  package init(validatesReferences: Bool = true) {
    self.validatesReferences = validatesReferences
  }

  package func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    let input = try request.stageDeclaredBundle()
    try request.validateLaunchBinding(module: input.module, configuration: input.configuration)
    if validatesReferences {
      guard let pin = request.referencePin, let artifacts = request.referenceArtifacts else {
        throw FiniteGraphCaseError.missingArtifact("reference pin and artifacts")
      }
      try request.validateReferenceBinding(pin: pin, artifacts: artifacts)
      try pin.validate(
        TLCReferenceInspector.inspect(
          artifacts: artifacts, javaExecutable: request.javaExecutable,
          directory: request.workingDirectory
        ))
    }
    let result = try executeProcess(
      executable: request.javaExecutable,
      arguments: try request.commandArguments(module: input.module, configuration: input.configuration),
      directory: request.workingDirectory,
      timeout: request.timeout,
      environment: request.effectiveEnvironment
    )
    try request.expectedCase.pin.validateReportedTLCBanner(result.stdout + "\n" + result.stderr)
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
    try RetainedEvidence.createDirectory(directory, beneath: directory.deletingLastPathComponent())
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
    let reader = TLCGraphReader(expectedCase: request.expectedCase)
    let stream = try reader.parse(graphEvents)
    guard stream.runID == request.runID else {
      throw TLCGraphEventError.invalidRecord(line: 1, reason: "run ID")
    }
    return TLCProcessCapture(
      run: run,
      graph: try reader.makeCompletedGraphRun(stream, result: run.primary)
    )
  }

  package func retain(request: TLCProcessRequest, in directory: URL) throws {
    try writeProcessRecord(request: request, results: [:], failures: [:], to: directory)
    try retainRawArtifacts(from: request, in: directory)
  }

  private func retain(
    _ run: TLCProcessRun,
    request: TLCProcessRequest,
    in directory: URL
  ) throws {
    var results: [TLCInvocationPhase: TLCProcessResult] = [.primary: run.primary]
    if let trace = run.trace { results[.trace] = trace }
    try writeProcessRecord(request: request, results: results, failures: [:], to: directory)
    let logs = try RetainedEvidence.createDirectory(
      directory.appendingPathComponent("logs"), beneath: directory)
    try retain(run.primary, phase: .primary, in: logs)
    if let trace = run.trace { try retain(trace, phase: .trace, in: logs) }
    try retainRawArtifacts(from: request, in: directory)
  }

  private func retain(
    _ error: Error,
    request: TLCProcessRequest,
    in directory: URL
  ) throws {
    let lifecycle = processLifecycle(for: error)
    try writeProcessRecord(
      request: request, results: lifecycle.results, failures: lifecycle.failures, to: directory)
    let logs = try RetainedEvidence.createDirectory(
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
    try retainRawArtifacts(from: request, in: directory)
  }

  private func retainRawArtifacts(from request: TLCProcessRequest, in directory: URL) throws {
    let artifacts = [
      (request.graphEvents, "graph-events.jsonl"),
      (traceGraphEvents(for: request.graphEvents), "graph-events.trace.jsonl"),
      (request.traceOutput, "counterexample.json")
    ]
    var availability: [String: Bool] = [:]
    for (source, name) in artifacts {
      let destination = directory.appendingPathComponent(name)
      let exists = FileManager.default.fileExists(atPath: source.path)
      availability[name] = exists
      if exists {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try RetainedEvidence.copy(source, to: destination)
      }
    }
    try RetainedEvidence.writeJSON(availability, to: directory.appendingPathComponent("raw-artifacts.json"))
  }

  private func traceRequest(_ request: TLCProcessRequest) -> TLCProcessRequest {
    TLCProcessRequest(
      javaExecutable: request.javaExecutable, jar: request.jar,
      bridgeClasses: request.bridgeClasses,
      bundle: request.bundle,
      graphEvents: traceGraphEvents(for: request.graphEvents),
      traceOutput: request.traceOutput,
      workingDirectory: request.workingDirectory, arguments: request.arguments,
      expectedCase: request.expectedCase, runID: request.runID,
      timeout: request.timeout, traceMode: .dumpJSON, referencePin: request.referencePin,
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
    let phases: [TLCInvocationPhase] = [.primary, .trace]
    var record: [String: Any] = [
      "request": processRequestJSON(request),
      "attempted": phases.compactMap { phase in
        results[phase] != nil || failures[phase] != nil ? phase.rawValue : nil
      }
    ]
    for phase in phases {
      if let result = results[phase] {
        record[phase.rawValue] = processJSON(result)
      } else if let failure = failures[phase] {
        record[phase.rawValue] = ["executionError": redactingSecrets(in: failure.message)]
      } else {
        record[phase.rawValue] = NSNull()
      }
    }
    try RetainedEvidence.writeJSON(record, to: directory.appendingPathComponent("tlc-process.json"))
  }

  private func retain(_ result: TLCProcessResult, phase: TLCInvocationPhase, in directory: URL) throws {
    try RetainedEvidence.writeText(
      redactingSecrets(in: result.stdout),
      to: directory.appendingPathComponent(phase.stdoutLog)
    )
    try RetainedEvidence.writeText(
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
      try RetainedEvidence.writeText(
        redactingSecrets(in: stdout),
        to: directory.appendingPathComponent(phase.stdoutLog)
      )
      try RetainedEvidence.writeText(
        redactingSecrets(in: stderr),
        to: directory.appendingPathComponent(phase.stderrLog)
      )
    } else {
      try RetainedEvidence.writeText(
        redactingSecrets(in: failure.message),
        to: directory.appendingPathComponent("tlc.\(phase.rawValue).failure.log")
      )
    }
  }

  private func traceGraphEvents(for primary: URL) -> URL {
    return primary.deletingPathExtension().appendingPathExtension("trace.jsonl")
  }
}

func processJSON(_ result: TLCProcessResult) -> [String: Any] {
  [
    "status": result.status,
    "isViolation": result.isViolation,
    "reportedExhaustiveCompletion": result.reportedExhaustiveCompletion
  ]
}

private func processRequestJSON(_ request: TLCProcessRequest) -> [String: Any] {
  [
    "case": finiteGraphCaseJSON(request.expectedCase),
    "toolchain": toolchainJSON(request),
    "arguments": request.arguments,
    "bundle": [
      "root": request.bundle.root.name,
      "files": request.bundle.files.map {
        ["name": $0.name, "tlaSHA256": SHA256.hex(Data($0.tla.utf8))]
      }
    ],
    "module": request.moduleFileName,
    "configuration": request.configurationFileName,
    "timeout": request.timeout
  ]
}

private func finiteGraphCaseJSON(_ finiteGraphCase: FiniteGraphCase) -> [String: Any] {
  let record: [String: Any] = [
    "id": finiteGraphCase.id,
    "moduleSHA256": finiteGraphCase.moduleSHA256,
    "cfgSHA256": finiteGraphCase.cfgSHA256,
    "arguments": finiteGraphCase.arguments,
    "argumentsSHA256": finiteGraphCase.argumentsSHA256,
    "workers": finiteGraphCase.workers,
    "fingerprintPolynomial": finiteGraphCase.fingerprintPolynomial,
    "deadlock": finiteGraphCase.deadlock,
    "operatingSystem": finiteGraphCase.operatingSystem,
    "architecture": finiteGraphCase.architecture,
    "environment": finiteGraphCase.environment,
    "pin": pinJSON(finiteGraphCase.pin),
    "renderedActions": finiteGraphCase.renderedActions.map { call in
      [
        "sourceName": call.sourceName,
        "arguments": call.arguments.map(\.description),
        "renderedName": call.renderedName
      ]
    }
  ]
  return record
}

private func toolchainJSON(_ request: TLCProcessRequest) -> [String: Any] {
  var record: [String: Any] = ["declaredPin": pinJSON(request.expectedCase.pin)]
  if let referencePin = request.referencePin {
    record["referencePin"] = pinJSON(referencePin)
  }
  if let artifacts = request.referenceArtifacts {
    record["referenceArtifacts"] = [
      "jar": artifacts.jar.path,
      "javaArchive": artifacts.javaArchive.path,
      "bridgeSource": artifacts.bridgeSource.path,
      "bridgeBinary": artifacts.bridgeBinary.path,
      "jarManifest": artifacts.jarManifest,
      "runtime": [
        "version": artifacts.runtime.version,
        "vendor": artifacts.runtime.vendor,
        "architecture": artifacts.runtime.architecture,
        "properties": artifacts.runtime.properties
      ]
    ]
  }
  return record
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

private func executeProcess(
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
