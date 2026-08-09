import Foundation
import Testing

@Suite(.serialized)
struct ReadmeSymmetricCollectionTests {
  @Test("README symmetric collection model compiles, retains its invariant, and checks")
  func readmeModelCompilesAndChecks() throws {
    let root = packageRoot()
    let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    let fixture = root.appendingPathComponent("Tests/Fixtures/ReadmeSymmetricCollectionMacro")
    let source = try String(
      contentsOf: fixture.appendingPathComponent(
        "Sources/ReadmeSymmetricCollectionMacro/ReadmeSymmetricCollectionMacro.swift"
      ),
      encoding: .utf8
    )

    #expect(source.hasPrefix(symmetricCollectionSnippet(in: readme) + "\n\nlet generatedSpec"))

    let result = try runSwift(["run", "--package-path", fixture.path])
    #expect(result.status == 0, "README fixture failed:\n\(result.output)")
  }

  @Test("An invalid modeled phase fails macro-time checking")
  func invalidPhaseFailsMacroTimeCheck() throws {
    let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidReadmePhaseMacro")
    let result = try runSwift(["build", "--package-path", fixture.path])

    #expect(result.status != 0)
    #expect(result.output.contains("validPhase"))
    #expect(result.output.localizedCaseInsensitiveContains("invariant"))
  }

  private func symmetricCollectionSnippet(in readme: String) -> String {
    guard let section = readme.range(of: "## Symmetric collections"),
          let opening = readme.range(of: "```swift", range: section.upperBound..<readme.endIndex),
          let closing = readme.range(of: "```", range: opening.upperBound..<readme.endIndex)
    else {
      Issue.record("README symmetric collection Swift snippet is missing")
      return ""
    }
    return String(readme[opening.upperBound..<closing.lowerBound]).trimmingCharacters(in: .newlines)
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

  private func packageRoot() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
      directory.deleteLastPathComponent()
    }
    return directory
  }
}
