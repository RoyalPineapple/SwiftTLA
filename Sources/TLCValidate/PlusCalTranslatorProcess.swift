import CryptoKit
import Foundation

/// Immutable inputs and retained evidence for one external PlusCal translation.
///
/// The translator rewrites its module argument in place. The canonical `module`
/// is therefore copied to `stagingDirectory` before it is passed to the tool.
struct PlusCalTranslationRequestV1: Equatable, Sendable {
  let javaExecutable: URL
  let jar: URL
  let module: URL
  let configuration: URL
  let stagingDirectory: URL

  init(
    javaExecutable: URL,
    jar: URL,
    module: URL,
    configuration: URL,
    stagingDirectory: URL
  ) {
    self.javaExecutable = javaExecutable
    self.jar = jar
    self.module = module
    self.configuration = configuration
    self.stagingDirectory = stagingDirectory
  }

  init(projectRoot: URL, module: URL, configuration: URL, stagingDirectory: URL) {
    self.init(
      javaExecutable: projectRoot.appending(path: ".build/core-conformance-tools/java-arm64/Contents/Home/bin/java"),
      jar: projectRoot.appending(path: ".build/core-conformance-tools/downloads/tla2tools.jar"),
      module: module,
      configuration: configuration,
      stagingDirectory: stagingDirectory
    )
  }

  var stagedModule: URL {
    stagingDirectory.appendingPathComponent(module.lastPathComponent)
  }

  var stagedConfiguration: URL {
    stagingDirectory.appendingPathComponent(configuration.lastPathComponent)
  }

  func commandArguments(stagedModule: URL) -> [String] {
    ["-cp", jar.path, "pcal.trans", "-unixEOL", stagedModule.path]
  }

  func command(stagedModule: URL) -> [String] {
    [javaExecutable.path] + commandArguments(stagedModule: stagedModule)
  }
}

struct PlusCalTranslationResultV1: Equatable, Sendable {
  let status: Int32
  let stdout: String
  let stderr: String
  let originalModule: URL
  let stagedModule: URL
  let originalConfiguration: URL
  let stagedConfiguration: URL
  let originalModuleSHA256: String
  let stagedModuleSHA256: String
  let stagedOutputChanged: Bool
  let originalConfigurationSHA256: String
  let stagedConfigurationSHA256: String
  let stagedConfigurationChanged: Bool

  var completed: Bool { status == 0 }
}

/// A presentation-ready failure that keeps each investigation field separate.
struct PlusCalTranslationDiagnosticV1: Equatable, Sendable {
  let failedConcept: String
  let filePath: String
  let command: [String]
  let expected: String
  let actual: String
  let outputStatus: String
  let nextSafeAction: String
  let stdout: String
  let stderr: String
  let originalModule: URL
  let stagedModule: URL
  let originalConfiguration: URL
  let stagedConfiguration: URL
  let originalModuleSHA256: String?
  let stagedModuleSHA256: String?
  let stagedOutputChanged: Bool?
  let originalConfigurationSHA256: String?
  let stagedConfigurationSHA256: String?
  let stagedConfigurationChanged: Bool?
}

enum PlusCalTranslationErrorV1: Error, Equatable, Sendable {
  case invalidInput(PlusCalTranslationDiagnosticV1)
  case failedToStart(PlusCalTranslationDiagnosticV1)
  case unsuccessful(PlusCalTranslationDiagnosticV1)

  var diagnostic: PlusCalTranslationDiagnosticV1 {
    switch self {
    case .invalidInput(let diagnostic), .failedToStart(let diagnostic), .unsuccessful(let diagnostic):
      diagnostic
    }
  }
}

protocol PlusCalTranslationExecuting: Sendable {
  func execute(_ request: PlusCalTranslationRequestV1) throws -> PlusCalTranslationResultV1
}

/// Runs the pinned external PlusCal translator without interpreting its output.
///
/// This is deliberately a tooling boundary: it neither renders a module nor
/// invokes TLC. Callers decide when a successfully rewritten module is safe to
/// consume.
struct SystemPlusCalTranslationExecutorV1: PlusCalTranslationExecuting {
  func execute(_ request: PlusCalTranslationRequestV1) throws -> PlusCalTranslationResultV1 {
    try validateInputs(request)
    let originalDigest = try sha256(at: request.module)
    let originalConfigurationDigest = try sha256(at: request.configuration)
    let staged = try stage(request)

    let process = Process()
    process.executableURL = request.javaExecutable
    process.arguments = request.commandArguments(stagedModule: staged.module)
    process.currentDirectoryURL = request.stagingDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw PlusCalTranslationErrorV1.failedToStart(diagnostic(
        failedConcept: "external PlusCal translator launch",
        filePath: request.javaExecutable.path,
        request: request,
        staged: staged,
        expected: "The pinned Java runtime launches pcal.trans with the pinned tla2tools.jar.",
        actual: error.localizedDescription,
        outputStatus: "The translator did not start; the canonical module was not changed and staged output is unchanged.",
        nextSafeAction: "Verify the pinned Java executable and tla2tools.jar paths before retrying."
      ))
    }

    process.waitUntilExit()
    let result = PlusCalTranslationResultV1(
      status: process.terminationStatus,
      stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
      stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
      originalModule: request.module,
      stagedModule: staged.module,
      originalConfiguration: request.configuration,
      stagedConfiguration: staged.configuration,
      originalModuleSHA256: originalDigest,
      stagedModuleSHA256: try sha256(at: staged.module),
      stagedOutputChanged: try sha256(at: staged.module) != originalDigest,
      originalConfigurationSHA256: originalConfigurationDigest,
      stagedConfigurationSHA256: try sha256(at: staged.configuration),
      stagedConfigurationChanged: try sha256(at: staged.configuration) != originalConfigurationDigest
    )
    guard result.completed else {
      throw PlusCalTranslationErrorV1.unsuccessful(diagnostic(
        failedConcept: "external PlusCal translation",
        filePath: staged.module.path,
        request: request,
        staged: staged,
        expected: "pcal.trans exits successfully after translating the declared PlusCal module.",
        actual: "pcal.trans exited with status \(result.status).",
        outputStatus: "The translator exited unsuccessfully; canonical inputs were not changed; staged module changed: \(result.stagedOutputChanged); staged cfg changed: \(result.stagedConfigurationChanged). No downstream TLC result was produced.",
        nextSafeAction: "Inspect the retained stdout and stderr with the module source, correct the PlusCal syntax, then rerun translation.",
        stdout: result.stdout,
        stderr: result.stderr
      ))
    }
    return result
  }

  private func validateInputs(_ request: PlusCalTranslationRequestV1) throws {
    let fileManager = FileManager.default
    for (concept, file, expected, action) in [
      ("pinned Java runtime", request.javaExecutable, "The pinned Java executable exists.", "Restore the core conformance Java toolchain before retrying."),
      ("pinned tla2tools.jar", request.jar, "The pinned tla2tools.jar exists.", "Restore downloads/tla2tools.jar before retrying."),
      ("PlusCal module", request.module, "The requested .tla module exists before translation.", "Write or select the intended PlusCal module before retrying."),
      ("TLC configuration", request.configuration, "The requested .cfg configuration exists beside the translation inputs.", "Write or select the intended configuration before retrying.")
    ] {
      guard fileManager.fileExists(atPath: file.path) else {
        throw PlusCalTranslationErrorV1.invalidInput(diagnostic(
          failedConcept: concept,
          filePath: file.path,
          request: request,
          staged: nil,
          expected: expected,
          actual: "No file exists at \(file.path).",
          outputStatus: "The translator was not launched; no module state was changed.",
          nextSafeAction: action
        ))
      }
    }
    guard request.stagingDirectory.resolvingSymlinksInPath().standardizedFileURL
      != request.module.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL else {
      throw PlusCalTranslationErrorV1.invalidInput(diagnostic(
        failedConcept: "PlusCal staging directory",
        filePath: request.stagingDirectory.path,
        request: request,
        staged: nil,
        expected: "A run-local staging directory distinct from the canonical module directory.",
        actual: "The staging directory aliases the canonical module directory.",
        outputStatus: "The translator was not launched; no module state was changed.",
        nextSafeAction: "Choose a fresh run-local staging directory before retrying."
      ))
    }
    for (concept, file) in [("PlusCal module", request.module), ("TLC configuration", request.configuration)] {
      guard (try? Data(contentsOf: file)) != nil else {
      throw PlusCalTranslationErrorV1.invalidInput(diagnostic(
        failedConcept: concept,
        filePath: file.path,
        request: request,
        staged: nil,
        expected: "The requested translation input is readable before translation.",
        actual: "The input could not be read.",
        outputStatus: "The translator was not launched; no canonical input was changed.",
        nextSafeAction: "Repair the input permissions or encoding before retrying."
      ))
      }
    }
  }

  private struct StagedInputs: Sendable {
    let module: URL
    let configuration: URL
  }

  private func stage(_ request: PlusCalTranslationRequestV1) throws -> StagedInputs {
    let fileManager = FileManager.default
    let staging = request.stagingDirectory
    let staged = StagedInputs(module: request.stagedModule, configuration: request.stagedConfiguration)
    let temporary = staging.deletingLastPathComponent()
      .appendingPathComponent(".\(staging.lastPathComponent).staging-\(UUID().uuidString)", isDirectory: true)
    do {
      guard !fileManager.fileExists(atPath: staging.path) else {
        throw CocoaError(.fileWriteFileExists)
      }
      try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
      let temporaryModule = temporary.appendingPathComponent(request.module.lastPathComponent)
      let temporaryConfiguration = temporary.appendingPathComponent(request.configuration.lastPathComponent)
      guard !fileManager.fileExists(atPath: temporaryModule.path),
            !fileManager.fileExists(atPath: temporaryConfiguration.path) else {
        throw CocoaError(.fileWriteFileExists)
      }
      try fileManager.copyItem(at: request.module, to: temporaryModule)
      try fileManager.copyItem(at: request.configuration, to: temporaryConfiguration)
      try fileManager.moveItem(at: temporary, to: staging)
      return staged
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw PlusCalTranslationErrorV1.invalidInput(diagnostic(
        failedConcept: "PlusCal translation input staging",
        filePath: staging.path,
        request: request,
        staged: staged,
        expected: "The canonical .tla module and .cfg configuration are copied atomically to a fresh run-local staging directory before translation.",
        actual: error.localizedDescription,
        outputStatus: "The translator was not launched; canonical module and cfg were not changed.",
        nextSafeAction: "Inspect the staging directory permissions and choose a fresh run-local directory before retrying."
      ))
    }
  }

  private func diagnostic(
    failedConcept: String,
    filePath: String,
    request: PlusCalTranslationRequestV1,
    staged: StagedInputs?,
    expected: String,
    actual: String,
    outputStatus: String,
    nextSafeAction: String,
    stdout: String = "",
    stderr: String = ""
  ) -> PlusCalTranslationDiagnosticV1 {
    .init(
      failedConcept: failedConcept,
      filePath: filePath,
      command: request.command(stagedModule: staged?.module ?? request.stagedModule),
      expected: expected,
      actual: actual,
      outputStatus: outputStatus,
      nextSafeAction: nextSafeAction,
      stdout: stdout,
      stderr: stderr,
      originalModule: request.module,
      stagedModule: staged?.module ?? request.stagedModule,
      originalConfiguration: request.configuration,
      stagedConfiguration: staged?.configuration ?? request.stagedConfiguration,
      originalModuleSHA256: try? sha256(at: request.module),
      stagedModuleSHA256: staged.flatMap { try? sha256(at: $0.module) },
      stagedOutputChanged: staged.flatMap { staged in
        guard let original = try? sha256(at: request.module), let output = try? sha256(at: staged.module) else { return nil }
        return original != output
      },
      originalConfigurationSHA256: try? sha256(at: request.configuration),
      stagedConfigurationSHA256: staged.flatMap { try? sha256(at: $0.configuration) },
      stagedConfigurationChanged: staged.flatMap { staged in
        guard let original = try? sha256(at: request.configuration), let output = try? sha256(at: staged.configuration) else { return nil }
        return original != output
      }
    )
  }

  private func sha256(at url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
