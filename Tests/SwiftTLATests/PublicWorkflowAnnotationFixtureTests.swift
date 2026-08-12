import Foundation
import Testing

@Suite(.serialized)
struct PublicWorkflowAnnotationFixtureTests {
  @Test("every advertised public annotation has a declared support decision and fixture identity")
  func advertisedAnnotationsHaveSupportDecisions() throws {
    let inventory = try loadInventory()
    #expect(Set(inventory.annotations.map(\.fixtureID)).count == inventory.annotations.count)

    for annotation in inventory.annotations where annotation.advertised {
      #expect(
        annotation.decision == "fixtureBacked",
        "\(annotation.name) is advertised without an explicit support decision"
      )
      if annotation.decision == "fixtureBacked" {
        let positiveFixture = try #require(annotation.positiveFixture)
        let invalidFixture = try #require(annotation.invalidFixture)
        #expect(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent(positiveFixture).path))
        #expect(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent(invalidFixture).path))
        #expect(annotation.expectedPositiveOutcome == "buildSucceeded" || annotation.expectedPositiveOutcome == "runSucceeded")
        #expect(annotation.positiveCommand == "build" || annotation.positiveCommand == "run")
        #expect(annotation.expectedInvalidOutcome == "buildFailed")
      }
      #expect(annotation.diagnosticCategory?.isEmpty == false)
      #expect(annotation.diagnosticText?.isEmpty == false)
      #expect(!annotation.sourceInputs.isEmpty)
      for sourceInput in annotation.sourceInputs {
        #expect(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent(sourceInput).path))
      }
    }
  }

  @Test("fixture packages produce their declared compiler outcomes")
  func fixturePackagesProduceDeclaredOutcomes() throws {
    let inventory = try loadInventory()

    for annotation in inventory.annotations where annotation.decision == "fixtureBacked" {
      let positiveFixture = try #require(annotation.positiveFixture)
      let invalidFixture = try #require(annotation.invalidFixture)
      let diagnostic = try #require(annotation.diagnosticText)

      let positive = try runSwift(
        annotation.positiveCommand == "run" ? "run" : "build",
        in: fixtureRoot.appendingPathComponent(positiveFixture)
      )
      #expect(positive.status == 0, "\(annotation.name) positive fixture failed:\n\(positive.output)")

      let invalid = try runSwift("build", in: fixtureRoot.appendingPathComponent(invalidFixture))
      #expect(invalid.status != 0, "\(annotation.name) invalid fixture unexpectedly built")
      #expect(invalid.output.contains(diagnostic), "\(annotation.name) invalid fixture lost its diagnostic category:\n\(invalid.output)")
    }

  }

  @Test("unimplemented annotations cannot be treated as release support")
  func unimplementedAnnotationsAreExplicitlyNarrowed() throws {
    let inventory = try loadInventory()
    let validated = try #require(inventory.annotations.first { $0.name == "@TLAValidated" })

    #expect(validated.advertised == false)
    #expect(validated.decision == "removeBeforeRelease")
    #expect(validated.positiveFixture == nil)
    #expect(validated.invalidFixture == nil)
    #expect(validated.reason?.isEmpty == false)
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

  private func runSwift(_ command: String, in fixture: URL) throws -> (status: Int32, output: String) {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-public-workflow-fixture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", command, "--package-path", fixture.path, "--scratch-path", scratch.path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    return (
      process.terminationStatus,
      String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
    let positiveFixture: String?
    let invalidFixture: String?
    let positiveCommand: String?
    let expectedPositiveOutcome: String?
    let expectedInvalidOutcome: String?
    let diagnosticCategory: String?
    let diagnosticText: String?
    let reason: String?
    let sourceInputs: [String]
  }
}
