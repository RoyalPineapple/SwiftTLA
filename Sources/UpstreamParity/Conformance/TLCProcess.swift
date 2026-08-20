import Darwin
import Foundation
import os
import SwiftTLA

public enum TLCTraceMode: Equatable, Sendable {
  case none
  case dumpJSON
  case loadJSON
}

public enum TLCReplayPolicy: Equatable, Sendable {
  case none
  case required
}

public struct TLCProcessExecutionFailure: Equatable, Sendable {
  public let message: String
  public let partialStdout: String?
  public let partialStderr: String?

  public init(_ error: Error) {
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
public enum TLCModuleBundleError: Error, Equatable, Sendable {
  case unreadableModule(path: String, reason: String)
  case missingImportedModule(
    module: String,
    importedBy: String,
    line: Int,
    expectedFile: String
  )
}

public indirect enum TLCProcessError: Error, Equatable, Sendable {
  case timedOut(partialStdout: String, partialStderr: String)
  case failedToStart(String)
  case invalidModuleBundle(TLCModuleBundleError)
  case requiredReplayFailed(completed: TLCProcessRun, failed: TLCProcessResult)
  case traceCaptureFailed(completed: TLCProcessRun, failed: TLCProcessResult)
  case requiredReplayExecutionFailed(completed: TLCProcessRun, error: TLCProcessExecutionFailure)
  case traceCaptureExecutionFailed(completed: TLCProcessRun, error: TLCProcessExecutionFailure)
}

public struct TLCProcessRequest: Equatable, Sendable {
  public let javaExecutable: URL
  public let jar: URL
  public let bridgeClasses: URL
  /// The only TLA+ sources that this TLC invocation may receive.
  public let bundle: TLAModuleBundle
  public let graphEvents: URL
  public let traceOutput: URL
  public let replayInput: URL
  public let workingDirectory: URL
  public let arguments: [String]
  public let expectedCase: CoreConformanceCase
  public let runID: UUID
  public let timeout: TimeInterval
  public let traceMode: TLCTraceMode
  public let referencePin: TLCReferencePin?
  public let referenceArtifacts: TLCReferenceArtifacts?

  public init(
    javaExecutable: URL,
    jar: URL,
    bridgeClasses: URL,
    bundle: TLAModuleBundle,
    graphEvents: URL,
    traceOutput: URL,
    replayInput: URL,
    workingDirectory: URL,
    arguments: [String],
    expectedCase: CoreConformanceCase,
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
    self.replayInput = replayInput
    self.workingDirectory = workingDirectory
    self.arguments = arguments
    self.expectedCase = expectedCase
    self.runID = runID
    self.timeout = timeout
    self.traceMode = traceMode
    self.referencePin = referencePin
    self.referenceArtifacts = referenceArtifacts
  }

  public var caseID: String { expectedCase.id }

  public var effectiveEnvironment: [String: String] { expectedCase.environment }
  public var moduleFileName: String { "\(bundle.root.name).tla" }
  public var configurationFileName: String { "\(bundle.root.name).cfg" }

  public func commandArguments(
    module: URL,
    configuration: URL,
    traceMode: TLCTraceMode? = nil
  ) throws -> [String] {
    let mode = traceMode ?? self.traceMode
    return [
      "-Dswifttla.tlc.graph.path=\(graphEvents.path)",
      "-Dswifttla.tlc.graph.provenance=\(try provenanceJSON())",
      "-Dswifttla.tlc.graph.run-id=\(runID.uuidString.lowercased())",
      "-Dswifttla.tlc.graph.case-id=\(caseID)",
      "-cp", "\(jar.path):\(bridgeClasses.path)",
      "tlc2.TLC", "-dump", "class,org.swifttla.conformance.LosslessStateWriter"
    ] + traceArguments(mode) + arguments + ["-config", configuration.path, module.path]
  }

  public func validateLaunchBinding(module: URL, configuration: URL) throws {
    try expectedCase.validateLaunch(
      module: module, configuration: configuration, arguments: arguments, caseID: caseID
    )
  }

  /// Checks post-render bundle integrity before TLC launch.
  ///
  /// This protects the external boundary from incomplete staged files. It does
  /// not resolve imports or provide compiler-linking diagnostics.
  public func validateRenderedBundleIntegrity() throws {
    do {
      try bundle.validateRenderedBundleIntegrity(standardModules: referencePin?.availableStandardModules)
    } catch {
      if case TLAModuleBundleIntegrityError.missingModule(let dependency, let importedBy, let line) = error {
        throw TLCProcessError.invalidModuleBundle(.missingImportedModule(
          module: dependency,
          importedBy: "\(importedBy).tla",
          line: line,
          expectedFile: "\(dependency).tla"
        ))
      }
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: bundle.root.name + ".tla", reason: sanitized(error.localizedDescription)
      ))
    }
  }

  /// Writes exactly the declared bundle to a fresh directory for one TLC invocation.
  /// Nothing else in the source checkout can become an accidental TLC import.
  public func stageDeclaredBundle() throws -> (module: URL, configuration: URL) {
    guard let cfg = bundle.root.cfg else {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: bundle.root.name + ".cfg", reason: "the declared root has no TLC configuration"
      ))
    }
    try validateRenderedBundleIntegrity()
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
        path: input.path, reason: sanitized(error.localizedDescription)
      ))
    }
  }

  /// Reads an explicitly declared root, configuration, and import list.
  /// This is the only URL-to-bundle boundary; it never enumerates a directory.
  public static func declaredBundle(
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
      return TLAModuleBundle.untrusted(root: rootFile, imports: importedFiles)
    } catch {
      throw TLCProcessError.invalidModuleBundle(.unreadableModule(
        path: root.path, reason: sanitized(error.localizedDescription)
      ))
    }
  }

  public func validateReferenceBinding(pin: TLCReferencePin, artifacts: TLCReferenceArtifacts)
    throws {
    guard expectedCase.pin == pin else {
      throw CoreConformanceCaseError.pinMismatch("declared case reference pin")
    }
    guard sameFile(jar, artifacts.jar) else {
      throw CoreConformanceCaseError.pinMismatch("execution TLC JAR")
    }
    let bridgeClassFile =
      bridgeClasses
      .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
      .appendingPathExtension("class")
    guard sameFile(bridgeClassFile, artifacts.bridgeBinary) else {
      throw CoreConformanceCaseError.pinMismatch("execution bridge class")
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
    case .loadJSON: ["-loadTrace", "json", replayInput.path]
    }
  }

  private func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL
      == rhs.resolvingSymlinksInPath().standardizedFileURL
  }

  public static let fixture = Self(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
    bundle: .untrusted(root: TLAModuleFile(name: "Fixture", tla: "---- MODULE Fixture ----", cfg: "SPECIFICATION Spec")),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/counterexample.json"),
    replayInput: URL(fileURLWithPath: "/tmp/counterexample.json"),
    workingDirectory: URL(fileURLWithPath: "/tmp"),
    arguments: ["-workers", "1", "-fp", "1"],
    expectedCase: try! CoreConformanceCase(
      id: "fixture", moduleSHA256: String(repeating: "c", count: 64),
      cfgSHA256: String(repeating: "d", count: 64),
      arguments: ["-workers", "1", "-fp", "1"],
      argumentsSHA256: CoreConformanceCase.argumentsDigest(["-workers", "1", "-fp", "1"]),
      workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
      architecture: "arm64", environment: [:], pin: .fixture
    ),
    runID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  )
}

public struct TLCProcessResult: Equatable, Sendable {
  public let status: Int32
  public let stdout: String
  public let stderr: String

  public init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }

  public var isViolation: Bool {
    let output = stdout + "\n" + stderr
    return output.localizedCaseInsensitiveContains("error:")
      || output.localizedCaseInsensitiveContains("violation")
  }

  public var reportedExhaustiveCompletion: Bool {
    status == 0
      && (stdout + "\n" + stderr).contains("Model checking completed. No error has been found.")
  }
}

public protocol TLCProcessExecuting: Sendable {
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult
}

public struct SystemTLCProcessExecutor: TLCProcessExecuting {
  private let validatesReferences: Bool

  public init(validatesReferences: Bool = true) {
    self.validatesReferences = validatesReferences
  }

  public func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    let input = try request.stageDeclaredBundle()
    try request.validateLaunchBinding(module: input.module, configuration: input.configuration)
    if validatesReferences {
      guard let pin = request.referencePin, let artifacts = request.referenceArtifacts else {
        throw CoreConformanceCaseError.missingArtifact("reference pin and artifacts")
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

public struct TLCProcessRun: Equatable, Sendable {
  public let primary: TLCProcessResult
  public let trace: TLCProcessResult?
  public let replay: TLCProcessResult?
}

public struct TLCProcessAdapter: Sendable {
  private let executor: any TLCProcessExecuting

  public init(executor: any TLCProcessExecuting = SystemTLCProcessExecutor()) {
    self.executor = executor
  }

  public func run(_ request: TLCProcessRequest, replay: TLCReplayPolicy) throws
    -> TLCProcessRun {
    let primary = try executor.execute(request)
    guard primary.isViolation else {
      return TLCProcessRun(primary: primary, trace: nil, replay: nil)
    }

    let trace: TLCProcessResult
    do {
      trace = try executor.execute(updating(request, traceMode: .dumpJSON))
    } catch {
      throw TLCProcessError.traceCaptureExecutionFailed(
        completed: TLCProcessRun(primary: primary, trace: nil, replay: nil),
        error: TLCProcessExecutionFailure(error))
    }
    guard trace.isViolation || trace.status == 0 else {
      throw TLCProcessError.traceCaptureFailed(
        completed: TLCProcessRun(primary: primary, trace: nil, replay: nil), failed: trace)
    }
    guard replay == .required else {
      return TLCProcessRun(primary: primary, trace: trace, replay: nil)
    }

    let replayResult: TLCProcessResult
    do {
      replayResult = try executor.execute(updating(request, traceMode: .loadJSON))
    } catch {
      throw TLCProcessError.requiredReplayExecutionFailed(
        completed: TLCProcessRun(primary: primary, trace: trace, replay: nil),
        error: TLCProcessExecutionFailure(error))
    }
    guard replayResult.faithfullyReproduces(primary) else {
      throw TLCProcessError.requiredReplayFailed(
        completed: TLCProcessRun(primary: primary, trace: trace, replay: nil), failed: replayResult
      )
    }
    return TLCProcessRun(primary: primary, trace: trace, replay: replayResult)
  }

  private func updating(_ request: TLCProcessRequest, traceMode: TLCTraceMode)
    -> TLCProcessRequest {
    TLCProcessRequest(
      javaExecutable: request.javaExecutable, jar: request.jar,
      bridgeClasses: request.bridgeClasses,
      bundle: request.bundle,
      graphEvents: graphEvents(for: request.graphEvents, mode: traceMode),
      traceOutput: request.traceOutput, replayInput: request.replayInput,
      workingDirectory: request.workingDirectory, arguments: request.arguments,
      expectedCase: request.expectedCase, runID: request.runID,
      timeout: request.timeout, traceMode: traceMode, referencePin: request.referencePin,
      referenceArtifacts: request.referenceArtifacts
    )
  }

  private func graphEvents(for primary: URL, mode: TLCTraceMode) -> URL {
    guard mode != .none else { return primary }
    let suffix = mode == .dumpJSON ? "trace" : "replay"
    return primary.deletingPathExtension().appendingPathExtension("\(suffix).jsonl")
  }
}

extension TLCProcessResult {
  fileprivate func faithfullyReproduces(_ primary: TLCProcessResult) -> Bool {
    primary.isViolation && status == primary.status && isViolation
  }
}

public enum TLCReferenceInspector {
  public static func inspect(
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
      throw CoreConformanceCaseError.pinMismatch("TLC JAR manifest")
    }
    let runtime = try executeProcess(
      executable: javaExecutable, arguments: ["-XshowSettings:properties", "-version"],
      directory: directory, timeout: 10
    )
    guard runtime.status == 0 else { throw CoreConformanceCaseError.pinMismatch("Java runtime") }
    let properties = parseProperties(runtime.stdout + "\n" + runtime.stderr)
    let architecture: String
    switch properties["os.arch"] {
    case "aarch64", "arm64": architecture = "arm64"
    case "amd64", "x86_64": architecture = "x86_64"
    default: throw CoreConformanceCaseError.pinMismatch("Java architecture")
    }
    guard let version = properties["java.runtime.version"], let vendor = properties["java.vendor"]
    else {
      throw CoreConformanceCaseError.pinMismatch("Java runtime properties")
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
