import Darwin
import Foundation
import Testing
import UpstreamParity

struct CoreConformanceTLCAdapterTests {
  @Test("frozen graph stream becomes complete canonical evidence")
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
    let artifacts = TLCReferenceArtifactsV1(
      jar: root.appendingPathComponent("Tools/TLCGraphBridge/.tool-cache/tla2tools-1.8.0.jar"),
      javaArchive: root.appendingPathComponent(
        "Tools/TLCGraphBridge/.tool-cache/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.19_10.tar.gz"),
      bridgeSource: root.appendingPathComponent(
        "Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java"),
      bridgeBinary: root.appendingPathComponent(
        "Tools/TLCGraphBridge/build/classes/org/swifttla/conformance/LosslessStateWriter.class"),
      jarManifest:
        "X-Git-Tag: v1.8.0\\nX-Git-Revision: 30cc3601321c3fc02e044d0ecb5c58d8921e18df\\n",
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
          "java.vendor": artifacts.runtime.vendor,
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
      .init(status: 1, stdout: "", stderr: "cannot replay"),
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
        .integer(0), .integer(1), .integer(2), .integer(3),
      ])
    #expect(evidence.canonicalTrace(id: "violation").steps.count == 3)
  }

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
    #expect(Date().timeIntervalSince(started) < 1.5)
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
    try "#!/bin/sh\nprintf 'TLC2 Version 2026.07.31.184830 (rev: 30cc360)\\n'\nprintf 'secret=%s allowed=%s\\n' \"${CORE_CONFORMANCE_TEST_SECRET-unset}\" \"${CORE_CONFORMANCE_ALLOWED_VALUE-unset}\"\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    setenv("CORE_CONFORMANCE_TEST_SECRET", "host-only", 1)
    defer { unsetenv("CORE_CONFORMANCE_TEST_SECRET") }

    let request = try helperProcessRequest(
      executable: executable,
      in: directory,
      environment: ["CORE_CONFORMANCE_ALLOWED_VALUE": "declared"]
    )
    let result = try SystemTLCProcessExecutorV1(validatesReferences: false).execute(request)

    #expect(result.stdout.contains("secret=unset allowed=declared"))
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
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(
        Data(
          "\(header(expectedCase))\n{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"initial\",\"callback\":\"writeState.initial\",\"seq\":2,\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"state\":{}}\n"
            .utf8))
    }
    #expect(throws: TLCGraphEventErrorV1.self) {
      try stream.parse(
        Data(
          "\(header(expectedCase))\n{\"schema\":\"swifttla.tlc.graph-events\",\"version\":1,\"type\":\"unsupported\",\"callback\":\"writeState.flags\",\"seq\":1,\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"reason\":\"missing action\"}\n"
            .utf8))
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

  @Test("process adapter adds trace and replay only after a violation")
  func onlyRequestsTraceAfterViolation() throws {
    let executor = RecordingTLCExecutorV1(results: [
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
      .init(status: 12, stdout: "Error: Invariant broken", stderr: ""),
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
      },
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

private func completeGraphStream(_ expectedCase: CoreConformanceCaseV1) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = ["fingerprint": "1", "level": 1, "bindings": [binding(0, "x", "0")]]
  let state1: [String: Any] = ["fingerprint": "2", "level": 2, "bindings": [binding(0, "x", "1")]]
  let headerData = Data(header(expectedCase).utf8)
  let initial: [String: Any] = record(
    "initial", 1, runID, expectedCase.id, ["callback": "writeState.initial", "state": state0])
  let transition: [String: Any] = record(
    "transition", 2, runID, expectedCase.id,
    [
      "callback": "writeState.action", "source": state0, "target": state1,
      "action": ["name": "Next", "location": "", "named": true],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable",
    ])
  let body = [headerData, jsonLine(initial), jsonLine(transition)].reduce(into: Data()) {
    $0.append($1)
    $0.append(10)
  }
  let footer: [String: Any] = record(
    "footer", 3, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 1],
      "lastBodySeq": 2, "bodySha256": SHA256V1.hex(body),
    ])
  return body + jsonLine(footer) + Data([10])
}

private func binding(_ ordinal: Int, _ name: String, _ tla: String) -> [String: Any] {
  ["ordinal": ordinal, "name": name, "tla": tla, "tlaSha256": SHA256V1.hex(Data(tla.utf8))]
}

private func record(
  _ type: String, _ sequence: Int, _ runID: String, _ caseID: String, _ fields: [String: Any]
) -> [String: Any] {
  fields.merging([
    "schema": "swifttla.tlc.graph-events", "version": 1, "type": type, "seq": sequence,
    "runId": runID, "caseId": caseID,
  ]) { _, new in new }
}

private func jsonLine(_ object: [String: Any]) -> Data {
  try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func fixtureCase(_ pin: TLCReferencePinV1, arguments: [String] = [])
  -> CoreConformanceCaseV1
{
  try! CoreConformanceCaseV1(
    id: "fixture", moduleSHA256: String(repeating: "c", count: 64),
    cfgSHA256: String(repeating: "d", count: 64),
    arguments: arguments, argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: [:], pin: pin
  )
}

private func mutatedCompleteGraphStream(
  _ expectedCase: CoreConformanceCaseV1, mutation: (String) -> String
) -> Data {
  var lines = String(decoding: completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  lines[0] = mutation(lines[0])
  lines[1] = mutation(lines[1])
  lines[2] = mutation(lines[2])
  let body = Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
  var footer =
    try! JSONSerialization.jsonObject(with: Data(mutation(lines[3]).utf8)) as! [String: Any]
  footer["bodySha256"] = SHA256V1.hex(body)
  return body + jsonLine(footer) + Data([10])
}

private func caseForFiles(
  id: String,
  module: URL,
  configuration: URL,
  arguments: [String],
  environment: [String: String] = [:]
)
  -> CoreConformanceCaseV1
{
  try! CoreConformanceCaseV1(
    id: id, moduleSHA256: SHA256V1.hex(try! Data(contentsOf: module)),
    cfgSHA256: SHA256V1.hex(try! Data(contentsOf: configuration)),
    arguments: arguments, argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: environment, pin: .fixture
  )
}

private func helperProcessDirectory() throws -> URL {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func helperProcessRequest(
  executable: URL,
  in directory: URL,
  environment: [String: String]
) throws -> TLCProcessRequestV1 {
  let module = directory.appendingPathComponent("Module.tla")
  let configuration = directory.appendingPathComponent("Module.cfg")
  try "---- MODULE Module ----\n====\n".write(to: module, atomically: true, encoding: .utf8)
  try "SPECIFICATION Spec\n".write(to: configuration, atomically: true, encoding: .utf8)
  return TLCProcessRequestV1(
    javaExecutable: executable,
    jar: URL(fileURLWithPath: "/tmp/jar"),
    bridgeClasses: directory,
    module: module,
    configuration: configuration,
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("trace.json"),
    replayInput: directory.appendingPathComponent("replay.json"),
    workingDirectory: directory,
    arguments: [],
    expectedCase: caseForFiles(
      id: "helper", module: module, configuration: configuration, arguments: [],
      environment: environment
    ),
    runID: UUID()
  )
}

private func launchRequest(
  expectedCase: CoreConformanceCaseV1, module: URL, configuration: URL, arguments: [String]
) -> TLCProcessRequestV1 {
  TLCProcessRequestV1(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"), module: module,
    configuration: configuration,
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
    workingDirectory: module.deletingLastPathComponent(),
    arguments: arguments, expectedCase: expectedCase, runID: UUID()
  )
}

private func requestWithReferenceArtifacts(
  jar: URL,
  bridgeClasses: URL,
  artifacts: TLCReferenceArtifactsV1
) -> TLCProcessRequestV1 {
  TLCProcessRequestV1(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: jar, bridgeClasses: bridgeClasses,
    module: URL(fileURLWithPath: "/tmp/Fixture.tla"),
    configuration: URL(fileURLWithPath: "/tmp/Fixture.cfg"),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
    workingDirectory: URL(fileURLWithPath: "/tmp"),
    arguments: ["-workers", "1", "-fp", "1"],
    expectedCase: fixtureCase(.fixture, arguments: ["-workers", "1", "-fp", "1"]),
    runID: UUID(), referencePin: .fixture, referenceArtifacts: artifacts
  )
}

private func retainedBridgeCase() -> CoreConformanceCaseV1 {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let module = root.appendingPathComponent("Tools/TLCGraphBridge/spike/BridgeGraph.tla")
  let configuration = root.appendingPathComponent("Tools/TLCGraphBridge/spike/BridgeGraph.cfg")
  let arguments = ["-workers", "1", "-fp", "1", "-seed", "1", "-deadlock"]
  return try! CoreConformanceCaseV1(
    id: "adversarial-core-graph-v1", moduleSHA256: SHA256V1.hex(try! Data(contentsOf: module)),
    cfgSHA256: SHA256V1.hex(try! Data(contentsOf: configuration)), arguments: arguments,
    argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(arguments), workers: 1,
    fingerprintPolynomial: 1,
    deadlock: false, operatingSystem: "macos", architecture: "arm64", environment: [:],
    pin: .fixture
  )
}

private func header(_ expectedCase: CoreConformanceCaseV1) -> String {
  let pin = expectedCase.pin
  let record: [String: Any] = [
    "schema": "swifttla.tlc.graph-events", "version": 1, "type": "header",
    "callback": "writer.header",
    "seq": 0, "runId": "00000000-0000-4000-8000-000000000001", "caseId": "fixture",
    "provenance": [
      "tlcTag": pin.tag, "tlcCommit": pin.commit, "tlcJarSha256": pin.jarSHA256,
      "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
      "javaArchiveSha256": pin.javaArchiveSHA256,
      "bridgeClass": pin.bridgeClass, "bridgeSourceSha256": pin.bridgeSourceSHA256,
      "bridgeBinarySha256": pin.bridgeBinarySHA256,
      "moduleSha256": expectedCase.moduleSHA256, "cfgSha256": expectedCase.cfgSHA256,
      "arguments": expectedCase.arguments, "argumentsSha256": expectedCase.argumentsSHA256,
      "workers": expectedCase.workers,
      "fingerprintPolynomial": expectedCase.fingerprintPolynomial,
      "deadlock": expectedCase.deadlock,
      "os": expectedCase.operatingSystem, "architecture": expectedCase.architecture,
      "environment": expectedCase.environment,
    ],
  ]
  return String(data: try! JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
}

private final class RecordingTLCExecutorV1: TLCProcessExecuting, @unchecked Sendable {
  private var pending: [TLCProcessResultV1]
  private(set) var requests: [TLCProcessRequestV1] = []

  init(results: [TLCProcessResultV1]) {
    pending = results
  }

  func execute(_ request: TLCProcessRequestV1) throws -> TLCProcessResultV1 {
    requests.append(request)
    return pending.removeFirst()
  }
}
