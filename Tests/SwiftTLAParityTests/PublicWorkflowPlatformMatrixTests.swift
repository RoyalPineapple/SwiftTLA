import Foundation
import Testing
@testable import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowPlatformMatrixTests {
  @Test("platform matrix emits decodable succeeded, failed, and unavailable evidence")
  func emittedPlatformEvidenceMatchesContract() throws {
    let root = try throwingPackageRoot()
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
      #expect(evidence.correlation.caseID == "public-library-macos")
      #expect(evidence.correlation.platformRunID != evidence.correlation.gateRunID)
      #expect(evidence.fixtureBinding.evidence == evidence.fixture)
      #expect(evidence.stdoutBinding.evidence == evidence.stdout)
      #expect(evidence.stderrBinding.evidence == evidence.stderr)
    }
  }

  private enum Outcome { case succeeded, failed, unavailable }

  private func makeContext(at url: URL) throws -> URL {
    let digest = String(repeating: "a", count: 64)
    let root = try throwingPackageRoot()
    let sourcePath = "Tests/Fixtures/PublicWorkflowConformance/Platform/assert_platform_matrix.sh"
    let configurationPath = "Package.swift"
    let sourceDigest = SHA256.hex(try Data(contentsOf: root.appendingPathComponent(sourcePath)))
    let configurationDigest = SHA256.hex(try Data(contentsOf: root.appendingPathComponent(configurationPath)))
    let source = try CoreEvidenceReference(path: sourcePath, sha256: sourceDigest)
    let configuration = try CoreEvidenceReference(path: configurationPath, sha256: configurationDigest)
    let provenance = try CoreEvidenceProvenance(
      caseID: "public-library-macos", moduleSHA256: sourceDigest, cfgSHA256: configurationDigest,
      argumentsSHA256: SHA256.hex(try JSONEncoder().encode([["xcodebuild", "-scheme", "SwiftTLA-Package", "-target", "SwiftTLA", "-sdk", "macosx", "-destination", "platform=macOS", "build"]])),
      tlcTag: "v1.8.0", tlcCommit: "30cc3601321c3fc02e044d0ecb5c58d8921e18df", tlcJarSHA256: digest,
      javaDistribution: "Eclipse Temurin", javaVersion: "17.0.19+10", javaArchiveSHA256: digest,
      bridgeClass: "org.swifttla.conformance.LosslessStateWriter", bridgeSourceSHA256: digest,
      bridgeBinarySHA256: digest)
    let context = BindingContext(
      caseID: "public-library-macos",
      gateRunID: try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111")),
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

  private func runMatrix(root: URL, output: URL, context: URL, executable: URL, expectedExit: Int32) throws -> PublicWorkflowPlatformEvidence {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      root.appendingPathComponent("scripts/run_public_workflow_platform_matrix.sh").path,
      "--output", output.path,
      "--context", context.path,
    ]
    process.environment = ProcessInfo.processInfo.environment.merging([
      "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": executable.path,
      "PUBLIC_WORKFLOW_PLATFORM_MATRIX": "macos|macosx|platform=macOS|build|SwiftTLA",
    ]) { _, replacement in replacement }
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == expectedExit)

    let runDirectory = try #require(try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("runs"), includingPropertiesForKeys: nil).first)
    return try JSONDecoder().decode(
      PublicWorkflowPlatformEvidence.self,
      from: Data(contentsOf: runDirectory.appendingPathComponent("platforms/macos/result.json")))
  }

  private struct BindingContext: Encodable {
    let caseID: String
    let gateRunID: UUID
    let sourceInput: CoreEvidenceReference
    let configuration: CoreEvidenceReference
    let provenance: CoreEvidenceProvenance
  }
}
