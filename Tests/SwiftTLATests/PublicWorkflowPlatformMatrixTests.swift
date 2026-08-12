import Foundation
import Testing
@testable import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowPlatformMatrixTests {
  @Test("platform matrix emits V1-decodable succeeded, failed, and unavailable evidence")
  func emittedPlatformEvidenceMatchesV1Contract() throws {
    let root = try packageRoot()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PublicWorkflowPlatformMatrixTests-\(UUID())")
    let outputRoot = root.appendingPathComponent(".build/PublicWorkflowPlatformMatrixTests-\(UUID())")
    defer {
      try? FileManager.default.removeItem(at: scratch)
      try? FileManager.default.removeItem(at: outputRoot)
    }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let context = try makeContext(at: scratch.appendingPathComponent("context.json"))

    let succeeded = try runMatrix(root: root, output: outputRoot.appendingPathComponent("succeeded"), context: context,
                                  executable: try fakeXcodebuild(at: scratch, outcome: .succeeded), expectedExit: 0)
    #expect(succeeded.status == .succeeded)
    #expect(succeeded.exitCode == 0)

    let failed = try runMatrix(root: root, output: outputRoot.appendingPathComponent("failed"), context: context,
                               executable: try fakeXcodebuild(at: scratch, outcome: .failed), expectedExit: 2)
    #expect(failed.status == .failed)
    #expect(failed.exitCode == 65)

    let unavailable = try runMatrix(root: root, output: outputRoot.appendingPathComponent("unavailable"), context: context,
                                    executable: try fakeXcodebuild(at: scratch, outcome: .unavailable), expectedExit: 2)
    #expect(unavailable.status == .unavailable)
    #expect(unavailable.exitCode == nil)

    for evidence in [succeeded, failed, unavailable] {
      #expect(evidence.platform == "macos")
      #expect(evidence.sdk == "macosx")
      #expect(evidence.destination == "platform=macOS")
      #expect(evidence.command.contains("xcodebuild"))
      #expect(evidence.xcodeVersion == "Xcode Fake")
      #expect(evidence.correlation.caseID == "nested-package-macos")
      #expect(evidence.correlation.platformRunID != evidence.correlation.gateRunID)
      #expect(evidence.fixtureBinding.evidence == evidence.fixture)
      #expect(evidence.stdoutBinding.evidence == evidence.stdout)
      #expect(evidence.stderrBinding.evidence == evidence.stderr)
    }
  }

  private enum Outcome { case succeeded, failed, unavailable }

  private func packageRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
      let parent = directory.deletingLastPathComponent()
      guard parent != directory else { throw CocoaError(.fileNoSuchFile) }
      directory = parent
    }
    return directory
  }

  private func makeContext(at url: URL) throws -> URL {
    let digest = String(repeating: "a", count: 64)
    let root = try packageRoot()
    let sourcePath = "Tests/Fixtures/PublicWorkflowConformance/Platform/assert_platform_matrix.sh"
    let configurationPath = "Packages/SwiftTLAVerified/Package.swift"
    let sourceDigest = SHA256V1.hex(try Data(contentsOf: root.appendingPathComponent(sourcePath)))
    let configurationDigest = SHA256V1.hex(try Data(contentsOf: root.appendingPathComponent(configurationPath)))
    let source = try CoreEvidenceReferenceV1(path: sourcePath, sha256: sourceDigest)
    let configuration = try CoreEvidenceReferenceV1(path: configurationPath, sha256: configurationDigest)
    let provenance = try CoreDivergenceProvenanceV1(
      caseID: "nested-package-macos", moduleSHA256: sourceDigest, cfgSHA256: configurationDigest,
      argumentsSHA256: SHA256V1.hex(try JSONEncoder().encode([["xcodebuild", "-scheme", "SwiftTLAVerified-Package", "-sdk", "macosx", "-destination", "platform=macOS", "test"]])),
      tlcTag: "v1.8.0", tlcCommit: "30cc3601321c3fc02e044d0ecb5c58d8921e18df", tlcJarSHA256: digest,
      javaDistribution: "Eclipse Temurin", javaVersion: "17.0.19+10", javaArchiveSHA256: digest,
      bridgeClass: "org.swifttla.conformance.LosslessStateWriter", bridgeSourceSHA256: digest,
      bridgeBinarySHA256: digest)
    let context = BindingContext(
      caseID: "nested-package-macos", gateRunID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
      sourceInput: source, configuration: configuration, provenance: provenance)
    try JSONEncoder().encode(context).write(to: url)
    return url
  }

  private func fakeXcodebuild(at scratch: URL, outcome: Outcome) throws -> URL {
    let executable = scratch.appendingPathComponent("xcodebuild-\(UUID())")
    let body: String
    switch outcome {
    case .succeeded:
      body = "echo build-succeeded; exit 0"
    case .failed:
      body = "echo compile-failed >&2; exit 65"
    case .unavailable:
      body = "echo 'Unable to find a destination matching the provided destination specifier' >&2; exit 70"
    }
    try "#!/bin/bash\nif [ \"$1\" = \"-version\" ]; then echo 'Xcode Fake'; exit 0; fi\n\(body)\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable
  }

  private func runMatrix(root: URL, output: URL, context: URL, executable: URL, expectedExit: Int32) throws -> PublicWorkflowPlatformEvidenceV1 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      root.appendingPathComponent("scripts/run_public_workflow_platform_matrix.sh").path,
      "--output", output.path,
      "--context", context.path,
    ]
    process.environment = ProcessInfo.processInfo.environment.merging([
      "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": executable.path,
      "PUBLIC_WORKFLOW_PLATFORM_MATRIX": "macos|macosx|platform=macOS|test",
    ]) { _, replacement in replacement }
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == expectedExit)

    let runDirectory = try #require(try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("runs"), includingPropertiesForKeys: nil).first)
    return try JSONDecoder().decode(
      PublicWorkflowPlatformEvidenceV1.self,
      from: Data(contentsOf: runDirectory.appendingPathComponent("platforms/macos/result.json")))
  }

  private struct BindingContext: Encodable {
    let caseID: String
    let gateRunID: UUID
    let sourceInput: CoreEvidenceReferenceV1
    let configuration: CoreEvidenceReferenceV1
    let provenance: CoreDivergenceProvenanceV1
  }
}
