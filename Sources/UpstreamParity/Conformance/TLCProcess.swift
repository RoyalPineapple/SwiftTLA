import Darwin
import Foundation

public enum TLCTraceModeV1: Equatable, Sendable {
  case none
  case dumpJSON
  case loadJSON
}

public enum TLCReplayPolicyV1: Equatable, Sendable {
  case none
  case required
}

public struct TLCProcessExecutionFailureV1: Equatable, Sendable {
  public let message: String
  public let partialStdout: String?
  public let partialStderr: String?

  public init(_ error: Error) {
    if case TLCProcessErrorV1.timedOut(let stdout, let stderr) = error {
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

public indirect enum TLCProcessErrorV1: Error, Equatable, Sendable {
  case timedOut(partialStdout: String, partialStderr: String)
  case failedToStart(String)
  case requiredReplayFailed(completed: TLCProcessRunV1, failed: TLCProcessResultV1)
  case traceCaptureFailed(completed: TLCProcessRunV1, failed: TLCProcessResultV1)
  case requiredReplayExecutionFailed(completed: TLCProcessRunV1, error: TLCProcessExecutionFailureV1)
  case traceCaptureExecutionFailed(completed: TLCProcessRunV1, error: TLCProcessExecutionFailureV1)
}

public struct TLCProcessRequestV1: Equatable, Sendable {
  public let javaExecutable: URL
  public let jar: URL
  public let bridgeClasses: URL
  public let module: URL
  public let configuration: URL
  public let graphEvents: URL
  public let traceOutput: URL
  public let replayInput: URL
  public let workingDirectory: URL
  public let arguments: [String]
  public let expectedCase: CoreConformanceCaseV1
  public let runID: UUID
  public let timeout: TimeInterval
  public let traceMode: TLCTraceModeV1
  public let referencePin: TLCReferencePinV1?
  public let referenceArtifacts: TLCReferenceArtifactsV1?

  public init(
    javaExecutable: URL,
    jar: URL,
    bridgeClasses: URL,
    module: URL,
    configuration: URL,
    graphEvents: URL,
    traceOutput: URL,
    replayInput: URL,
    workingDirectory: URL,
    arguments: [String],
    expectedCase: CoreConformanceCaseV1,
    runID: UUID,
    timeout: TimeInterval = 60,
    traceMode: TLCTraceModeV1 = .none,
    referencePin: TLCReferencePinV1? = nil,
    referenceArtifacts: TLCReferenceArtifactsV1? = nil
  ) {
    self.javaExecutable = javaExecutable
    self.jar = jar
    self.bridgeClasses = bridgeClasses
    self.module = module
    self.configuration = configuration
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

  public func commandArguments(traceMode: TLCTraceModeV1? = nil) throws -> [String] {
    let mode = traceMode ?? self.traceMode
    return [
      "-Dswifttla.tlc.graph.path=\(graphEvents.path)",
      "-Dswifttla.tlc.graph.provenance=\(try provenanceJSON())",
      "-Dswifttla.tlc.graph.run-id=\(runID.uuidString.lowercased())",
      "-Dswifttla.tlc.graph.case-id=\(caseID)",
      "-cp", "\(jar.path):\(bridgeClasses.path)",
      "tlc2.TLC", "-dump", "class,org.swifttla.conformance.LosslessStateWriter",
    ] + traceArguments(mode) + arguments + ["-config", configuration.path, module.path]
  }

  public func validateLaunchBinding() throws {
    try expectedCase.validateLaunch(
      module: module, configuration: configuration, arguments: arguments, caseID: caseID
    )
  }

  public func validateReferenceBinding(pin: TLCReferencePinV1, artifacts: TLCReferenceArtifactsV1)
    throws
  {
    guard expectedCase.pin == pin else {
      throw CoreConformanceCaseErrorV1.pinMismatch("declared case reference pin")
    }
    guard sameFile(jar, artifacts.jar) else {
      throw CoreConformanceCaseErrorV1.pinMismatch("execution TLC JAR")
    }
    let bridgeClassFile =
      bridgeClasses
      .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
      .appendingPathExtension("class")
    guard sameFile(bridgeClassFile, artifacts.bridgeBinary) else {
      throw CoreConformanceCaseErrorV1.pinMismatch("execution bridge class")
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
      "architecture": expectedCase.architecture, "environment": expectedCase.environment,
    ]
    let data = try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }

  private func traceArguments(_ mode: TLCTraceModeV1) -> [String] {
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
    module: URL(fileURLWithPath: "/tmp/Fixture.tla"),
    configuration: URL(fileURLWithPath: "/tmp/Fixture.cfg"),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/counterexample.json"),
    replayInput: URL(fileURLWithPath: "/tmp/counterexample.json"),
    workingDirectory: URL(fileURLWithPath: "/tmp"),
    arguments: ["-workers", "1", "-fp", "1"],
    expectedCase: try! CoreConformanceCaseV1(
      id: "fixture", moduleSHA256: String(repeating: "c", count: 64),
      cfgSHA256: String(repeating: "d", count: 64),
      arguments: ["-workers", "1", "-fp", "1"],
      argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(["-workers", "1", "-fp", "1"]),
      workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
      architecture: "arm64", environment: [:], pin: .fixture
    ),
    runID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  )
}

public struct TLCProcessResultV1: Equatable, Sendable {
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
  func execute(_ request: TLCProcessRequestV1) throws -> TLCProcessResultV1
}

public struct SystemTLCProcessExecutorV1: TLCProcessExecuting {
  private let validatesReferences: Bool

  public init(validatesReferences: Bool = true) {
    self.validatesReferences = validatesReferences
  }

  public func execute(_ request: TLCProcessRequestV1) throws -> TLCProcessResultV1 {
    try request.validateLaunchBinding()
    if validatesReferences {
      guard let pin = request.referencePin, let artifacts = request.referenceArtifacts else {
        throw CoreConformanceCaseErrorV1.missingArtifact("reference pin and artifacts")
      }
      try request.validateReferenceBinding(pin: pin, artifacts: artifacts)
      try pin.validate(
        TLCReferenceInspectorV1.inspect(
          artifacts: artifacts, javaExecutable: request.javaExecutable,
          directory: request.workingDirectory
        ))
    }
    let result = try executeProcess(
      executable: request.javaExecutable,
      arguments: try request.commandArguments(),
      directory: request.workingDirectory,
      timeout: request.timeout,
      environment: request.effectiveEnvironment
    )
    try request.expectedCase.pin.validateReportedTLCBanner(result.stdout + "\n" + result.stderr)
    return result
  }
}

public struct TLCProcessRunV1: Equatable, Sendable {
  public let primary: TLCProcessResultV1
  public let trace: TLCProcessResultV1?
  public let replay: TLCProcessResultV1?
}

public struct TLCProcessAdapterV1: Sendable {
  private let executor: any TLCProcessExecuting

  public init(executor: any TLCProcessExecuting = SystemTLCProcessExecutorV1()) {
    self.executor = executor
  }

  public func run(_ request: TLCProcessRequestV1, replay: TLCReplayPolicyV1) throws
    -> TLCProcessRunV1
  {
    let primary = try executor.execute(request)
    guard primary.isViolation else {
      return TLCProcessRunV1(primary: primary, trace: nil, replay: nil)
    }

    let trace: TLCProcessResultV1
    do {
      trace = try executor.execute(updating(request, traceMode: .dumpJSON))
    } catch {
      throw TLCProcessErrorV1.traceCaptureExecutionFailed(
        completed: TLCProcessRunV1(primary: primary, trace: nil, replay: nil),
        error: TLCProcessExecutionFailureV1(error))
    }
    guard trace.isViolation || trace.status == 0 else {
      throw TLCProcessErrorV1.traceCaptureFailed(
        completed: TLCProcessRunV1(primary: primary, trace: nil, replay: nil), failed: trace)
    }
    guard replay == .required else {
      return TLCProcessRunV1(primary: primary, trace: trace, replay: nil)
    }

    let replayResult: TLCProcessResultV1
    do {
      replayResult = try executor.execute(updating(request, traceMode: .loadJSON))
    } catch {
      throw TLCProcessErrorV1.requiredReplayExecutionFailed(
        completed: TLCProcessRunV1(primary: primary, trace: trace, replay: nil),
        error: TLCProcessExecutionFailureV1(error))
    }
    guard replayResult.faithfullyReproduces(primary) else {
      throw TLCProcessErrorV1.requiredReplayFailed(
        completed: TLCProcessRunV1(primary: primary, trace: trace, replay: nil), failed: replayResult
      )
    }
    return TLCProcessRunV1(primary: primary, trace: trace, replay: replayResult)
  }

  private func updating(_ request: TLCProcessRequestV1, traceMode: TLCTraceModeV1)
    -> TLCProcessRequestV1
  {
    TLCProcessRequestV1(
      javaExecutable: request.javaExecutable, jar: request.jar,
      bridgeClasses: request.bridgeClasses,
      module: request.module, configuration: request.configuration,
      graphEvents: graphEvents(for: request.graphEvents, mode: traceMode),
      traceOutput: request.traceOutput, replayInput: request.replayInput,
      workingDirectory: request.workingDirectory, arguments: request.arguments,
      expectedCase: request.expectedCase, runID: request.runID,
      timeout: request.timeout, traceMode: traceMode, referencePin: request.referencePin,
      referenceArtifacts: request.referenceArtifacts
    )
  }

  private func graphEvents(for primary: URL, mode: TLCTraceModeV1) -> URL {
    guard mode != .none else { return primary }
    let suffix = mode == .dumpJSON ? "trace" : "replay"
    return primary.deletingPathExtension().appendingPathExtension("\(suffix).jsonl")
  }
}

extension TLCProcessResultV1 {
  fileprivate func faithfullyReproduces(_ primary: TLCProcessResultV1) -> Bool {
    primary.isViolation && status == primary.status && isViolation
  }
}

public enum TLCReferenceInspectorV1 {
  public static func inspect(
    artifacts: TLCReferenceArtifactsV1,
    javaExecutable: URL,
    directory: URL
  )
    throws -> TLCReferenceArtifactsV1
  {
    let manifest = try executeProcess(
      executable: URL(fileURLWithPath: "/usr/bin/unzip"),
      arguments: ["-p", artifacts.jar.path, "META-INF/MANIFEST.MF"], directory: directory,
      timeout: 10
    )
    guard manifest.status == 0 else {
      throw CoreConformanceCaseErrorV1.pinMismatch("TLC JAR manifest")
    }
    let runtime = try executeProcess(
      executable: javaExecutable, arguments: ["-XshowSettings:properties", "-version"],
      directory: directory, timeout: 10
    )
    guard runtime.status == 0 else { throw CoreConformanceCaseErrorV1.pinMismatch("Java runtime") }
    let properties = parseProperties(runtime.stdout + "\n" + runtime.stderr)
    let architecture: String
    switch properties["os.arch"] {
    case "aarch64", "arm64": architecture = "arm64"
    case "amd64", "x86_64": architecture = "x86_64"
    default: throw CoreConformanceCaseErrorV1.pinMismatch("Java architecture")
    }
    guard let version = properties["java.runtime.version"], let vendor = properties["java.vendor"]
    else {
      throw CoreConformanceCaseErrorV1.pinMismatch("Java runtime properties")
    }
    return TLCReferenceArtifactsV1(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary,
      jarManifest: manifest.stdout,
      runtime: TLCJavaRuntimeIdentityV1(
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
) throws -> TLCProcessResultV1 {
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
  let readersStarted = DispatchGroup()
  let output = ProcessOutputBuffersV1()
  readersStarted.enter()
  outputGroup.enter()
  DispatchQueue.global().async {
    readersStarted.leave()
    drain(stdoutPipe.fileHandleForReading, into: output.appendStdout)
    outputGroup.leave()
  }
  readersStarted.enter()
  outputGroup.enter()
  DispatchQueue.global().async {
    readersStarted.leave()
    drain(stderrPipe.fileHandleForReading, into: output.appendStderr)
    outputGroup.leave()
  }
  guard readersStarted.wait(timeout: .now() + 1) == .success else {
    throw TLCProcessErrorV1.failedToStart("could not start process output readers")
  }
  let termination = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in termination.signal() }
  do {
    try process.run()
  } catch {
    throw TLCProcessErrorV1.failedToStart(error.localizedDescription)
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
    throw TLCProcessErrorV1.timedOut(
      partialStdout: String(data: output.stdout, encoding: .utf8) ?? "<non-UTF-8 output>",
      partialStderr: String(data: output.stderr, encoding: .utf8) ?? "<non-UTF-8 output>"
    )
  }
  _ = outputGroup.wait(timeout: .now() + 1)
  return TLCProcessResultV1(
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

private final class ProcessOutputBuffersV1: @unchecked Sendable {
  private let lock = NSLock()
  private var storedStdout = Data()
  private var storedStderr = Data()

  var stdout: Data { lock.withLock { storedStdout } }
  var stderr: Data { lock.withLock { storedStderr } }

  func appendStdout(_ data: Data) { lock.withLock { storedStdout.append(data) } }
  func appendStderr(_ data: Data) { lock.withLock { storedStderr.append(data) } }
}
