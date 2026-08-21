import Foundation

public enum PublicWorkflowDiagnosticCheckStatus: String, Codable, Sendable, Equatable {
  case matched
  case differed
  case unavailable
}

public enum PublicWorkflowDiagnosticExit: String, Codable, Sendable {
  case success
  case blocked
  case unavailable
}

public struct PublicWorkflowDiagnosticCheck: Codable, Sendable {
  public let id: String
  public let command: String
  public let status: PublicWorkflowDiagnosticCheckStatus
  public let expectedOutcome: PublicWorkflowExpectedOutcome
  public let actualOutcome: PublicWorkflowExpectedOutcome?
  public let evidence: [CoreEvidenceReference]
  public let diagnostic: String?

  public init(
    id: String,
    command: String,
    status: PublicWorkflowDiagnosticCheckStatus,
    expectedOutcome: PublicWorkflowExpectedOutcome,
    actualOutcome: PublicWorkflowExpectedOutcome?,
    evidence: [CoreEvidenceReference],
    diagnostic: String?
  ) {
    self.id = id
    self.command = command
    self.status = status
    self.expectedOutcome = expectedOutcome
    self.actualOutcome = actualOutcome
    self.evidence = evidence
    self.diagnostic = diagnostic
  }
}

public struct PublicWorkflowDiagnosticReport: Codable, Sendable {
  public static let schema = "PublicWorkflowDiagnosticReport"
  public let schema: String
  public let runID: UUID
  public let authority: PublicWorkflowEvidenceAuthority
  public let claimStatus: String
  public let checks: [PublicWorkflowDiagnosticCheck]
  public let finalExitClass: PublicWorkflowDiagnosticExit

  public init(runID: UUID, authority: PublicWorkflowEvidenceAuthority, checks: [PublicWorkflowDiagnosticCheck]) {
    self.schema = Self.schema
    self.runID = runID
    self.authority = authority
    self.claimStatus = authority == .candidate ? "candidateEvidence" : "diagnosticOnly"
    self.checks = checks
    if checks.contains(where: { $0.status == .unavailable }) {
      finalExitClass = .unavailable
    } else if checks.contains(where: { $0.status == .differed }) {
      finalExitClass = .blocked
    } else {
      finalExitClass = .success
    }
  }
}

public struct PublicWorkflowConformanceRunner: Sendable {
  public struct Options: Sendable {
    public let projectRoot: URL
    public let outputRoot: URL
    public let hostedCI: Bool
    public let runFixtures: Bool
    public let runPlatformMatrix: Bool

    public init(projectRoot: URL, outputRoot: URL, hostedCI: Bool, runFixtures: Bool = true, runPlatformMatrix: Bool = true) {
      self.projectRoot = projectRoot
      self.outputRoot = outputRoot
      self.hostedCI = hostedCI
      self.runFixtures = runFixtures
      self.runPlatformMatrix = runPlatformMatrix
    }
  }

  private struct Register: Decodable {
    static let schema = "PublicWorkflowRunnerRegister"
    let schema: String
    let parserBuilder: [Entry]
    let generatedBehavior: CoreEvidenceReference

    struct Entry: Decodable {
      let id: String
      let manifest: CoreEvidenceReference
      let expectedOutcome: PublicWorkflowExpectedOutcome
    }
  }

  public init() {}

  @discardableResult
  public func run(_ options: Options) throws -> (report: PublicWorkflowDiagnosticReport, reportURL: URL) {
    let root = try ConformanceEvidence.projectRoot(options.projectRoot)
    let runID = UUID()
    let outputRoot = try ConformanceEvidence.createDirectory(options.outputRoot, beneath: root)
    let runDirectory = try ConformanceEvidence.createDirectory(
      outputRoot.appendingPathComponent("runs/\(runID.uuidString.lowercased())"), beneath: root)
    let authority: PublicWorkflowEvidenceAuthority = hostedExecutionRequested(options.hostedCI) ? .candidate : .diagnostic
    let checks: [PublicWorkflowDiagnosticCheck]
    do {
      let registerURL = root.appendingPathComponent("Verification/PublicWorkflowConformance/runner.json")
      let registerData = try Data(contentsOf: registerURL)
      let register = try JSONDecoder().decode(Register.self, from: registerData)
      guard register.schema == Register.schema else {
        throw ConformanceGovernanceError.invalidSchema(register.schema)
      }
      checks = try execute(register: register, root: root, runDirectory: runDirectory, gateRunID: runID, runFixtures: options.runFixtures, runPlatformMatrix: options.runPlatformMatrix, hostedCI: authority == .candidate)
    } catch {
      checks = [PublicWorkflowDiagnosticCheck(
        id: "register", command: "load Verification/PublicWorkflowConformance/runner.json", status: .unavailable,
        expectedOutcome: .exact, actualOutcome: nil, evidence: [], diagnostic: String(describing: error))]
    }
    let report = PublicWorkflowDiagnosticReport(runID: runID, authority: authority, checks: checks)
    let reportURL = runDirectory.appendingPathComponent("support-admission.json")
    try ConformanceEvidence.writeCanonical(report, to: reportURL, trailingNewline: true)
    try ConformanceEvidence.writeCanonical(report, to: outputRoot.appendingPathComponent("support-admission.json"), trailingNewline: true)
    return (report, reportURL)
  }

  private func hostedExecutionRequested(_ requested: Bool) -> Bool {
    guard requested else { return false }
    let environment = ProcessInfo.processInfo.environment
    guard environment["GITHUB_ACTIONS"] == "true",
          environment["GITHUB_SHA"]?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
          environment["GITHUB_REPOSITORY"]?.isEmpty == false,
          environment["GITHUB_WORKFLOW"]?.isEmpty == false,
          environment["GITHUB_REF"]?.isEmpty == false,
          environment["GITHUB_RUN_ID"]?.isEmpty == false,
          Int(environment["GITHUB_RUN_ATTEMPT"] ?? "") ?? 0 > 0,
          environment["GITHUB_JOB"]?.isEmpty == false,
          environment["GITHUB_SERVER_URL"]?.isEmpty == false else {
      return false
    }
    return true
  }

  private func execute(
    register: Register,
    root: URL,
    runDirectory: URL,
    gateRunID: UUID,
    runFixtures: Bool,
    runPlatformMatrix: Bool,
    hostedCI: Bool
  ) throws -> [PublicWorkflowDiagnosticCheck] {
    var checks = [PublicWorkflowDiagnosticCheck]()
    for entry in register.parserBuilder {
      checks.append(try parserCheck(entry, root: root, output: runDirectory.appendingPathComponent(entry.id), gateRunID: gateRunID))
    }
    let generatedData = try ConformanceEvidence.data(for: register.generatedBehavior, beneath: root)
    let generated = try PublicWorkflowGeneratedBehaviorManifest.load(generatedData)
    for fixture in generated.fixtures {
      checks.append(try generatedCheck(fixture.id, expected: fixture.expectedOutcome, manifest: register.generatedBehavior,
                                       root: root, output: runDirectory.appendingPathComponent(fixture.id), gateRunID: gateRunID))
    }
    if runFixtures {
      checks.append(try fixtureCheck(root: root, output: runDirectory.appendingPathComponent("annotation-fixtures"), gateRunID: gateRunID))
    }
    if runPlatformMatrix {
      checks.append(try platformCheck(root: root, output: runDirectory.appendingPathComponent("platform-matrix"), gateRunID: gateRunID, hostedCI: hostedCI))
    }
    return checks
  }

  private func platformCheck(root: URL, output: URL, gateRunID: UUID, hostedCI: Bool) throws -> PublicWorkflowDiagnosticCheck {
    _ = try ConformanceEvidence.createDirectory(output, beneath: root)
    let script = root.appendingPathComponent("scripts/run_public_workflow_platform_matrix.sh")
    let package = root.appendingPathComponent("Package.resolved")
    let source = try ConformanceEvidence.reference(for: script, beneath: root)
    let configuration = try ConformanceEvidence.reference(for: package, beneath: root)
    let commands: [[String]] = [
      ["xcodebuild", "-scheme", "SwiftTLA-Package", "-target", "SwiftTLA", "-sdk", "macosx", "-destination", "platform=macOS", "build"]
    ]
    let arguments = try JSONSerialization.data(
      withJSONObject: commands, options: [.sortedKeys, .withoutEscapingSlashes])
    let contextURL = output.appendingPathComponent("binding-context.json")
    let context: [String: Any] = [
      "caseID": "public-library-macos",
      "gateRunID": gateRunID.uuidString.lowercased(),
      "sourceInput": ["path": source.path, "sha256": source.sha256],
      "configuration": ["path": configuration.path, "sha256": configuration.sha256],
      "provenance": [
        "caseID": "public-library-macos", "moduleSHA256": source.sha256, "cfgSHA256": configuration.sha256,
        "argumentsSHA256": SHA256.hex(arguments),
        "tlcTag": "not-applicable-platform-build", "tlcCommit": "not-applicable-platform-build", "tlcJarSHA256": source.sha256,
        "javaDistribution": "not-applicable-platform-build", "javaVersion": "not-applicable-platform-build", "javaArchiveSHA256": source.sha256,
        "bridgeClass": "public-workflow-platform-runner", "bridgeSourceSHA256": source.sha256, "bridgeBinarySHA256": source.sha256
      ]
    ]
    try ConformanceEvidence.writeJSON(context, to: contextURL)
    let stdout = output.appendingPathComponent("stdout.log")
    let stderr = output.appendingPathComponent("stderr.log")
    FileManager.default.createFile(atPath: stdout.path, contents: nil)
    FileManager.default.createFile(atPath: stderr.path, contents: nil)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "--output", output.appendingPathComponent("evidence").path, "--context", contextURL.path] + (hostedCI ? ["--hosted-ci"] : [])
    process.currentDirectoryURL = root
    process.standardOutput = try FileHandle(forWritingTo: stdout)
    process.standardError = try FileHandle(forWritingTo: stderr)
    do {
      try process.run()
      process.waitUntilExit()
      let retained = try artifactReferences(in: output.appendingPathComponent("evidence"), beneath: root)
      let platformStatuses = try retained.compactMap { reference -> String? in
        guard reference.path.hasSuffix("/result.json") else { return nil }
        let value = try JSONSerialization.jsonObject(with: try ConformanceEvidence.data(for: reference, beneath: root)) as? [String: Any]
        guard let correlation = value?["correlation"] as? [String: Any],
              correlation["gateRunID"] as? String == gateRunID.uuidString.lowercased(),
              correlation["caseID"] as? String == "public-library-macos",
              let status = value?["status"] as? String else {
          throw ConformanceGovernanceError.invalidField(record: reference.path, field: "aggregate platform correlation")
        }
        return status
      }
      guard !platformStatuses.isEmpty else {
        throw ConformanceGovernanceError.invalidField(record: "platform-matrix", field: "retained platform results")
      }
      let actual: PublicWorkflowExpectedOutcome? = process.terminationStatus == 0 ? .exact : platformStatuses.contains("failed") ? .difference : nil
      let status: PublicWorkflowDiagnosticCheckStatus
      switch actual {
      case .none: status = .unavailable
      case .some: status = process.terminationStatus == 0 ? .matched : .differed
      }
      return PublicWorkflowDiagnosticCheck(id: "public-library-platform-matrix", command: "scripts/run_public_workflow_platform_matrix.sh",
        status: status, expectedOutcome: .exact, actualOutcome: actual,
        evidence: try [ConformanceEvidence.reference(for: contextURL, beneath: root), ConformanceEvidence.reference(for: stdout, beneath: root), ConformanceEvidence.reference(for: stderr, beneath: root)] + retained,
        diagnostic: status == .matched ? nil : "platform matrix exited \(process.terminationStatus)")
    } catch {
      return PublicWorkflowDiagnosticCheck(id: "public-library-platform-matrix", command: "scripts/run_public_workflow_platform_matrix.sh",
        status: .unavailable, expectedOutcome: .exact, actualOutcome: nil,
        evidence: try [ConformanceEvidence.reference(for: contextURL, beneath: root), ConformanceEvidence.reference(for: stdout, beneath: root), ConformanceEvidence.reference(for: stderr, beneath: root)], diagnostic: String(describing: error))
    }
  }

  private func fixtureCheck(root: URL, output: URL, gateRunID: UUID) throws -> PublicWorkflowDiagnosticCheck {
    _ = try ConformanceEvidence.createDirectory(output, beneath: root)
    let fixtures = [
      ("TLAModel-valid", "TLAModel", "Valid", "PublicWorkflowTLAModelValid", true),
      ("TLAModel-invalid", "TLAModel", "Invalid", "PublicWorkflowTLAModelInvalid", false),
      ("TLAActor-valid", "TLActor", "Valid", "PublicWorkflowTLAActorValid", true),
      ("TLAActor-invalid", "TLActor", "Invalid", "PublicWorkflowTLAActorInvalid", false),
      ("TLAObservable-valid", "TLAObservable", "Valid", "PublicWorkflowTLAObservableValid", true),
      ("TLAObservable-invalid", "TLAObservable", "Invalid", "PublicWorkflowTLAObservableInvalid", false)
    ]
    var unavailable = false
    var differed = false
    let xcodebuild = ProcessInfo.processInfo.environment["PUBLIC_WORKFLOW_ANNOTATION_XCODEBUILD"] ?? "/usr/bin/xcodebuild"
    for (id, directory, kind, scheme, shouldBuild) in fixtures {
      let resultDirectory = output.appendingPathComponent(id)
      _ = try ConformanceEvidence.createDirectory(resultDirectory, beneath: root)
      let stdout = resultDirectory.appendingPathComponent("stdout.log")
      let stderr = resultDirectory.appendingPathComponent("stderr.log")
      let process = Process()
      process.executableURL = URL(fileURLWithPath: xcodebuild)
      process.arguments = ["-workspace", root.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance/\(directory)/\(kind)").path, "-scheme", scheme, "-destination", "platform=macOS,arch=arm64", "build", "CODE_SIGNING_ALLOWED=NO", "SWIFT_SUPPRESS_WARNINGS=NO"]
      FileManager.default.createFile(atPath: stdout.path, contents: nil)
      FileManager.default.createFile(atPath: stderr.path, contents: nil)
      process.standardOutput = try FileHandle(forWritingTo: stdout)
      process.standardError = try FileHandle(forWritingTo: stderr)
      let result = resultDirectory.appendingPathComponent("result.json")
      do {
        try process.run(); process.waitUntilExit()
        let diagnostics = (try? String(contentsOf: stdout, encoding: .utf8) + String(contentsOf: stderr, encoding: .utf8)) ?? ""
        let matched = shouldBuild == (process.terminationStatus == 0)
          && (shouldBuild || diagnostics.contains("Invariant 'withinBounds' violated"))
        differed = differed || !matched
        try ConformanceEvidence.writeJSON(["schema": "PublicWorkflowAnnotationFixtureResult", "gateRunID": gateRunID.uuidString.lowercased(), "id": id, "expected": shouldBuild ? "succeeded" : "failed", "actualExit": process.terminationStatus, "matched": matched], to: result)
      } catch {
        unavailable = true
        try ConformanceEvidence.writeJSON(["schema": "PublicWorkflowAnnotationFixtureResult", "gateRunID": gateRunID.uuidString.lowercased(), "id": id, "status": "unavailable", "diagnostic": String(describing: error)], to: result)
      }
    }
    let retained = try artifactReferences(in: output, beneath: root)
    for reference in retained where reference.path.hasSuffix("/result.json") {
      let value = try JSONSerialization.jsonObject(with: try ConformanceEvidence.data(for: reference, beneath: root)) as? [String: Any]
      guard value?["gateRunID"] as? String == gateRunID.uuidString.lowercased() else {
        throw ConformanceGovernanceError.invalidField(record: reference.path, field: "aggregate annotation correlation")
      }
    }
    let status: PublicWorkflowDiagnosticCheckStatus = unavailable ? .unavailable : differed ? .differed : .matched
    let actual: PublicWorkflowExpectedOutcome? = status == .matched ? .exact : status == .differed ? .difference : nil
    return PublicWorkflowDiagnosticCheck(id: "annotation-fixtures", command: "xcodebuild annotation fixtures", status: status, expectedOutcome: .exact, actualOutcome: actual,
      evidence: try [ConformanceEvidence.reference(for: root.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance/inventory.json"), beneath: root)] + retained, diagnostic: status == .matched ? nil : "annotation fixture outcome did not match")
  }

  private func parserCheck(_ entry: Register.Entry, root: URL, output: URL, gateRunID: UUID) throws -> PublicWorkflowDiagnosticCheck {
    _ = try ConformanceEvidence.data(for: entry.manifest, beneath: root)
    let run = try PublicWorkflowParserBuilderAdapter().run(
      manifestURL: root.appendingPathComponent(entry.manifest.path), projectRoot: root, outputDirectory: output,
      correlation: try correlation(caseID: entry.id, gateRunID: gateRunID))
    return try check(id: entry.id, command: "parser-builder", expected: entry.expectedOutcome, actual: run.comparison.outcome,
                     references: [run.manifest, run.parserObservation, run.builderObservation], root: root, output: output)
  }

  private func generatedCheck(_ id: String, expected: PublicWorkflowExpectedOutcome, manifest: CoreEvidenceReference,
                              root: URL, output: URL, gateRunID: UUID) throws -> PublicWorkflowDiagnosticCheck {
    let run = try PublicWorkflowGeneratedBehaviorAdapter().run(
      manifestURL: root.appendingPathComponent(manifest.path), projectRoot: root, outputDirectory: output,
      correlation: try correlation(caseID: id, gateRunID: gateRunID))
    return try check(id: id, command: "generated-behavior", expected: expected, actual: run.comparison.outcome,
                     references: [run.manifest, run.builderObservation, run.generatedObservation], root: root, output: output)
  }

  private func check(id: String, command: String, expected: PublicWorkflowExpectedOutcome,
                     actual: PublicWorkflowExpectedOutcome, references: [CoreEvidenceReference], root: URL, output: URL) throws -> PublicWorkflowDiagnosticCheck {
    let comparison = try ConformanceEvidence.reference(for: output.appendingPathComponent("comparison.json"), beneath: root)
    return PublicWorkflowDiagnosticCheck(id: id, command: command,
      status: actual == expected ? .matched : .differed, expectedOutcome: expected, actualOutcome: actual,
      evidence: references + [comparison], diagnostic: actual == expected ? nil : "expected \(expected.rawValue), got \(actual.rawValue)")
  }

  private func correlation(caseID: String, gateRunID: UUID) throws -> PublicWorkflowCaseRunCorrelation {
    try PublicWorkflowCaseRunCorrelation(caseID: caseID, gateRunID: gateRunID, fixtureRunID: UUID(), comparisonRunID: UUID())
  }

  private func artifactReferences(in directory: URL, beneath root: URL) throws -> [CoreEvidenceReference] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
      .map { directory.appendingPathComponent($0) }
      .filter { ["json", "log"].contains($0.pathExtension) }
      .sorted { $0.path < $1.path }
    return try files.map { try ConformanceEvidence.reference(for: $0, beneath: root) }
  }
}
