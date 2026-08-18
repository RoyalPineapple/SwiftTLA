import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowAnnotationFixtureTests {
  @Test("every advertised public annotation has fixture identity without a local admission claim")
  func advertisedAnnotationsHaveSupportDecisions() throws {
    let inventory = try loadInventory()
    #expect(Set(inventory.annotations.map(\.fixtureID)).count == inventory.annotations.count)
    for annotation in inventory.annotations {
      try validateSourceInputs(annotation, root: packageRoot)
    }

    for annotation in inventory.annotations where annotation.advertised {
      #expect(
        annotation.decision == "pendingCI",
        "\(annotation.name) does not require retained CI evidence"
      )
      #expect(annotation.publicAdmission == "notAdmitted")
      #expect(annotation.localEvidence == "diagnosticOnly")
      #expect(annotation.ciEvidence == "requiredRetained")
      if annotation.decision == "pendingCI" {
        let positiveFixture = try #require(annotation.positiveFixture)
        let invalidFixture = try #require(annotation.invalidFixture)
        #expect(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent(positiveFixture).path))
        #expect(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent(invalidFixture).path))
        #expect(annotation.expectedPositiveOutcome == "buildSucceeded")
        #expect(annotation.scheme?.isEmpty == false)
        #expect(annotation.expectedInvalidOutcome == "buildFailed")
      }
      #expect(annotation.diagnosticCategory?.isEmpty == false)
      #expect(annotation.diagnosticText?.isEmpty == false)
      #expect(!annotation.sourceInputs.isEmpty)
      for sourceInput in annotation.sourceInputs {
        #expect(FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(sourceInput.path).path))
      }
    }
  }

  @Test("inventory exactly covers exported public macro declarations")
  func inventoryCoversExportedMacros() throws {
    let inventory = try loadInventory()
    let macroSource = try String(
      contentsOf: packageRoot.appendingPathComponent("Sources/SwiftTLAMacros/Macros.swift"),
      encoding: .utf8
    )
    let expression = try NSRegularExpression(pattern: #"public\s+macro\s+(\w+)"#)
    let range = NSRange(macroSource.startIndex..., in: macroSource)
    let exported = Set(expression.matches(in: macroSource, range: range).compactMap { match -> String? in
      guard let nameRange = Range(match.range(at: 1), in: macroSource) else { return nil }
      return "@" + String(macroSource[nameRange])
    }.filter { $0 != "@spec" })
    let inventoried = Set(inventory.annotations.filter { $0.decision != "removed" }.map(\.name))

    #expect(exported == inventoried)
    #expect(!macroSource.contains("public macro TLAValidated"))
    #expect(!macroSource.contains("public macro TypedVar"))
    let typedVar = try #require(inventory.annotations.first { $0.name == "@TypedVar" })
    #expect(typedVar.advertised == false)
    #expect(typedVar.decision == "removed")
  }

  @Test("pinned source input digest rejects byte drift")
  func sourceInputDigestRejectsByteDrift() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-annotation-drift-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let input = root.appendingPathComponent("fixture.swift")
    let original = Data("original".utf8)
    try original.write(to: input)
    let reference = SourceInput(path: "fixture.swift", sha256: SHA256V1.hex(original))
    try Data("changed".utf8).write(to: input)

    #expect(throws: InventoryError.digestMismatch("fixture.swift")) {
      try validateSourceInput(reference, root: root)
    }
  }

  @Test("xcodebuild fixture results are local diagnostics until CI retains them")
  func xcodebuildFixtureResultsAreDiagnosticOnly() throws {
    let inventory = try loadInventory()

    for annotation in inventory.annotations where annotation.decision == "pendingCI" {
      let positiveFixture = try #require(annotation.positiveFixture)
      let invalidFixture = try #require(annotation.invalidFixture)
      let scheme = try #require(annotation.scheme)
      let diagnostic = try #require(annotation.diagnosticText)

      let positive = try runXcodebuild(fixtureRoot.appendingPathComponent(positiveFixture), scheme: scheme)
      #expect(positive.status == 0, "\(annotation.name) positive fixture failed:\n\(positive.output)")

      let invalidScheme = scheme.replacingOccurrences(of: "Valid", with: "Invalid")
      let invalid = try runXcodebuild(fixtureRoot.appendingPathComponent(invalidFixture), scheme: invalidScheme)
      #expect(invalid.status != 0, "\(annotation.name) invalid fixture unexpectedly built")
      #expect(invalid.output.contains(diagnostic), "\(annotation.name) invalid fixture lost its diagnostic category:\n\(invalid.output)")
    }

  }

  @Test("actor runtime proof is local diagnostic evidence until CI retains it")
  func actorRuntimeProofIsDiagnosticOnly() throws {
    let inventory = try loadInventory()
    let actor = try #require(inventory.annotations.first { $0.name == "@TLAActor" })
    let runtimeProof = try #require(actor.runtimeProof)
    let fixture = try #require(actor.positiveFixture)

    #expect(runtimeProof.command == "swift run")
    #expect(runtimeProof.evidence == "localDiagnosticOnly")

    let result = try runSwiftRun(in: fixtureRoot.appendingPathComponent(fixture))
    #expect(result.status == 0, "@TLAActor runtime fixture failed:\n\(result.output)")
  }

  @Test("unimplemented annotations cannot be treated as release support")
  func unimplementedAnnotationsAreExplicitlyNarrowed() throws {
    let inventory = try loadInventory()
    let validated = try #require(inventory.annotations.first { $0.name == "@TLAValidated" })

    #expect(validated.advertised == false)
    #expect(validated.decision == "removed")
    #expect(validated.positiveFixture == nil)
    #expect(validated.invalidFixture == nil)
    #expect(validated.reason?.isEmpty == false)
  }

  private func validateSourceInputs(_ annotation: Annotation, root: URL) throws {
    for reference in annotation.sourceInputs {
      try validateSourceInput(reference, root: root)
    }
    let canonical = annotation.sourceInputs
      .sorted { $0.path < $1.path }
      .map { "\($0.path) \($0.sha256)\n" }
      .joined()
    guard SHA256V1.hex(Data(canonical.utf8)) == annotation.sourceInputsSHA256 else {
      throw InventoryError.aggregateMismatch(annotation.name)
    }
  }

  private func validateSourceInput(_ reference: SourceInput, root: URL) throws {
    let actual = SHA256V1.hex(try Data(contentsOf: root.appendingPathComponent(reference.path)))
    guard actual == reference.sha256 else {
      throw InventoryError.digestMismatch(reference.path)
    }
  }

  private var fixtureRoot: URL {
    packageRoot.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance")
  }

  private var packageRoot: URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
      directory.deleteLastPathComponent()
    }
    return directory
  }

  private func loadInventory() throws -> Inventory {
    let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("inventory.json"))
    let inventory = try JSONDecoder().decode(Inventory.self, from: data)
    #expect(inventory.schema == "PublicWorkflowAnnotationInventoryV1")
    return inventory
  }

  private func runXcodebuild(_ fixture: URL, scheme: String) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
    process.arguments = [
      "-workspace", fixture.path,
      "-scheme", scheme,
      "-destination", "platform=macOS,arch=arm64",
      "build",
      "CODE_SIGNING_ALLOWED=NO"
    ]
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-xcodebuild-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    try output.close()

    return (
      process.terminationStatus,
      String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
    )
  }

  private func runSwiftRun(in fixture: URL) throws -> (status: Int32, output: String) {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-public-workflow-fixture-\(UUID().uuidString)")
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-swift-run-\(UUID().uuidString).log")
    defer {
      try? FileManager.default.removeItem(at: scratch)
      try? FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run", "--package-path", fixture.path, "--scratch-path", scratch.path]
    let output = try FileHandle(forWritingTo: outputURL)
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    try output.close()

    return (
      process.terminationStatus,
      String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
    )
  }

  private struct Inventory: Decodable {
    let schema: String
    let annotations: [Annotation]
  }

  private struct Annotation: Decodable {
    let name: String
    let fixtureID: String
    let advertised: Bool
    let decision: String
    let publicAdmission: String?
    let localEvidence: String?
    let ciEvidence: String?
    let positiveFixture: String?
    let invalidFixture: String?
    let scheme: String?
    let expectedPositiveOutcome: String?
    let expectedInvalidOutcome: String?
    let diagnosticCategory: String?
    let diagnosticText: String?
    let runtimeProof: RuntimeProof?
    let reason: String?
    let sourceInputsSHA256: String
    let sourceInputs: [SourceInput]
  }

  private struct SourceInput: Codable {
    let path: String
    let sha256: String
  }

  private enum InventoryError: Error, Equatable {
    case digestMismatch(String)
    case aggregateMismatch(String)
  }

  private struct RuntimeProof: Decodable {
    let command: String
    let evidence: String
  }
}
