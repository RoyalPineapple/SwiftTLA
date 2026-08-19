import Foundation
import Testing

@Suite(.serialized)
struct ReadmeSymmetricCollectionTests {
  @Test("symmetric collection fixture compiles, retains its invariant, and checks")
  func symmetricCollectionFixtureCompilesAndChecks() throws {
    let root = packageRoot()
    let fixture = root.appendingPathComponent("Tests/Fixtures/ReadmeSymmetricCollectionMacro")

    let result = try runSwift(["run", "--package-path", fixture.path])
    #expect(result.status == 0, "symmetric collection fixture failed:\n\(result.output)")
  }

  @Test("An invalid modeled phase fails macro-time checking")
  func invalidPhaseFailsMacroTimeCheck() throws {
    let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidReadmePhaseMacro")
    let result = try runSwift(["build", "--package-path", fixture.path])

    #expect(result.status != 0)
    #expect(result.output.contains("validPhase"))
    #expect(result.output.localizedCaseInsensitiveContains("invariant"))
  }

  private func runSwift(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-readme-fixture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift"] + arguments + ["--scratch-path", scratch.path]
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
