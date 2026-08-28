import Darwin
import Foundation
import Testing
import SwiftTLA
import UpstreamParity
@Suite(.serialized)
struct TLCGraphReaderTests { @Test("frozen graph stream becomes complete canonical evidence")
  func parsesFrozenGraphIntoCompletedGraphRun() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let result = TLCProcessResult(
      status: 0,
      stdout: "Model checking completed. No error has been found.",
      stderr: ""
    )
    let run = try reader.readCompletedGraph(try completeGraphStream(finiteGraphCase), result: result)
    #expect(run.isPassEligible)
    #expect(run.graph.initialStateKeys.count == 1)
    #expect(run.graph.edgeOccurrences.values.sorted() == [1])
    #expect(run.observableActions == ["Next"])
  }

  @Test("TLC stages only the declared bundle, never sibling TLA files")
  func stagesOnlyDeclaredBundle() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let root = directory.appendingPathComponent("OnlyThis.tla")
    let cfg = directory.appendingPathComponent("OnlyThis.cfg")
    try "---- MODULE OnlyThis ----\n====\n".write(to: root, atomically: true, encoding: .utf8)
    try "SPECIFICATION Spec\n".write(to: cfg, atomically: true, encoding: .utf8)
    try "---- MODULE StaleSibling ----\n====\n".write(
      to: directory.appendingPathComponent("StaleSibling.tla"), atomically: true, encoding: .utf8)
    let request = TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: directory.appendingPathComponent("tla2tools.jar"),
      bridgeClasses: directory.appendingPathComponent("bridge"),
      bundle: try TLCProcessRequest.declaredBundle(root: root, configuration: cfg),
      graphEvents: directory.appendingPathComponent("events.jsonl"),
      traceOutput: directory.appendingPathComponent("trace.json"),
      workingDirectory: directory.appendingPathComponent("work"),
      finiteGraphCase: try fixtureCase(try toolchainPin()),
      runID: UUID()
    )

    let staged = try request.stageDeclaredBundle()
    let names = try FileManager.default.contentsOfDirectory(
      at: staged.module.deletingLastPathComponent(), includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).sorted()
    #expect(names == ["OnlyThis.cfg", "OnlyThis.tla"])
  }

  @Test("the TLC pin matches the locked standard-module inventory")
  func pinnedInventoryMatchesTheToolchainLock() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
    let lock = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tlc = try #require(lock["tlc"] as? [String: Any])
    let names = try #require(tlc["standardModules"] as? [String])

    #expect(Set(names) == TLCReferencePin.standardModuleNames)
  }

  @Test("TLC violations remain non-passing canonical outcomes")
  func preservesViolationOutcome() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let run = try TLCGraphReader(finiteGraphCase: finiteGraphCase).readCompletedGraph(
      try completeGraphStream(finiteGraphCase),
      result: TLCProcessResult(
        status: 12,
        stdout: "Error: Invariant broken is violated.",
        stderr: ""
      )
    )
    #expect(!run.isPassEligible)
    #expect(run.outcome == .invariantViolation("Error: Invariant broken is violated."))
  }

  @Test("a violation path cannot replace TLC's invariant diagnostic")
  func ignoresViolationInInputPath() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let run = try TLCGraphReader(finiteGraphCase: finiteGraphCase).readCompletedGraph(
      try completeGraphStream(finiteGraphCase),
      result: TLCProcessResult(
        status: 12,
        stdout: "Parsing file /tmp/invariant-violation/DieHard.tla\nError: Invariant NotSolved is violated.",
        stderr: ""
      )
    )
    #expect(run.outcome == .invariantViolation("Error: Invariant NotSolved is violated."))
  }

  @Test("toolchain pin rejects malformed lock fields")
  func rejectsMalformedToolchainFields() throws {
    let pin = try toolchainPin()
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: String(repeating: "g", count: 64),
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: "not-a-revision", jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256,
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: "",
        bridgeSourceSHA256: pin.bridgeSourceSHA256,
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("the locked reference pin validates the compiled bridge artifact")
  func validatesCompiledBridgeArtifact() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard let toolRoot = ProcessInfo.processInfo.environment["FINITE_GRAPH_TOOL_ROOT"].map(URL.init(fileURLWithPath:)) else {
      return
    }
    let artifacts = TLCReferenceArtifacts(
      jar: toolRoot.appendingPathComponent("downloads/tla2tools.jar"),
      javaArchive: toolRoot.appendingPathComponent("downloads/temurin-arm64.tar.gz"),
      bridgeSource: root.appendingPathComponent(
        "Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java"),
      bridgeBinary: toolRoot.appendingPathComponent(
        "bridge-classes/org/swifttla/conformance/LosslessStateWriter.class"),
      jarManifest:
        "Implementation-Title: TLA+ Tools\\nX-Git-Revision: 9787e65714c37d94eebab40774bff401bd9f616d\\n",
      runtime: TLCJavaRuntimeIdentity(
        version: "17.0.19+10", vendor: "Eclipse Adoptium", architecture: "arm64",
        properties: ["java.runtime.version": "17.0.19+10", "java.vendor": "Eclipse Adoptium"]
      )
    )
    try toolchainPin().validate(artifacts)
    let emptyManifest = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: "", runtime: artifacts.runtime
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("TLC JAR manifest")) {
      try toolchainPin().validate(emptyManifest)
    }
    let mismatchedRuntime = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: artifacts.jarManifest,
      runtime: TLCJavaRuntimeIdentity(
        version: "17.0.19+11", vendor: artifacts.runtime.vendor,
        architecture: artifacts.runtime.architecture,
        properties: [
          "java.runtime.version": "17.0.19+11",
          "java.vendor": artifacts.runtime.vendor
        ]
      )
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("Java runtime")) {
      try toolchainPin().validate(mismatchedRuntime)
    }
  }

  @Test("TLC command selects the bridge and identifies its graph stream")
  func assemblesFrozenBridgeCommand() throws {
    let request = TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
      bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
      bundle: fixtureBundle(),
      graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
      traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      finiteGraphCase: try fixtureCase(try toolchainPin(), arguments: ["-workers", "1"]),
      runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
      traceMode: .dumpJSON
    )
    let command = request.launchArguments
    #expect(command.contains("-Dswifttla.tlc.graph.path=/tmp/events.jsonl"))
    #expect(command.contains("-Dswifttla.tlc.graph.run-id=00000000-0000-4000-8000-000000000001"))
    #expect(command.contains("-Dswifttla.tlc.graph.case-id=fixture"))
    #expect(command.contains("/tmp/tla2tools.jar:/tmp/bridge-classes"))
    #expect(command.contains("-dumpTrace"))
    #expect(command.contains("/tmp/trace.json"))
  }

  @Test("execution rejects substituted JAR and bridge classpath artifacts")
  func rejectsSubstitutedExecutionArtifacts() throws {
    let root = URL(fileURLWithPath: "/tmp/validated-bridge")
    let artifacts = TLCReferenceArtifacts(
      jar: URL(fileURLWithPath: "/tmp/validated-tla2tools.jar"),
      javaArchive: URL(fileURLWithPath: "/tmp/temurin.tar.gz"),
      bridgeSource: URL(fileURLWithPath: "/tmp/LosslessStateWriter.java"),
      bridgeBinary: root.appendingPathComponent(
        "org/swifttla/conformance/LosslessStateWriter.class"),
      jarManifest: "",
      runtime: TLCJavaRuntimeIdentity(version: "", vendor: "", architecture: "", properties: [:])
    )
    let substitutedJar = try requestWithReferenceArtifacts(
      jar: URL(fileURLWithPath: "/tmp/substituted-tla2tools.jar"), bridgeClasses: root,
      artifacts: artifacts
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("execution TLC JAR")) {
      try substitutedJar.validateReferenceBinding(artifacts: artifacts)
    }
    let substitutedBridge = try requestWithReferenceArtifacts(
      jar: artifacts.jar, bridgeClasses: URL(fileURLWithPath: "/tmp/substituted-bridge"),
      artifacts: artifacts
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("execution bridge class")) {
      try substitutedBridge.validateReferenceBinding(artifacts: artifacts)
    }
  }

  @Test("TLC v1.8.0 counterexample parses as trace-only evidence")
  func parsesCounterexampleFixture() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let traceURL =
      testFile
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/FiniteGraph/TLCTrace/violation-counterexample.json")
    let evidence = try TLCTraceParser().parseCounterexample(Data(contentsOf: traceURL))
    #expect(evidence.states.count == 4)
    #expect(evidence.actions == ["Next", "Next", "Next"])
    #expect(
      evidence.states.map { $0.bindings["x"] } == [
        .integer(0), .integer(1), .integer(2), .integer(3)
      ])
    #expect(evidence.canonicalTrace(id: "violation").steps.count == 3)
  }
}

extension TLCGraphReaderTests {
  @Test("timeout is reported even when no output arrives before termination")
  func timeoutDoesNotAssumeOutputWasProducedBeforeTermination() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("slow-java.sh")
    let module = directory.appendingPathComponent("Module.tla")
    let configuration = directory.appendingPathComponent("Module.cfg")
    try "---- MODULE Module ----\n====\n".write(to: module, atomically: true, encoding: .utf8)
    try "SPECIFICATION Spec\n".write(to: configuration, atomically: true, encoding: .utf8)
    try "#!/bin/sh\ntrap '' TERM\nwhile true; do /bin/sleep 0.1; done\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let request = TLCProcessRequest(
      javaExecutable: executable, jar: URL(fileURLWithPath: "/tmp/jar"), bridgeClasses: directory,
      bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
      graphEvents: directory.appendingPathComponent("events.jsonl"),
      traceOutput: directory.appendingPathComponent("trace.json"),
      workingDirectory: directory,
      finiteGraphCase: try caseForFiles(
        id: "timeout", module: module, configuration: configuration, arguments: []),
      runID: UUID(), timeout: 0.25
    )
    let started = Date()
    #expect(throws: TLCProcessError.self) {
      _ = try SystemTLCProcessExecutor(validatesReferences: false).execute(request)
    }
    #expect(Date().timeIntervalSince(started) < 3)
  }

  @Test("production TLC execution rejects a banner outside the pinned revision")
  func rejectsWrongTLCBanner() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("wrong-banner.sh")
    try "#!/bin/sh\nprintf 'TLC2 Version 2026.07.31.184830 (rev: deadbee)\\n'\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let request = try helperProcessRequest(executable: executable, in: directory, environment: [:])
    #expect(throws: FiniteGraphCaseError.pinMismatch("TLC banner")) {
      _ = try SystemTLCProcessExecutor(validatesReferences: false).execute(request)
    }
  }

  @Test("production TLC execution uses only the declared environment")
  func excludesHostEnvironmentAndPreservesAllowlist() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("environment.sh")
    try "#!/bin/sh\n"
      .appending("printf 'TLC2 Version 2026.08.11.125311 (rev: 9787e65)\\n'\n")
      .appending("printf 'home=%s allowed=%s\\n' \"${HOME-unset}\" \"${FINITE_GRAPH_ALLOWED_VALUE-unset}\"\n")
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let request = try helperProcessRequest(
      executable: executable,
      in: directory,
      environment: ["FINITE_GRAPH_ALLOWED_VALUE": "declared"]
    )
    let result = try SystemTLCProcessExecutor(validatesReferences: false).execute(request)
    #expect(result.stdout.contains("home=unset allowed=declared"))
  }

  @Test("graph event reader rejects malformed footer and unsupported callbacks")
  func rejectsMalformedStreams() throws {
    let pin = try toolchainPin()
    let finiteGraphCase = try fixtureCase(pin)
    let stream = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data("{\"not\":\"jsonl footer\"}\n".utf8))
    }
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data("{\"schema\":\"x\",\"schema\":\"x\"}\n".utf8))
    }
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data("{\"schema\":\"x\",\"sche\\u006da\":\"x\"}\n".utf8))
    }
    let invalidInitial = [
      "\(try header(finiteGraphCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":2,\"type\":\"initial\",",
      "\"callback\":\"writeState.initial\",\"seq\":2,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"state\":{}}\n"
    ].joined()
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data(invalidInitial.utf8))
    }
    let unsupportedCallback = [
      "\(try header(finiteGraphCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":2,\"type\":\"unsupported\",",
      "\"callback\":\"writeState.flags\",\"seq\":1,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",",
      "\"reason\":\"missing action\"}\n"
    ].joined()
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data(unsupportedCallback.utf8))
    }
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: "v9.9.9", commit: "0", jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("graph event stream requires stable identity, order, closure, counts, and body bytes")
  func validatesStreamIntegrity() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let complete = try completeGraphStream(finiteGraphCase)
    let runID = "00000000-0000-4000-8000-000000000001"

    let changedRun = try mutatedCompleteGraphStream(finiteGraphCase) { line in
      guard line.contains("\"seq\":1") else { return line }
      return line.replacingOccurrences(
        of: runID, with: "00000000-0000-4000-8000-000000000002")
    }
    #expect(throws: TLCGraphEventError.invalidRecord(line: 2, reason: "run ID changed")) {
      try reader.parse(changedRun)
    }

    let changedCase = Data(
      String(decoding: complete, as: UTF8.self)
        .replacingOccurrences(of: "\"caseId\":\"fixture\"", with: "\"caseId\":\"other\"")
        .utf8)
    #expect(throws: TLCGraphEventError.invalidRecord(line: 1, reason: "case ID")) {
      try reader.parse(changedCase)
    }

    let sequenceGap = try mutatedCompleteGraphStream(finiteGraphCase) {
      $0.replacingOccurrences(of: "\"seq\":1", with: "\"seq\":9")
    }
    #expect(throws: TLCGraphEventError.invalidRecord(line: 2, reason: "sequence gap")) {
      try reader.parse(sequenceGap)
    }

    let openFooter = Data(
      String(decoding: complete, as: UTF8.self)
        .replacingOccurrences(of: "\"status\":\"closed\"", with: "\"status\":\"open\"")
        .utf8)
    #expect(throws: TLCGraphEventError.invalidFooter("not closed")) {
      try reader.parse(openFooter)
    }

    let wrongCounts = Data(
      String(decoding: complete, as: UTF8.self)
        .replacingOccurrences(of: "\"initial\":1", with: "\"initial\":2")
        .utf8)
    #expect(throws: TLCGraphEventError.invalidFooter("count for initial")) {
      try reader.parse(wrongCounts)
    }

    var changedBody = complete
    changedBody.insert(0x20, at: 1)
    #expect(throws: TLCGraphEventError.invalidFooter("body digest")) {
      try reader.parse(changedBody)
    }
  }

  @Test("graph event reader accepts only TLC's exact actionless stuttering observation")
  func acceptsExactStutteringObservation() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let stream = try completeGraphStreamWithStutteringObservation(finiteGraphCase)
    #expect(try reader.parse(stream).transitions.count == 1)
    let rejected = Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "STUTTERING", with: "ARBITRARY").utf8)
    #expect(throws: TLCGraphEventError.unsupportedCallback("writeState.visualization")) {
      try reader.parse(rejected)
    }
  }

  @Test("graph event reader retains only exact excluded predicate observations")
  func acceptsExcludedPredicateObservationsWithoutAddingGraphEdges() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let stream = try completeGraphStreamWithExcludedPredicateObservation(finiteGraphCase)
    #expect(try reader.parse(stream).transitions.count == 1)
    let wrongFlags = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "\"raw\":2", with: "\"raw\":3").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try reader.parse(wrongFlags)
    }
    let wrongSourceIdentity = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Next(", with: "<Other(").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try reader.parse(wrongSourceIdentity)
    }
  }

  @Test("declared invocation resolves to its compiled rendered action")
  func resolvesOnlyDeclaredBridgeConversions() throws {
    let call = RenderedAction(
      sourceName: "Step", arguments: [.int(0)], renderedName: "Step__0")
    let expected = try fixtureCase(try toolchainPin(), renderedActions: [call])
    let reader = TLCGraphReader(finiteGraphCase: expected)
    let stream = try functionRecordNormalizationStream(expected, actionLocation: "<Step(0) line 1, col 1 to line 1, col 2 of module Fixture>")
    let run = try reader.readCompletedGraph(
      stream,
      result: TLCProcessResult(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    #expect(run.observableActions == ["Step__0"])
    #expect(run.graph.initialStateKeys.first?.canonicalEncoding.contains("63617273=record") == true)
    let undeclared = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Step(0)", with: "<Step(1)").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 3, reason: "undeclared invocation identity")) {
      try reader.parse(undeclared)
    }
  }

  @Test("an unchanged action name does not require invocation decoding")
  func retainsUnchangedActionNames() throws {
    let action = RenderedAction(sourceName: "Next", arguments: [], renderedName: "Next")
    let finiteGraphCase = try fixtureCase(try toolchainPin(), renderedActions: [action])
    let stream = try refreshedFooterDigest(Data(String(
      decoding: completeGraphStream(finiteGraphCase), as: UTF8.self
    ).replacingOccurrences(
      of: "\"location\":\"\"",
      with: "\"location\":\"<Next line 1, col 1 to line 1, col 2 of module Fixture>\""
    ).utf8))

    let parsed = try TLCGraphReader(finiteGraphCase: finiteGraphCase).parse(stream)

    #expect(parsed.transitions.map(\.action) == ["Next"])
  }

  @Test("reduced TLC fingerprint aliases must belong to the declared symmetry orbit")
  func acceptsOnlyDeclaredSymmetryAliases() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let parsed = try reader.parse(try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: true))
    #expect(parsed.transitions.count == 2)
    #expect(parsed.transitions[0].target == parsed.transitions[1].target)
    #expect(parsed.fingerprintRepresentatives["2"] == parsed.transitions[0].target)
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "fingerprint binding mismatch")) {
      try reader.parse(try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: false, aliasValue: "B"))
    }
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "fingerprint binding mismatch")) {
      try reader.parse(try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: true, aliasValue: "B"))
    }
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "seen fingerprint without representative")) {
      try reader.parse(try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: true, aliasFingerprint: "foreign"))
    }

    let reducedCase = try fixtureCase(
      try toolchainPin(),
      symmetryReduction: .enabled(maximumPermutationCount: 2),
      symmetryGenerators: [try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])]
    )
    let reduced = try TLCGraphReader(finiteGraphCase: reducedCase).parse(
      try fingerprintAliasGraphStream(reducedCase, aliasSeen: true, aliasValue: "B")
    )
    #expect(reduced.transitions.count == 2)
    #expect(reduced.transitions[0].target == reduced.transitions[1].target)
    #expect(throws: TLCGraphEventError.invalidRecord(
      line: 4, reason: "fingerprint binding outside declared symmetry orbit")) {
      try TLCGraphReader(finiteGraphCase: reducedCase).parse(try fingerprintAliasGraphStream(
        reducedCase, aliasSeen: true, aliasValue: "B", aliasStableValue: "1"))
    }
    #expect(throws: TLCGraphEventError.invalidRecord(
      line: 4, reason: "fingerprint binding outside declared symmetry orbit")) {
      try TLCGraphReader(finiteGraphCase: reducedCase).parse(try fingerprintAliasGraphStream(
        reducedCase, aliasSeen: true, aliasValue: "C"))
    }
    #expect(throws: SymmetryOrbitAdapterError.emptyPermutationGroup) {
      try fixtureCase(
        try toolchainPin(),
        symmetryReduction: .enabled(maximumPermutationCount: 2))
    }
  }

  @Test("process adapter adds trace capture only after a violation")
  func onlyRequestsTraceAfterViolation() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    try completeGraphStream(request.finiteGraphCase).write(to: request.graphEvents, options: .atomic)
    let executor = RecordingTLCExecutor(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: "")
    ])
    let adapter = TLCProcessAdapter(executor: executor)
    let capture = try adapter.capture(
      request,
      retainingIn: directory.appendingPathComponent("evidence")
    )
    #expect(capture.run.primary.isViolation)
    #expect(executor.requests.count == 2)
    #expect(executor.requests[0].traceMode == .none)
    #expect(executor.requests[1].traceMode == .dumpJSON)
    #expect(executor.requests[0].graphEvents == request.graphEvents)
    #expect(executor.requests[1].graphEvents.lastPathComponent == "events.trace.jsonl")
    #expect(capture.run.trace == .init(status: 12, stdout: "Error: Invariant broken", stderr: ""))
  }

  @Test("graph event reader rejects booleans for integers and numbers for booleans")
  func rejectsWrongJSONPrimitiveTypes() throws {
    let finiteGraphCase = try fixtureCase(try toolchainPin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let mutations = [
      { (line: String) in line.replacingOccurrences(of: "\"version\":2", with: "\"version\":true")
      },
      { (line: String) in line.replacingOccurrences(of: "\"seen\":false", with: "\"seen\":0") },
      { (line: String) in
        line.replacingOccurrences(of: "\"notInModel\":false", with: "\"notInModel\":1")
      },
      { (line: String) in
        line.replacingOccurrences(of: "\"lastBodySeq\":2", with: "\"lastBodySeq\":false")
      }
    ]
    for mutation in mutations {
      #expect(throws: TLCGraphEventError.self) {
        try reader.parse(try mutatedCompleteGraphStream(finiteGraphCase, mutation: mutation))
      }
    }
  }

  @Test("launch validates the staged module and configuration against the declared case")
  func rejectsLaunchBindingMismatches() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let module = directory.appendingPathComponent("Module.tla")
    let configuration = directory.appendingPathComponent("Module.cfg")
    try "module bytes".write(to: module, atomically: true, encoding: .utf8)
    try "cfg bytes".write(to: configuration, atomically: true, encoding: .utf8)
    let finiteGraphCase = try caseForFiles(
      id: "bound", module: module, configuration: configuration, arguments: ["-workers", "1"])
    let valid = try launchRequest(
      finiteGraphCase: finiteGraphCase, module: module, configuration: configuration)
    let staged = try valid.stageDeclaredBundle()
    try valid.validateLaunchBinding(module: staged.module, configuration: staged.configuration)
    let wrongModule = TLAModuleBundle.external(
      root: TLAModuleFile(name: "Module", tla: "wrong module", cfg: "cfg bytes")
    )
    let wrongModuleRequest = TLCProcessRequest(
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeClasses: valid.bridgeClasses,
      bundle: wrongModule, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      workingDirectory: directory.appendingPathComponent("wrong-module"),
      finiteGraphCase: finiteGraphCase, runID: UUID()
    )
    #expect(throws: FiniteGraphCaseError.moduleDigestMismatch) {
      let wrongStaged = try wrongModuleRequest.stageDeclaredBundle()
      try wrongModuleRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
    let wrongConfiguration = TLAModuleBundle.external(
      root: TLAModuleFile(name: "Module", tla: "module bytes", cfg: "wrong cfg")
    )
    let wrongConfigurationRequest = TLCProcessRequest(
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeClasses: valid.bridgeClasses,
      bundle: wrongConfiguration, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      workingDirectory: directory.appendingPathComponent("wrong-configuration"),
      finiteGraphCase: finiteGraphCase, runID: UUID()
    )
    #expect(throws: FiniteGraphCaseError.cfgDigestMismatch) {
      let wrongStaged = try wrongConfigurationRequest.stageDeclaredBundle()
      try wrongConfigurationRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
  }
}

private func toolchainPin() throws -> TLCReferencePin {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let data = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
  let lock = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  let tlc = try #require(lock["tlc"] as? [String: Any])
  let jar = try #require(tlc["jar"] as? [String: Any])
  let java = try #require(lock["java"] as? [String: Any])
  let archives = try #require(java["archives"] as? [String: Any])
  let arm64 = try #require(archives["arm64"] as? [String: Any])
  let bridge = try #require(lock["bridge"] as? [String: Any])
  return try TLCReferencePin(
    tag: try #require(tlc["tag"] as? String),
    commit: try #require(tlc["commit"] as? String),
    jarSHA256: try #require(jar["sha256"] as? String),
    javaDistribution: try #require(java["distribution"] as? String),
    javaVersion: try #require(java["version"] as? String),
    javaArchiveSHA256: try #require(arm64["sha256"] as? String),
    bridgeClass: try #require(bridge["class"] as? String),
    bridgeSourceSHA256: try #require(bridge["sourceSha256"] as? String),
    bridgeBinarySHA256: try #require(bridge["binarySha256"] as? String))
}

private func retainedCaptureRequest(in directory: URL) throws -> TLCProcessRequest {
  return TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
    bundle: fixtureBundle(),
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("counterexample.json"),
    workingDirectory: directory.appendingPathComponent("work"),
    finiteGraphCase: try fixtureCase(try toolchainPin(), arguments: ["-workers", "1", "-fp", "1"]),
    runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
  )
}

private func fixtureBundle() -> TLAModuleBundle {
  .external(root: TLAModuleFile(name: "Fixture", tla: "---- MODULE Fixture ----", cfg: "SPECIFICATION Spec"))
}
