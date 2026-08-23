import Darwin
import Foundation
import Testing
import SwiftTLA
import UpstreamParity
@Suite(.serialized)
struct CoreConformanceTLCAdapterTests { @Test("frozen graph stream becomes complete canonical evidence")
  func parsesFrozenGraphIntoCanonicalRun() throws {
    let expectedCase = try fixtureCase(.fixture)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let result = TLCProcessResult(
      status: 0,
      stdout: "Model checking completed. No error has been found.",
      stderr: ""
    )
    let run = try parser.parseCanonicalRun(try completeGraphStream(expectedCase), result: result)
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
      replayInput: directory.appendingPathComponent("replay.json"),
      workingDirectory: directory.appendingPathComponent("work"),
      arguments: [],
      expectedCase: try fixtureCase(.fixture),
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
    let data = try Data(contentsOf: root.appendingPathComponent("Verification/CoreConformance/toolchain.json"))
    let lock = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tlc = try #require(lock["tlc"] as? [String: Any])
    let names = try #require(tlc["standardModules"] as? [String])

    #expect(Set(names) == TLCReferencePin.standardModuleNames)
  }

  @Test("TLC violations remain non-passing canonical outcomes")
  func preservesViolationOutcome() throws {
    let expectedCase = try fixtureCase(.fixture)
    let run = try TLCGraphEventParser(expectedCase: expectedCase).parseCanonicalRun(
      try completeGraphStream(expectedCase),
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
    let expectedCase = try fixtureCase(.fixture)
    let run = try TLCGraphEventParser(expectedCase: expectedCase).parseCanonicalRun(
      try completeGraphStream(expectedCase),
      result: TLCProcessResult(
        status: 12,
        stdout: "Parsing file /tmp/invariant-violation/DieHard.tla\nError: Invariant NotSolved is violated.",
        stderr: ""
      )
    )
    #expect(run.outcome == .invariantViolation("Error: Invariant NotSolved is violated."))
  }

  @Test("retained frozen bridge stream parses every admitted value form")
  func parsesRetainedFrozenBridgeStream() throws {
    let expectedCase = try retainedBridgeCase()
    let testFile = URL(fileURLWithPath: #filePath)
    let streamURL =
      testFile
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/CoreConformance/spike/run-1/events.jsonl")
    let run = try TLCGraphEventParser(expectedCase: expectedCase).parseCanonicalRun(
      Data(contentsOf: streamURL),
      result: TLCProcessResult(
        status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    )
    #expect(run.isPassEligible)
    #expect(run.graph.states.count == 6)
    #expect(run.graph.edgeOccurrences.values.reduce(0, +) == 9)
  }

  @Test("active frozen CoreConformance streams bind to their regenerated bridge pin")
  func parsesActiveFrozenCoreStreamsAgainstTheirMetadata() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directories = [
      "Verification/CoreConformance/baselines/hour-clock",
      "Verification/CoreConformance/baselines/die-hard-type-ok",
      "Verification/CoreConformance/baselines/multicar-elevator"
    ]
    for path in directories {
      let directory = root.appendingPathComponent(path)
      let expected = try frozenCase(directory.appendingPathComponent("case.json"))
      let streamNames = ["graph-events.jsonl"]
      for name in streamNames where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
        _ = try TLCGraphEventParser(expectedCase: expected).parseCanonicalRun(
          Data(contentsOf: directory.appendingPathComponent(name)),
          result: TLCProcessResult(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
      }
    }
  }

  @Test("well-formed but unlocked digests fail pin validation")
  func rejectsWrongPinnedDigests() throws {
    let pin = TLCReferencePin.fixture
    #expect(throws: CoreConformanceCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: String(repeating: "0", count: 64),
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: CoreConformanceCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: String(repeating: "a", count: 64),
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: CoreConformanceCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256,
        bridgeBinarySHA256: String(repeating: "b", count: 64)
      )
    }
  }

  @Test("the locked reference pin validates the compiled bridge artifact")
  func validatesCompiledBridgeArtifact() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard let toolRoot = ProcessInfo.processInfo.environment["CORE_CONFORMANCE_TOOL_ROOT"].map(URL.init(fileURLWithPath:)) else {
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
        "Implementation-Title: TLA+ Tools\\nX-Git-Revision: 0894c3407f4717fec7cc18bde3bf3c857fa47333\\n",
      runtime: TLCJavaRuntimeIdentity(
        version: "17.0.19+10", vendor: "Eclipse Adoptium", architecture: "arm64",
        properties: ["java.runtime.version": "17.0.19+10", "java.vendor": "Eclipse Adoptium"]
      )
    )
    try TLCReferencePin.fixture.validate(artifacts)
    let emptyManifest = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: "", runtime: artifacts.runtime
    )
    #expect(throws: CoreConformanceCaseError.pinMismatch("TLC JAR manifest")) {
      try TLCReferencePin.fixture.validate(emptyManifest)
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
    #expect(throws: CoreConformanceCaseError.pinMismatch("Java runtime")) {
      try TLCReferencePin.fixture.validate(mismatchedRuntime)
    }
  }

  @Test("TLC command loads bridge and passes every frozen property")
  func assemblesFrozenBridgeCommand() throws {
    let request = TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
      bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
      bundle: try TLCProcessRequest.fixture().bundle,
      graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
      traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
      replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      arguments: ["-workers", "1"],
      expectedCase: try fixtureCase(.fixture, arguments: ["-workers", "1"]),
      runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
    )
    let command = try request.commandArguments(
      module: URL(fileURLWithPath: "/tmp/Fixture.tla"),
      configuration: URL(fileURLWithPath: "/tmp/Fixture.cfg"),
      traceMode: .dumpJSON
    )
    #expect(command.contains("-Dswifttla.tlc.graph.path=/tmp/events.jsonl"))
    #expect(
      command.contains(where: {
        $0.contains("-Dswifttla.tlc.graph.provenance=") && $0.contains("moduleSha256")
      }))
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
    #expect(throws: CoreConformanceCaseError.pinMismatch("execution TLC JAR")) {
      try substitutedJar.validateReferenceBinding(pin: .fixture, artifacts: artifacts)
    }
    let substitutedBridge = try requestWithReferenceArtifacts(
      jar: artifacts.jar, bridgeClasses: URL(fileURLWithPath: "/tmp/substituted-bridge"),
      artifacts: artifacts
    )
    #expect(throws: CoreConformanceCaseError.pinMismatch("execution bridge class")) {
      try substitutedBridge.validateReferenceBinding(pin: .fixture, artifacts: artifacts)
    }
  }

  @Test("required replay fails when its TLC execution does not succeed")
  func requiredReplayFailureIsExplicit() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    let executor = RecordingTLCExecutor(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 1, stdout: "", stderr: "cannot replay")
    ])
    #expect(throws: TLCProcessError.self) {
      _ = try TLCProcessAdapter(executor: executor).capture(
        request,
        replay: .required,
        retainingIn: directory.appendingPathComponent("evidence")
      )
    }
  }

  @Test("retained TLC v1.8.0 counterexample remains trace-only evidence")
  func parsesRetainedCounterexample() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let traceURL =
      testFile
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/CoreConformance/spike/violation/counterexample.json")
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

extension CoreConformanceTLCAdapterTests {
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
      replayInput: directory.appendingPathComponent("replay.json"), workingDirectory: directory,
      arguments: [],
      expectedCase: try caseForFiles(
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
    #expect(throws: CoreConformanceCaseError.pinMismatch("TLC banner")) {
      _ = try SystemTLCProcessExecutor(validatesReferences: false).execute(request)
    }
  }

  @Test("production TLC execution uses only the declared environment")
  func excludesHostEnvironmentAndPreservesAllowlist() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("environment.sh")
    try "#!/bin/sh\n"
      .appending("printf 'TLC2 Version 2026.08.11.125311 (rev: 0894c34)\\n'\n")
      .appending("printf 'home=%s allowed=%s\\n' \"${HOME-unset}\" \"${CORE_CONFORMANCE_ALLOWED_VALUE-unset}\"\n")
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let request = try helperProcessRequest(
      executable: executable,
      in: directory,
      environment: ["CORE_CONFORMANCE_ALLOWED_VALUE": "declared"]
    )
    let result = try SystemTLCProcessExecutor(validatesReferences: false).execute(request)
    #expect(result.stdout.contains("home=unset allowed=declared"))
  }

  @Test("graph event parser rejects malformed footer and unsupported callbacks")
  func rejectsMalformedStreams() throws {
    let pin = TLCReferencePin.fixture
    let expectedCase = try fixtureCase(pin)
    let stream = TLCGraphEventParser(expectedCase: expectedCase)
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
      "\(try header(expectedCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"initial\",",
      "\"callback\":\"writeState.initial\",\"seq\":2,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"state\":{}}\n"
    ].joined()
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data(invalidInitial.utf8))
    }
    let unsupportedCallback = [
      "\(try header(expectedCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"unsupported\",",
      "\"callback\":\"writeState.flags\",\"seq\":1,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",",
      "\"reason\":\"missing action\"}\n"
    ].joined()
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data(unsupportedCallback.utf8))
    }
    #expect(throws: CoreConformanceCaseError.self) {
      _ = try TLCReferencePin(
        tag: "v9.9.9", commit: "0", jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("graph event parser accepts only TLC's exact actionless stuttering observation")
  func acceptsExactStutteringObservation() throws {
    let expectedCase = try fixtureCase(.fixture)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let stream = try completeGraphStreamWithStutteringObservation(expectedCase)
    #expect(try parser.parse(stream).transitions.count == 1)
    let rejected = Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "STUTTERING", with: "ARBITRARY").utf8)
    #expect(throws: TLCGraphEventError.unsupportedCallback("writeState.visualization")) {
      try parser.parse(rejected)
    }
  }

  @Test("graph event parser retains only exact excluded predicate observations")
  func acceptsExcludedPredicateObservationsWithoutAddingGraphEdges() throws {
    let expectedCase = try fixtureCase(.fixture)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let stream = try completeGraphStreamWithExcludedPredicateObservation(expectedCase)
    #expect(try parser.parse(stream).transitions.count == 1)
    let wrongFlags = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "\"raw\":2", with: "\"raw\":3").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try parser.parse(wrongFlags)
    }
    let wrongSourceIdentity = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Next(", with: "<Other(").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try parser.parse(wrongSourceIdentity)
    }
  }

  @Test("declared invocation and function-record normalization are the only bridge conversions")
  func resolvesOnlyDeclaredBridgeConversions() throws {
    let mapping = try CoreConformanceInvocationMapping(
      wrapper: "Step__0", action: "Step", arguments: ["0"], indices: [0])
    let normalization = try CoreConformanceValueNormalization(
      binding: "cars", functionKeys: ["\"carA\"": "carA", "\"carB\"": "carB"])
    let expected = try fixtureCase(.fixture, invocationMappings: [mapping], valueNormalizations: [normalization])
    let parser = TLCGraphEventParser(expectedCase: expected)
    let stream = try functionRecordNormalizationStream(expected, actionLocation: "<Step(0) line 1, col 1 to line 1, col 2 of module Fixture>")
    let run = try parser.parseCanonicalRun(
      stream,
      result: TLCProcessResult(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    #expect(run.observableActions == ["Step__0"])
    #expect(run.graph.initialStateKeys.first?.canonicalEncoding.contains("63617273=record") == true)
    let undeclared = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Step(0)", with: "<Step(1)").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 3, reason: "undeclared invocation identity")) {
      try parser.parse(undeclared)
    }
    let unknownKey = try replacingFunctionKey(in: stream, from: "carB", to: "carC")
    #expect(throws: TLCGraphEventError.invalidRecord(line: 0, reason: "normalized function keys")) {
      try parser.parseCanonicalRun(
        unknownKey,
        result: TLCProcessResult(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    }
  }

  @Test("graph event parser resolves a reduced TLC alias only through its retained fingerprint representative")
  func resolvesFingerprintAliasesFromSameStream() throws {
    let expectedCase = try fixtureCase(.fixture)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let parsed = try parser.parse(try fingerprintAliasGraphStream(expectedCase, aliasSeen: true))
    #expect(parsed.transitions.count == 2)
    #expect(parsed.transitions[0].target == parsed.transitions[1].target)
    #expect(parsed.fingerprintRepresentatives["2"] == parsed.transitions[0].target)
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "ambiguous fingerprint representative")) {
      try parser.parse(try fingerprintAliasGraphStream(expectedCase, aliasSeen: false))
    }
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "seen fingerprint without representative")) {
      try parser.parse(try fingerprintAliasGraphStream(expectedCase, aliasSeen: true, aliasFingerprint: "foreign"))
    }
  }

  @Test("process adapter adds trace and replay only after a violation")
  func onlyRequestsTraceAfterViolation() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    try completeGraphStream(request.expectedCase).write(to: request.graphEvents, options: .atomic)
    let executor = RecordingTLCExecutor(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: "")
    ])
    let adapter = TLCProcessAdapter(executor: executor)
    let capture = try adapter.capture(
      request,
      replay: .required,
      retainingIn: directory.appendingPathComponent("evidence")
    )
    #expect(capture.run.primary.isViolation)
    #expect(executor.requests.count == 3)
    #expect(executor.requests[0].traceMode == .none)
    #expect(executor.requests[1].traceMode == .dumpJSON)
    #expect(executor.requests[2].traceMode == .loadJSON)
    #expect(executor.requests[0].graphEvents == request.graphEvents)
    #expect(executor.requests[1].graphEvents.lastPathComponent == "events.trace.jsonl")
    #expect(executor.requests[2].graphEvents.lastPathComponent == "events.replay.jsonl")
    #expect(capture.run.replay == .init(status: 12, stdout: "Error: Invariant broken", stderr: ""))
  }

  @Test("graph event parser rejects booleans for integers and numbers for booleans")
  func rejectsWrongJSONPrimitiveTypes() throws {
    let expectedCase = try fixtureCase(.fixture)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let mutations = [
      { (line: String) in line.replacingOccurrences(of: "\"version\":1", with: "\"version\":true")
      },
      { (line: String) in line.replacingOccurrences(of: "\"workers\":1", with: "\"workers\":true")
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
        try parser.parse(try mutatedCompleteGraphStream(expectedCase, mutation: mutation))
      }
    }
  }

  @Test("launch binding hashes the actual inputs and derives provenance from the declared case")
  func rejectsLaunchBindingMismatches() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let module = directory.appendingPathComponent("Module.tla")
    let configuration = directory.appendingPathComponent("Module.cfg")
    try "module bytes".write(to: module, atomically: true, encoding: .utf8)
    try "cfg bytes".write(to: configuration, atomically: true, encoding: .utf8)
    let expectedCase = try caseForFiles(
      id: "bound", module: module, configuration: configuration, arguments: ["-workers", "1"])
    let valid = try launchRequest(
      expectedCase: expectedCase, module: module, configuration: configuration,
      arguments: ["-workers", "1"])
    let staged = try valid.stageDeclaredBundle()
    try valid.validateLaunchBinding(module: staged.module, configuration: staged.configuration)
    let command = try valid.commandArguments(module: staged.module, configuration: staged.configuration)
    #expect(
      command.contains(where: {
        $0.contains(expectedCase.moduleSHA256) && $0.contains(expectedCase.argumentsSHA256)
      }))
    let wrongModule = TLAModuleBundle.external(
      root: TLAModuleFile(name: "Module", tla: "wrong module", cfg: "cfg bytes")
    )
    let wrongModuleRequest = TLCProcessRequest(
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeClasses: valid.bridgeClasses,
      bundle: wrongModule, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      replayInput: valid.replayInput, workingDirectory: directory.appendingPathComponent("wrong-module"),
      arguments: valid.arguments, expectedCase: expectedCase, runID: UUID()
    )
    #expect(throws: CoreConformanceCaseError.moduleDigestMismatch) {
      let wrongStaged = try wrongModuleRequest.stageDeclaredBundle()
      try wrongModuleRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
    let wrongConfiguration = TLAModuleBundle.external(
      root: TLAModuleFile(name: "Module", tla: "module bytes", cfg: "wrong cfg")
    )
    let wrongConfigurationRequest = TLCProcessRequest(
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeClasses: valid.bridgeClasses,
      bundle: wrongConfiguration, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      replayInput: valid.replayInput, workingDirectory: directory.appendingPathComponent("wrong-configuration"),
      arguments: valid.arguments, expectedCase: expectedCase, runID: UUID()
    )
    #expect(throws: CoreConformanceCaseError.cfgDigestMismatch) {
      let wrongStaged = try wrongConfigurationRequest.stageDeclaredBundle()
      try wrongConfigurationRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
    let wrongArguments = try launchRequest(
      expectedCase: expectedCase, module: module, configuration: configuration,
      arguments: ["-workers", "2"])
    #expect(throws: CoreConformanceCaseError.executionArgumentsMismatch) {
      let wrongStaged = try wrongArguments.stageDeclaredBundle()
      try wrongArguments.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
  }
}

private func retainedCaptureRequest(in directory: URL) throws -> TLCProcessRequest {
  let fixture = try TLCProcessRequest.fixture()
  return TLCProcessRequest(
    javaExecutable: fixture.javaExecutable,
    jar: fixture.jar,
    bridgeClasses: fixture.bridgeClasses,
    bundle: fixture.bundle,
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("counterexample.json"),
    replayInput: directory.appendingPathComponent("counterexample.json"),
    workingDirectory: directory.appendingPathComponent("work"),
    arguments: fixture.arguments,
    expectedCase: fixture.expectedCase,
    runID: fixture.runID
  )
}
