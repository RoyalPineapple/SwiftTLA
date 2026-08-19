import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowConformanceRunnerTests {
  @Test("runner writes one correlated diagnostic report for the declared portable corpus")
  func runnerWritesMatchedDiagnosticReport() throws {
    let root = try throwingPackageRoot()
    let output = root.appending(path: ".build/PublicWorkflowConformanceRunnerTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: output) }

    let result = try PublicWorkflowConformanceRunnerV1().run(.init(
      projectRoot: root, outputRoot: output, hostedCI: false, runFixtures: false, runPlatformMatrix: false))

    #expect(result.report.schema == PublicWorkflowDiagnosticReportV1.schema)
    if case .diagnostic = result.report.authority {} else { Issue.record("report must be diagnostic locally") }
    #expect(result.report.claimStatus == "diagnosticOnly")
    let diagnostic = result.report.checks.compactMap(\.diagnostic).joined(separator: "\n")
    #expect(result.report.checks.count == 6, Comment(rawValue: diagnostic))
    #expect(result.report.checks.allSatisfy { $0.status == .matched })
    if case .success = result.report.finalExitClass {} else { Issue.record("matched corpus must succeed") }
    #expect(FileManager.default.fileExists(atPath: result.reportURL.path))
    let persisted = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self, from: Data(contentsOf: result.reportURL))
    #expect(persisted.checks.map(\.id) == result.report.checks.map(\.id))
    let current = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self, from: Data(contentsOf: output.appending(path: "support-admission.json")))
    #expect(current.runID == persisted.runID)
  }

  @Test("missing register writes an unavailable report")
  func missingRegisterIsUnavailable() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "PublicWorkflowRunnerMissingRegister-\(UUID())")
    let output = root.appending(path: "output")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let result = try PublicWorkflowConformanceRunnerV1().run(.init(
      projectRoot: root, outputRoot: output, hostedCI: false, runFixtures: false, runPlatformMatrix: false))

    #expect(result.report.checks.count == 1)
    #expect(result.report.checks[0].status == .unavailable)
    if case .unavailable = result.report.finalExitClass {} else { Issue.record("missing register must be unavailable") }
    #expect(FileManager.default.fileExists(atPath: output.appending(path: "support-admission.json").path))
  }

  @Test("completed disagreement maps to the blocked exit class")
  func completedDifferenceIsBlocked() {
    let report = PublicWorkflowDiagnosticReportV1(
      runID: UUID(), authority: .diagnostic,
      checks: [PublicWorkflowDiagnosticCheckV1(
        id: "difference", command: "fixture", status: .differed,
        expectedOutcome: .exact, actualOutcome: .difference, evidence: [], diagnostic: "observations differ")])

    if case .blocked = report.finalExitClass {} else { Issue.record("completed difference must return exit 1") }
  }

  @Test("public-workflow CLI binds the declared platform command digest and retains 0, 1, and 2 reports")
  func cliUsesCanonicalPlatformCommandDigestAndRetainsExitClasses() throws {
    let root = try throwingPackageRoot()
    let temporary = root.appending(path: ".build/PublicWorkflowCLIRunner-\(UUID())")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let xcodebuild = try fakeXcodebuild(at: temporary)
    let binary = try buildCLI(root: root, derivedData: temporary.appending(path: "derived-data"))

    for (mode, exitCode, expectedExit) in [("matched", 0, "success"), ("differed", 1, "blocked"), ("platform-failure", 1, "blocked"), ("unavailable", 2, "unavailable")] {
      let output = temporary.appending(path: mode)
      let result = try run(binary, from: root, arguments: ["public-workflow", "--output", output.path], environment: [
        "PUBLIC_WORKFLOW_ANNOTATION_XCODEBUILD": xcodebuild.path,
        "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": xcodebuild.path,
        "PUBLIC_WORKFLOW_FAKE_MODE": mode
      ])
      #expect(result == exitCode)
      let report = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self, from: Data(contentsOf: output.appending(path: "support-admission.json")))
      #expect(report.checks.contains(where: { $0.id == "annotation-fixtures" }))
      #expect(report.checks.contains(where: { $0.id == "public-library-platform-matrix" }))
      #expect(report.finalExitClass.rawValue == expectedExit)
      let retained = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self, from: Data(contentsOf: output.appending(path: "runs/\(report.runID.uuidString.lowercased())/support-admission.json")))
      #expect(retained.runID == report.runID)
      #expect(retained.finalExitClass.rawValue == expectedExit)

      if mode == "platform-failure" {
        let platform = try #require(report.checks.first(where: { $0.id == "public-library-platform-matrix" }))
        #expect(platform.status == .differed)
        #expect(platform.actualOutcome == .difference)
        #expect(!platform.evidence.isEmpty)
      }

      let context = try #require(report.checks
        .first(where: { $0.id == "public-library-platform-matrix" })?
        .evidence.first(where: { $0.path.hasSuffix("binding-context.json") }))
      let contextJSON = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: root.appending(path: context.path))) as? [String: Any])
      let provenance = try #require(contextJSON["provenance"] as? [String: Any])
      let commands: [[String]] = [
        ["xcodebuild", "-scheme", "SwiftTLA-Package", "-target", "SwiftTLA", "-sdk", "macosx", "-destination", "platform=macOS", "build"]
      ]
      let canonical = try JSONSerialization.data(
        withJSONObject: commands, options: [.sortedKeys, .withoutEscapingSlashes])
      #expect(provenance["argumentsSHA256"] as? String == SHA256V1.hex(canonical))
    }
  }

  @Test("release wrapper retains every declared permanent public-workflow control as local diagnostic evidence")
  func releaseWrapperRetainsDeclaredControls() throws {
    let root = try throwingPackageRoot()
    let temporary = root.appending(path: ".build/PublicWorkflowReleaseControls-\(UUID())")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let xcodebuild = try fakeXcodebuild(at: temporary)
    let exit = try run(URL(fileURLWithPath: "/bin/bash"), from: root,
      arguments: ["scripts/run_public_workflow_support_gate.sh", "--output", temporary.appending(path: "evidence").path],
      environment: [
        "PUBLIC_WORKFLOW_ANNOTATION_XCODEBUILD": xcodebuild.path,
        "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": xcodebuild.path,
      ])
    #expect(exit == 0)

    let report = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
      from: Data(contentsOf: temporary.appending(path: "evidence/support-admission.json")))
    #expect(report.authority == .diagnostic)
    #expect(report.claimStatus == "diagnosticOnly")
    #expect(report.finalExitClass == .success)
    let expected: [String: PublicWorkflowExpectedOutcomeV1] = [
      "parser-builder-bounded-counter": .exact,
      "parser-builder-bounded-counter-mismatch": .difference,
      "p4-generated-counter": .exact,
      "p4-generated-counter-intentional-mismatch": .difference,
      "p4-generated-counter-evaluation-failed": .difference,
      "p4-generated-counter-evaluation-unavailable": .difference,
      "annotation-fixtures": .exact,
      "public-library-platform-matrix": .exact,
    ]
    #expect(Dictionary(uniqueKeysWithValues: report.checks.map { ($0.id, $0.expectedOutcome) }) == expected)
    #expect(report.checks.allSatisfy { $0.status == .matched && $0.actualOutcome == $0.expectedOutcome && !$0.evidence.isEmpty })
    let annotation = try #require(report.checks.first(where: { $0.id == "annotation-fixtures" }))
    let validFixtureLog = try #require(annotation.evidence.first(where: { $0.path.hasSuffix("TLAModel-valid/stdout.log") }))
    #expect(try String(contentsOf: root.appending(path: validFixtureLog.path), encoding: .utf8).contains("SWIFT_SUPPRESS_WARNINGS=NO"))
    let retained = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
      from: Data(contentsOf: temporary.appending(path: "evidence/runs/\(report.runID.uuidString.lowercased())/support-admission.json")))
    #expect(retained.runID == report.runID)
  }

  @Test("release wrapper preserves CLI report and exit classes")
  func releaseWrapperPropagatesReportAndExitClasses() throws {
    let root = try throwingPackageRoot()
    let temporary = root.appending(path: ".build/PublicWorkflowReleaseExitClasses-\(UUID())")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let xcodebuild = try fakeXcodebuild(at: temporary)

    for (mode, expectedExit, expectedClass) in [("matched", 0, PublicWorkflowAdmissionExitClassV1.success), ("platform-failure", 1, .blocked), ("unavailable", 2, .unavailable)] {
      let output = temporary.appending(path: mode)
      let exit = try run(URL(fileURLWithPath: "/bin/bash"), from: root,
        arguments: ["scripts/run_public_workflow_support_gate.sh", "--output", output.path],
        environment: [
          "PUBLIC_WORKFLOW_ANNOTATION_XCODEBUILD": xcodebuild.path,
          "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": xcodebuild.path,
          "PUBLIC_WORKFLOW_FAKE_MODE": mode,
        ])
      #expect(exit == expectedExit)

      let report = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
        from: Data(contentsOf: output.appending(path: "support-admission.json")))
      #expect(report.finalExitClass == expectedClass)
      let retained = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
        from: Data(contentsOf: output.appending(path: "runs/\(report.runID.uuidString.lowercased())/support-admission.json")))
      #expect(retained.runID == report.runID)
      #expect(retained.finalExitClass == expectedClass)
    }
  }

  @Test("missing and digest-drifted public-workflow evidence retain unavailable reports")
  func invalidEvidenceFailsClosedWithStableDiagnostics() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "PublicWorkflowInvalidEvidence-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    for (name, body, expectedDiagnostic) in [
      ("missing", nil, "missing evidence"),
      ("drift", "{}", "SHA-256"),
    ] as [(String, String?, String)] {
      let verification = root.appending(path: "Verification/PublicWorkflowConformance")
      try FileManager.default.createDirectory(at: verification, withIntermediateDirectories: true)
      let manifest = verification.appending(path: "\(name).json")
      if let body { try body.write(to: manifest, atomically: true, encoding: .utf8) }
      let register = """
      {"schema":"PublicWorkflowRunnerRegisterV1","parserBuilder":[{"id":"\(name)","manifest":{"path":"Verification/PublicWorkflowConformance/\(name).json","sha256":"\(String(repeating: "a", count: 64))"},"expectedOutcome":"exact"}],"generatedBehavior":{"path":"Verification/PublicWorkflowConformance/unused.json","sha256":"\(String(repeating: "a", count: 64))"}}
      """
      try register.write(to: verification.appending(path: "runner.json"), atomically: true, encoding: .utf8)
      let output = root.appending(path: "output-\(name)")
      let result = try PublicWorkflowConformanceRunnerV1().run(.init(
        projectRoot: root, outputRoot: output, hostedCI: false, runFixtures: false, runPlatformMatrix: false))
      #expect(result.report.finalExitClass == .unavailable)
      #expect(result.report.checks.count == 1)
      #expect(result.report.checks[0].status == .unavailable)
      #expect(result.report.checks[0].diagnostic?.contains(expectedDiagnostic) == true)
      let persisted = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
        from: Data(contentsOf: output.appending(path: "support-admission.json")))
      #expect(persisted.finalExitClass == .unavailable)
    }
  }

  @Test("a local hosted flag remains diagnostic without a GitHub Actions identity")
  func localHostedFlagCannotCreateCandidateEvidence() throws {
    let root = try throwingPackageRoot()
    let temporary = root.appending(path: ".build/PublicWorkflowLocalHostedFlag-\(UUID())")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let xcodebuild = try fakeXcodebuild(at: temporary)
    let binary = try buildCLI(root: root, derivedData: temporary.appending(path: "derived-data"))
    let output = temporary.appending(path: "evidence")
    let exit = try run(binary, from: root,
      arguments: ["public-workflow", "--hosted-ci", "--output", output.path],
      environment: [
        "PUBLIC_WORKFLOW_ANNOTATION_XCODEBUILD": xcodebuild.path,
        "PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD": xcodebuild.path,
      ],
      scrubbing: [
        "GITHUB_ACTIONS", "GITHUB_SHA", "GITHUB_REPOSITORY", "GITHUB_WORKFLOW", "GITHUB_REF",
        "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB", "GITHUB_SERVER_URL",
      ])
    #expect(exit == 0)
    let report = try JSONDecoder().decode(PublicWorkflowDiagnosticReportV1.self,
      from: Data(contentsOf: output.appending(path: "support-admission.json")))
    #expect(report.authority == .diagnostic)
    #expect(report.claimStatus == "diagnosticOnly")
  }

  private func buildCLI(root: URL, derivedData: URL) throws -> URL {
    let result = try run(URL(fileURLWithPath: "/usr/bin/xcodebuild"), from: root,
      arguments: ["-scheme", "tlc-validate", "-sdk", "macosx", "-destination", "platform=macOS", "-derivedDataPath", derivedData.path, "build"], environment: [:])
    guard result == 0 else { throw CocoaError(.executableNotLoadable) }
    return derivedData.appending(path: "Build/Products/Debug/tlc-validate")
  }

  private func fakeXcodebuild(at directory: URL) throws -> URL {
    let executable = directory.appending(path: "xcodebuild")
    try """
    #!/bin/bash
    if [ "${PUBLIC_WORKFLOW_FAKE_MODE:-matched}" = "unavailable" ]; then exit 127; fi
    echo "$*"
    if [[ "$*" == *"Invalid"* ]]; then echo "Invariant 'withinBounds' violated"; exit 1; fi
    if [ "${PUBLIC_WORKFLOW_FAKE_MODE:-matched}" = "differed" ] && [[ "$*" == *"TLAModelValid"* ]]; then exit 1; fi
    if [ "${PUBLIC_WORKFLOW_FAKE_MODE:-matched}" = "platform-failure" ] && [[ "$*" == *"SwiftTLA-Package"* ]]; then echo "platform build failed"; exit 65; fi
    echo "Xcode 27.0"
    exit 0
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable
  }

  private func run(
    _ executable: URL,
    from directory: URL,
    arguments: [String],
    environment: [String: String],
    scrubbing keys: Set<String> = []
  ) throws -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = directory
    process.arguments = arguments
    var processEnvironment = ProcessInfo.processInfo.environment
    for key in keys {
      processEnvironment.removeValue(forKey: key)
    }
    process.environment = processEnvironment.merging(environment, uniquingKeysWith: { _, replacement in replacement })
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
