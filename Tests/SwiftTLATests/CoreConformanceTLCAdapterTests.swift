import Darwin
import Foundation
import Testing
import UpstreamParity
@Suite(.serialized)
struct CoreConformanceTLCAdapterTests { @Test("frozen graph stream becomes complete canonical evidence")
  func parsesFrozenGraphIntoCanonicalRun() throws {
    let expectedCase = fixtureCase(.fixture)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let result = TLCProcessResultV1(
      status: 0,
      stdout: "Model checking completed. No error has been found.",
      stderr: ""
    )
    let run = try parser.parseCanonicalRun(completeGraphStream(expectedCase), result: result)
    #expect(run.isPassEligible)
    #expect(run.graph.initialStateKeys.count == 1)
    #expect(run.graph.edgeOccurrences.values.sorted() == [1])
    #expect(run.observableActions == ["Next"])
  }

  @Test("TLC violations remain non-passing canonical outcomes")
  func preservesViolationOutcome() throws {
    let expectedCase = fixtureCase(.fixture)
    let run = try TLCGraphEventParserV1(expectedCase: expectedCase).parseCanonicalRun(
      completeGraphStream(expectedCase),
      result: TLCProcessResultV1(
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
    let expectedCase = fixtureCase(.fixture)
    let run = try TLCGraphEventParserV1(expectedCase: expectedCase).parseCanonicalRun(
      completeGraphStream(expectedCase),
      result: TLCProcessResultV1(
        status: 12,
        stdout: "Parsing file /tmp/die-hard-violation/DieHard.tla\nError: Invariant NotSolved is violated.",
        stderr: ""
      )
    )
    #expect(run.outcome == .invariantViolation("Error: Invariant NotSolved is violated."))
  }

  @Test("retained frozen bridge stream parses every admitted value form")
  func parsesRetainedFrozenBridgeStream() throws {
    let expectedCase = retainedBridgeCase()
    let testFile = URL(fileURLWithPath: #filePath)
    let streamURL =
      testFile
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/CoreConformance/spike/run-1/events.jsonl")
    let run = try TLCGraphEventParserV1(expectedCase: expectedCase).parseCanonicalRun(
      Data(contentsOf: streamURL),
      result: TLCProcessResultV1(
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
      "Verification/CoreConformance/fixtures/hour-clock-edge-mismatch/evidence",
      "Verification/CoreConformance/fixtures/die-hard-violation/evidence",
      "Verification/CoreConformance/baselines/multicar-elevator",
      "Verification/CoreConformance/baselines/multicar-elevator-edge-mismatch"
    ]
    for path in directories {
      let directory = root.appendingPathComponent(path)
      let expected = try frozenCase(directory.appendingPathComponent("case.json"))
      let streamNames = ["graph-events.jsonl"]
      for name in streamNames where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
        _ = try TLCGraphEventParserV1(expectedCase: expected).parseCanonicalRun(
          Data(contentsOf: directory.appendingPathComponent(name)),
          result: TLCProcessResultV1(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
      }
    }
  }

  @Test("well-formed but unlocked digests fail pin validation")
  func rejectsWrongPinnedDigests() throws {
    let pin = TLCReferencePinV1.fixture
    #expect(throws: CoreConformanceCaseErrorV1.self) {
      _ = try TLCReferencePinV1(
        tag: pin.tag, commit: pin.commit, jarSHA256: String(repeating: "0", count: 64),
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: CoreConformanceCaseErrorV1.self) {
      _ = try TLCReferencePinV1(
        tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: String(repeating: "a", count: 64),
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: CoreConformanceCaseErrorV1.self) {
      _ = try TLCReferencePinV1(
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
    let artifacts = TLCReferenceArtifactsV1(
      jar: toolRoot.appendingPathComponent("downloads/tla2tools.jar"),
      javaArchive: toolRoot.appendingPathComponent("downloads/temurin-arm64.tar.gz"),
      bridgeSource: root.appendingPathComponent(
        "Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java"),
      bridgeBinary: toolRoot.appendingPathComponent(
        "bridge-classes/org/swifttla/conformance/LosslessStateWriter.class"),
      jarManifest:
        "Implementation-Title: TLA+ Tools\\nX-Git-Revision: 0894c3407f4717fec7cc18bde3bf3c857fa47333\\n",
      runtime: TLCJavaRuntimeIdentityV1(
        version: "17.0.19+10", vendor: "Eclipse Adoptium", architecture: "arm64",
        properties: ["java.runtime.version": "17.0.19+10", "java.vendor": "Eclipse Adoptium"]
      )
    )
    try TLCReferencePinV1.fixture.validate(artifacts)
    let emptyManifest = TLCReferenceArtifactsV1(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: "", runtime: artifacts.runtime
    )
    #expect(throws: CoreConformanceCaseErrorV1.pinMismatch("TLC JAR manifest")) {
      try TLCReferencePinV1.fixture.validate(emptyManifest)
    }
    let mismatchedRuntime = TLCReferenceArtifactsV1(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSource: artifacts.bridgeSource,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: artifacts.jarManifest,
      runtime: TLCJavaRuntimeIdentityV1(
        version: "17.0.19+11", vendor: artifacts.runtime.vendor,
        architecture: artifacts.runtime.architecture,
        properties: [
          "java.runtime.version": "17.0.19+11",
          "java.vendor": artifacts.runtime.vendor
        ]
      )
    )
    #expect(throws: CoreConformanceCaseErrorV1.pinMismatch("Java runtime")) {
      try TLCReferencePinV1.fixture.validate(mismatchedRuntime)
    }
  }

  @Test("TLC command loads bridge and passes every frozen property")
  func assemblesFrozenBridgeCommand() throws {
    let request = TLCProcessRequestV1(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
      bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
      module: URL(fileURLWithPath: "/tmp/Fixture.tla"),
      configuration: URL(fileURLWithPath: "/tmp/Fixture.cfg"),
      graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
      traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
      replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      arguments: ["-workers", "1"],
      expectedCase: fixtureCase(.fixture, arguments: ["-workers", "1"]),
      runID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
    )
    let command = try request.commandArguments(traceMode: .dumpJSON)
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
    let artifacts = TLCReferenceArtifactsV1(
      jar: URL(fileURLWithPath: "/tmp/validated-tla2tools.jar"),
      javaArchive: URL(fileURLWithPath: "/tmp/temurin.tar.gz"),
      bridgeSource: URL(fileURLWithPath: "/tmp/LosslessStateWriter.java"),
      bridgeBinary: root.appendingPathComponent(
        "org/swifttla/conformance/LosslessStateWriter.class"),
      jarManifest: "",
      runtime: TLCJavaRuntimeIdentityV1(version: "", vendor: "", architecture: "", properties: [:])
    )
    let substitutedJar = requestWithReferenceArtifacts(
      jar: URL(fileURLWithPath: "/tmp/substituted-tla2tools.jar"), bridgeClasses: root,
      artifacts: artifacts
    )
    #expect(throws: CoreConformanceCaseErrorV1.pinMismatch("execution TLC JAR")) {
      try substitutedJar.validateReferenceBinding(pin: .fixture, artifacts: artifacts)
    }
    let substitutedBridge = requestWithReferenceArtifacts(
      jar: artifacts.jar, bridgeClasses: URL(fileURLWithPath: "/tmp/substituted-bridge"),
      artifacts: artifacts
    )
    #expect(throws: CoreConformanceCaseErrorV1.pinMismatch("execution bridge class")) {
      try substitutedBridge.validateReferenceBinding(pin: .fixture, artifacts: artifacts)
    }
  }

  @Test("required replay fails when its TLC execution does not succeed")
  func requiredReplayFailureIsExplicit() throws {
    let executor = RecordingTLCExecutorV1(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 1, stdout: "", stderr: "cannot replay")
    ])
    #expect(throws: TLCProcessErrorV1.self) {
      _ = try TLCProcessAdapterV1(executor: executor).run(.fixture, replay: .required)
    }
  }

  @Test("retained TLC v1.8.0 counterexample remains trace-only evidence")
  func parsesRetainedCounterexample() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let traceURL =
      testFile
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Verification/CoreConformance/spike/violation/counterexample.json")
    let evidence = try TLCTraceParserV1().parseCounterexample(Data(contentsOf: traceURL))
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
    let request = TLCProcessRequestV1(
      javaExecutable: executable, jar: URL(fileURLWithPath: "/tmp/jar"), bridgeClasses: directory,
      module: module, configuration: configuration,
      graphEvents: directory.appendingPathComponent("events.jsonl"),
      traceOutput: directory.appendingPathComponent("trace.json"),
      replayInput: directory.appendingPathComponent("replay.json"), workingDirectory: directory,
      arguments: [],
      expectedCase: caseForFiles(
        id: "timeout", module: module, configuration: configuration, arguments: []),
      runID: UUID(), timeout: 0.25
    )
    let started = Date()
    #expect(throws: TLCProcessErrorV1.self) {
      _ = try SystemTLCProcessExecutorV1(validatesReferences: false).execute(request)
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
    #expect(throws: CoreConformanceCaseErrorV1.pinMismatch("TLC banner")) {
      _ = try SystemTLCProcessExecutorV1(validatesReferences: false).execute(request)
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
    let result = try SystemTLCProcessExecutorV1(validatesReferences: false).execute(request)
    #expect(result.stdout.contains("home=unset allowed=declared"))
  }

  @Test("graph event parser rejects malformed footer and unsupported callbacks")
  func rejectsMalformedStreams() throws {
    let pin = TLCReferencePinV1.fixture
    let expectedCase = fixtureCase(pin)
    let stream = TLCGraphEventParserV1(expectedCase: expectedCase)
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(Data("{\"not\":\"jsonl footer\"}\n".utf8))
    }
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(Data("{\"schema\":\"x\",\"schema\":\"x\"}\n".utf8))
    }
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(Data("{\"schema\":\"x\",\"sche\\u006da\":\"x\"}\n".utf8))
    }
    let invalidInitial = [
      "\(header(expectedCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"initial\",",
      "\"callback\":\"writeState.initial\",\"seq\":2,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"state\":{}}\n"
    ].joined()
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(Data(invalidInitial.utf8))
    }
    let unsupportedCallback = [
      "\(header(expectedCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"unsupported\",",
      "\"callback\":\"writeState.flags\",\"seq\":1,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",",
      "\"reason\":\"missing action\"}\n"
    ].joined()
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(Data(unsupportedCallback.utf8))
    }
    #expect(throws: CoreConformanceCaseErrorV1.self) {
      _ = try TLCReferencePinV1(
        tag: "v9.9.9", commit: "0", jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("graph event parser accepts only TLC's exact actionless stuttering observation")
  func acceptsExactStutteringObservation() throws {
    let expectedCase = fixtureCase(.fixture)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let stream = completeGraphStreamWithStutteringObservation(expectedCase)
    #expect(try parser.parse(stream).transitions.count == 1)
    let rejected = Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "STUTTERING", with: "ARBITRARY").utf8)
    #expect(throws: TLCGraphEventErrorV1.unsupportedCallback("writeState.visualization")) {
      try parser.parse(rejected)
    }
  }

  @Test("graph event parser retains only exact excluded predicate observations")
  func acceptsExcludedPredicateObservationsWithoutAddingGraphEdges() throws {
    let expectedCase = fixtureCase(.fixture)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let stream = completeGraphStreamWithExcludedPredicateObservation(expectedCase)
    #expect(try parser.parse(stream).transitions.count == 1)
    let wrongFlags = refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "\"raw\":2", with: "\"raw\":3").utf8))
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try parser.parse(wrongFlags)
    }
    let wrongSourceIdentity = refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Next(", with: "<Other(").utf8))
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 4, reason: "invalid excluded predicate transition")) {
      try parser.parse(wrongSourceIdentity)
    }
  }

  @Test("declared invocation and function-record normalization are the only bridge conversions")
  func resolvesOnlyDeclaredBridgeConversions() throws {
    let mapping = try CoreConformanceInvocationMappingV1(
      wrapper: "Step__0", action: "Step", arguments: ["0"], indices: [0])
    let normalization = try CoreConformanceValueNormalizationV1(
      binding: "cars", functionKeys: ["\"carA\"": "carA", "\"carB\"": "carB"])
    let expected = fixtureCase(.fixture, invocationMappings: [mapping], valueNormalizations: [normalization])
    let parser = TLCGraphEventParserV1(expectedCase: expected)
    let stream = functionRecordNormalizationStream(expected, actionLocation: "<Step(0) line 1, col 1 to line 1, col 2 of module Fixture>")
    let run = try parser.parseCanonicalRun(
      stream,
      result: TLCProcessResultV1(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    #expect(run.observableActions == ["Step__0"])
    #expect(run.graph.initialStateKeys.first?.canonicalEncoding.contains("63617273=record") == true)
    let undeclared = refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Step(0)", with: "<Step(1)").utf8))
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 3, reason: "undeclared invocation identity")) {
      try parser.parse(undeclared)
    }
    let unknownKey = replacingFunctionKey(in: stream, from: "carB", to: "carC")
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 0, reason: "normalized function keys")) {
      try parser.parseCanonicalRun(
        unknownKey,
        result: TLCProcessResultV1(status: 0, stdout: "Model checking completed. No error has been found.", stderr: ""))
    }
  }

  @Test("graph event parser resolves a reduced TLC alias only through its retained fingerprint representative")
  func resolvesFingerprintAliasesFromSameStream() throws {
    let expectedCase = fixtureCase(.fixture)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let parsed = try parser.parse(fingerprintAliasGraphStream(expectedCase, aliasSeen: true))
    #expect(parsed.transitions.count == 2)
    #expect(parsed.transitions[0].target == parsed.transitions[1].target)
    #expect(parsed.fingerprintRepresentatives["2"] == parsed.transitions[0].target)
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 4, reason: "ambiguous fingerprint representative")) {
      try parser.parse(fingerprintAliasGraphStream(expectedCase, aliasSeen: false))
    }
    #expect(throws: TLCGraphEventErrorV1.invalidRecord(line: 4, reason: "seen fingerprint without representative")) {
      try parser.parse(fingerprintAliasGraphStream(expectedCase, aliasSeen: true, aliasFingerprint: "foreign"))
    }
  }

  @Test("process adapter adds trace and replay only after a violation")
  func onlyRequestsTraceAfterViolation() throws {
    let executor = RecordingTLCExecutorV1(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: "")
    ])
    let adapter = TLCProcessAdapterV1(executor: executor)
    let request = TLCProcessRequestV1.fixture
    let result = try adapter.run(request, replay: .required)
    #expect(result.primary.isViolation)
    #expect(executor.requests.count == 3)
    #expect(executor.requests[0].traceMode == .none)
    #expect(executor.requests[1].traceMode == .dumpJSON)
    #expect(executor.requests[2].traceMode == .loadJSON)
    #expect(executor.requests[0].graphEvents.path == "/tmp/events.jsonl")
    #expect(executor.requests[1].graphEvents.path == "/tmp/events.trace.jsonl")
    #expect(executor.requests[2].graphEvents.path == "/tmp/events.replay.jsonl")
    #expect(result.replay == .init(status: 12, stdout: "Error: Invariant broken", stderr: ""))
  }

  @Test("graph event parser rejects booleans for integers and numbers for booleans")
  func rejectsWrongJSONPrimitiveTypes() throws {
    let expectedCase = fixtureCase(.fixture)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
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
      #expect(throws: TLCGraphEventErrorV1.self) {
        try parser.parse(mutatedCompleteGraphStream(expectedCase, mutation: mutation))
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
    let expectedCase = caseForFiles(
      id: "bound", module: module, configuration: configuration, arguments: ["-workers", "1"])
    let valid = launchRequest(
      expectedCase: expectedCase, module: module, configuration: configuration,
      arguments: ["-workers", "1"])
    try valid.validateLaunchBinding()
    let command = try valid.commandArguments()
    #expect(
      command.contains(where: {
        $0.contains(expectedCase.moduleSHA256) && $0.contains(expectedCase.argumentsSHA256)
      }))
    try "wrong module".write(to: module, atomically: true, encoding: .utf8)
    #expect(throws: CoreConformanceCaseErrorV1.moduleDigestMismatch) {
      try valid.validateLaunchBinding()
    }
    try "module bytes".write(to: module, atomically: true, encoding: .utf8)
    try "wrong cfg".write(to: configuration, atomically: true, encoding: .utf8)
    #expect(throws: CoreConformanceCaseErrorV1.cfgDigestMismatch) {
      try valid.validateLaunchBinding()
    }
    try "cfg bytes".write(to: configuration, atomically: true, encoding: .utf8)
    let wrongArguments = launchRequest(
      expectedCase: expectedCase, module: module, configuration: configuration,
      arguments: ["-workers", "2"])
    #expect(throws: CoreConformanceCaseErrorV1.executionArgumentsMismatch) {
      try wrongArguments.validateLaunchBinding()
    }
  }
}
