import Darwin
import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity
@Suite(.serialized)
struct TLCGraphReaderTests {
  @Test("long fingerprint references preserve complete canonical graph identity")
  func preservesLongFingerprintReferences() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let original = try completeGraphStream(finiteGraphCase)
    let source = "18446744073709551614"
    let target = "18446744073709551615"
    let renamed = String(decoding: original, as: UTF8.self)
      .replacingOccurrences(of: "\"fingerprint\":\"1\"", with: "\"fingerprint\":\"\(source)\"")
      .replacingOccurrences(of: "\"fingerprint\":\"2\"", with: "\"fingerprint\":\"\(target)\"")
    let stream = try reader.parse(refreshedFooterDigest(Data(renamed.utf8)))
    #expect(Set(stream.states.keys) == [source, target])
    #expect(stream.initialStates == [source])
    #expect(stream.transitions == [TLCGraphTransition(source: source, target: target, action: "Next")])
    #expect(try reader.makeGraphRun(stream, outcome: .completed)
      == reader.makeGraphRun(reader.parse(original), outcome: .completed))
  }

  @Test("file-backed graph decoding preserves complete records and rejects corrupt transport")
  func validatesFileBackedStream() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let complete = try completeGraphStream(finiteGraphCase)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try complete.write(to: file)
    #expect(try reader.parse(contentsOf: file) == reader.parse(complete))

    var changedBody = complete
    changedBody.insert(0x20, at: 1)
    let corruptions: [Data] = [
      Data(), Data(complete.dropLast()), Data([0xEF, 0xBB, 0xBF]) + complete,
      complete + Data([10]), complete + Data([0xFF, 10]), changedBody,
      complete + complete,
    ]
    for data in corruptions {
      try data.write(to: file)
      #expect(throws: TLCGraphEventError.self) {
        try reader.parse(contentsOf: file)
      }
    }
  }

  @Test("scalar string decoding consumes exactly one value")
  func rejectsExtraScalarStrings() throws {
    #expect(try TLCValueParser.parse(#""first, second""#) == .string("first, second"))
    #expect(throws: TLCGraphEventError.self) {
      try TLCValueParser.parse(#""first", "second""#)
    }
    #expect(throws: TLCGraphEventError.self) {
      try TLCValueParser.parse(#""first" "second""#)
    }
  }

  @Test("TLC integer intervals retain their full set value, including nested sets")
  func parsesIntegerIntervals() throws {
    #expect(try TLCValueParser.parse("-1..1") == .set([.integer(-1), .integer(0), .integer(1)]))
    #expect(try TLCValueParser.parse("2..1") == .set([]))
    #expect(try TLCValueParser.parse("{1..1, 2..2}")
      == .set([.set([.integer(1)]), .set([.integer(2)])]))
    #expect(try TLCValueParser.parse(#""1..1""#) == .string("1..1"))
  }

  @Test("malformed or unrepresentable TLC intervals cannot become graph evidence")
  func rejectsInvalidIntegerIntervals() throws {
    for value in ["1..", "1..2..3", "0..9223372036854775807", "-9223372036854775808..0"] {
      #expect(throws: TLCGraphEventError.unsupportedValue(value)) {
        try TLCValueParser.parse(value)
      }
    }
  }

  @Test("frozen graph stream becomes complete canonical evidence")
  func parsesFrozenGraphIntoGraphRun() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let run = try completedGraph(
      try completeGraphStream(finiteGraphCase),
      with: reader,
      outcome: .completed)
    #expect(run.isComparable)
    #expect(run.graph.initialStateKeys.count == 1)
    #expect(run.graph.edges.count == 1)
    #expect(run.observableActions == ["Next"])
  }

  @Test("closed TLC streams with early violations do not certify complete graphs")
  func rejectsEarlyStoppedGraphsAsComplete() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let stream = try reader.parse(completeGraphStream(finiteGraphCase))
    for outcome in [TLCExecutionOutcome.safetyViolation, .livenessViolation, .deadlock] {
      let run = try reader.makeGraphRun(stream, outcome: outcome)
      #expect(!run.isComplete)
      #expect(!run.isComparable)
    }
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
      bridgeJar: directory.appendingPathComponent("bridge"),
      bundle: try TLCProcessRequest.declaredBundle(root: root, configuration: cfg),
      graphEvents: directory.appendingPathComponent("events.jsonl"),
      traceOutput: directory.appendingPathComponent("trace.json"),
      workingDirectory: directory,
      finiteGraphCase: try fixtureCase(try testReferencePin()),
      runID: UUID(),
      invocation: .finiteGraph
    )

    let staged = try request.stageDeclaredBundle()
    let names = try FileManager.default.contentsOfDirectory(
      at: staged.module.deletingLastPathComponent(), includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).sorted()
    #expect(names == ["OnlyThis.cfg", "OnlyThis.tla"])
  }

  @Test("a missing declared module fails before TLC staging")
  func rejectsMissingDeclaredModule() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let root = directory.appendingPathComponent("Root.tla")
    let configuration = directory.appendingPathComponent("Root.cfg")
    let middle = directory.appendingPathComponent("Middle.tla")
    let missing = directory.appendingPathComponent("Required.tla")
    try "---- MODULE Root ----\n====\n".write(
      to: root, atomically: true, encoding: .utf8)
    try "SPECIFICATION Spec\n".write(
      to: configuration, atomically: true, encoding: .utf8)
    try "---- MODULE Middle ----\n====\n".write(
      to: middle, atomically: true, encoding: .utf8)

    #expect(throws: TLCProcessError.invalidModuleBundle(.missingImportedModule(
      module: "Required",
      importedBy: "Middle.tla",
      line: 0,
      expectedFile: missing.path
    ))) {
      _ = try TLCProcessRequest.declaredBundle(
        root: root,
        configuration: configuration,
        imports: [middle, missing],
        dependencies: [
          .init(
            importingModule: "Root",
            importedModule: "Middle",
            structuralPath: ["fixture", "dependencies", "0"]
          ),
          .init(
            importingModule: "Middle",
            importedModule: "Required",
            structuralPath: ["fixture", "dependencies", "1"]
          )
        ]
      )
    }
  }

  @Test("a disconnected declared module fails before TLC staging")
  func rejectsDisconnectedDeclaredModule() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let root = directory.appendingPathComponent("Root.tla")
    let configuration = directory.appendingPathComponent("Root.cfg")
    let imported = directory.appendingPathComponent("Imported.tla")
    try "---- MODULE Root ----\n====\n".write(to: root, atomically: true, encoding: .utf8)
    try "SPECIFICATION Spec\n".write(to: configuration, atomically: true, encoding: .utf8)
    try "---- MODULE Imported ----\n====\n".write(to: imported, atomically: true, encoding: .utf8)
    let request = TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: directory.appendingPathComponent("tla2tools.jar"),
      bridgeJar: directory.appendingPathComponent("bridge"),
      bundle: try TLCProcessRequest.declaredBundle(
        root: root,
        configuration: configuration,
        imports: [imported]
      ),
      graphEvents: directory.appendingPathComponent("events.jsonl"),
      traceOutput: directory.appendingPathComponent("trace.json"),
      workingDirectory: directory,
      finiteGraphCase: try fixtureCase(try testReferencePin()),
      runID: UUID(),
      invocation: .finiteGraph
    )

    #expect(throws: TLCProcessError.invalidModuleBundle(.invalidDeclaredClosure(
      .unreachableModule(module: "Imported", root: "Root")
    ))) {
      _ = try request.stageDeclaredBundle()
    }
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
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let run = try completedGraph(
      try completeGraphStream(finiteGraphCase),
      with: TLCGraphReader(finiteGraphCase: finiteGraphCase),
      outcome: .safetyViolation
    )
    #expect(!run.isComparable)
    #expect(run.outcome == .invariantViolation("TLC safety property violation"))
  }

  @Test("process capture rejects trace symlinks before executing", arguments: [true, false])
  func rejectsTraceSymlink(targetExists: Bool) throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    let target = directory.appendingPathComponent("protected.json")
    if targetExists { try Data("keep".utf8).write(to: target) }
    try FileManager.default.createSymbolicLink(at: request.traceOutput, withDestinationURL: target)
    let executor = RecordingTLCExecutor(results: [])
    #expect(throws: EvidenceFormatError.self) {
      try TLCProcessAdapter(executor: executor).capture(request, retainingIn: directory.appendingPathComponent("retained"))
    }
    #expect(executor.requests.isEmpty)
    if targetExists { #expect(try String(contentsOf: target) == "keep") }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: request.traceOutput.path) == target.path)
  }

  @Test("TLC exit status and closed event stream define graph outcomes")
  func graphOutcomeUsesTypedExecutionOutcome() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let run = try completedGraph(
      try completeGraphStream(finiteGraphCase),
      with: TLCGraphReader(finiteGraphCase: finiteGraphCase),
      outcome: .completed
    )
    #expect(run.outcome == .noViolation)
  }

  @Test("toolchain pin rejects malformed lock fields")
  func rejectsMalformedToolchainFields() throws {
    let pin = try testReferencePin()
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: String(repeating: "g", count: 64),
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceHashes: pin.bridgeSourceHashes, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: "not-a-revision", jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
        bridgeSourceHashes: pin.bridgeSourceHashes,
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
    #expect(throws: FiniteGraphCaseError.self) {
      _ = try TLCReferencePin(
        tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
        javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
        javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: "",
        bridgeSourceHashes: pin.bridgeSourceHashes,
        bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("reference pins validate artifacts and reject changed binaries")
  func validatesReferenceArtifacts() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("reference artifact fixture".utf8)
    for name in ["tlc.jar", "java.tar.gz", "Bridge.java", "Selection.java", "Bridge.jar"] {
      try bytes.write(to: root.appendingPathComponent(name))
    }
    let hash = SHA256.hex(bytes)
    let declared = try testReferencePin()
    let pin = try TLCReferencePin(
      tag: declared.tag, commit: declared.commit, jarSHA256: hash,
      javaDistribution: declared.javaDistribution, javaVersion: declared.javaVersion,
      javaArchiveSHA256: hash, bridgeClass: declared.bridgeClass,
      bridgeSourceHashes: ["Bridge.java": hash, "Selection.java": hash], bridgeBinarySHA256: hash)
    let artifacts = TLCReferenceArtifacts(
      jar: root.appendingPathComponent("tlc.jar"),
      javaArchive: root.appendingPathComponent("java.tar.gz"),
      bridgeSources: ["Bridge.java": root.appendingPathComponent("Bridge.java"),
        "Selection.java": root.appendingPathComponent("Selection.java")],
      bridgeBinary: root.appendingPathComponent("Bridge.jar"),
      jarManifest: "Implementation-Title: TLA+ Tools\nX-Git-Revision: \(pin.commit)\n",
      runtime: TLCJavaRuntimeIdentity(
        version: pin.javaVersion, vendor: "Eclipse Adoptium", architecture: "arm64",
        properties: ["java.runtime.version": pin.javaVersion, "java.vendor": "Eclipse Adoptium"]
      )
    )
    try pin.validate(artifacts)
    let emptyManifest = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSources: artifacts.bridgeSources,
      bridgeBinary: artifacts.bridgeBinary, jarManifest: "", runtime: artifacts.runtime
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("TLC JAR manifest")) {
      try pin.validate(emptyManifest)
    }
    let mismatchedRuntime = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive, bridgeSources: artifacts.bridgeSources,
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
      try pin.validate(mismatchedRuntime)
    }
    let selector = root.appendingPathComponent("Selection.java")
    try Data("changed source".utf8).write(to: selector)
    #expect(throws: FiniteGraphCaseError.pinMismatch("bridge source Selection.java")) {
      try pin.validate(artifacts)
    }
    try bytes.write(to: selector)
    let missingSource = TLCReferenceArtifacts(
      jar: artifacts.jar, javaArchive: artifacts.javaArchive,
      bridgeSources: ["Bridge.java": root.appendingPathComponent("Bridge.java")],
      bridgeBinary: artifacts.bridgeBinary, jarManifest: artifacts.jarManifest, runtime: artifacts.runtime)
    #expect(throws: FiniteGraphCaseError.pinMismatch("bridge source inventory")) {
      try pin.validate(missingSource)
    }
    try Data("changed binary".utf8).write(to: artifacts.bridgeBinary)
    #expect(throws: FiniteGraphCaseError.pinMismatch("bridge binary")) {
      try pin.validate(artifacts)
    }
  }

  @Test("TLC command selects the bridge and identifies its graph stream")
  func assemblesFrozenBridgeCommand() throws {
    let request = TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
      bridgeJar: URL(fileURLWithPath: "/tmp/bridge.jar"),
      bundle: fixtureBundle(),
      graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
      traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      finiteGraphCase: try fixtureCase(try testReferencePin(), arguments: ["-workers", "1"]),
      runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
      invocation: .finiteGraph
    )
    let command = request.launchArguments
    #expect(command.contains("-Dswifttla.tlc.graph.path=/tmp/events.jsonl"))
    #expect(command.contains("-Dswifttla.tlc.graph.run-id=00000000-0000-4000-8000-000000000001"))
    #expect(command.contains("-Dswifttla.tlc.graph.case-id=fixture"))
    #expect(command.contains("/tmp/tla2tools.jar:/tmp/bridge.jar"))
    #expect(command.contains("-dumpTrace"))
    #expect(command.contains("/tmp/trace.json"))
  }

  @Test("execution rejects substituted JAR and bridge classpath artifacts")
  func rejectsSubstitutedExecutionArtifacts() throws {
    let root = URL(fileURLWithPath: "/tmp/validated-bridge")
    let artifacts = TLCReferenceArtifacts(
      jar: URL(fileURLWithPath: "/tmp/validated-tla2tools.jar"),
      javaArchive: URL(fileURLWithPath: "/tmp/temurin.tar.gz"),
      bridgeSources: ["Bridge.java": URL(fileURLWithPath: "/tmp/LosslessStateWriter.java")],
      bridgeBinary: root,
      jarManifest: "",
      runtime: TLCJavaRuntimeIdentity(version: "", vendor: "", architecture: "", properties: [:])
    )
    let substitutedJar = try requestWithReferenceArtifacts(
      jar: URL(fileURLWithPath: "/tmp/substituted-tla2tools.jar"), bridgeJar: root,
      artifacts: artifacts
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("execution TLC JAR")) {
      try substitutedJar.validateReferenceBinding(artifacts: artifacts)
    }
    let substitutedBridge = try requestWithReferenceArtifacts(
      jar: artifacts.jar, bridgeJar: URL(fileURLWithPath: "/tmp/substituted-bridge"),
      artifacts: artifacts
    )
    #expect(throws: FiniteGraphCaseError.pinMismatch("execution bridge JAR")) {
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
    let trace = try TLCTraceParser().parseCounterexample(Data(contentsOf: traceURL),
      states: (0...3).map { CanonicalState(bindings: ["x": .integer($0)]) })
    #expect(trace.steps.count == 4)
    #expect(trace.steps.map(\.action) == [nil, "Next", "Next", "Next"])
    #expect(trace.cycleStartIndex == nil)
    #expect(trace.steps.map(\.state) == (0...3).map { CanonicalState(bindings: ["x": .integer($0)]).key })
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
    try "#!/bin/sh\ntrap '' TERM\nwhile true; do /bin/sleep 0.1; done\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let started = Date()
    #expect(throws: TLCProcessError.self) {
      _ = try executeProcess(
        executable: executable, arguments: [], directory: directory, timeout: 0.25)
    }
    #expect(Date().timeIntervalSince(started) < 3)
  }

  @Test("the TLC pin rejects a banner from another revision")
  func rejectsWrongTLCBanner() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("wrong-banner.sh")
    try "#!/bin/sh\nprintf 'TLC2 Version 2026.07.31.184830 (rev: deadbee)\\n'\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let processOutput = try executeProcess(
      executable: executable, arguments: [], directory: directory, timeout: 1, environment: [:])
    #expect(throws: FiniteGraphCaseError.pinMismatch("TLC banner")) {
      try testReferencePin().validateReportedTLCBanner(processOutput.stdout + "\n" + processOutput.stderr)
    }
  }

  @Test("the TLC subprocess uses only the declared environment")
  func excludesHostEnvironmentAndPreservesAllowlist() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("environment.sh")
    try "#!/bin/sh\n"
      .appending("printf 'TLC2 Version 2026.08.11.125311 (rev: 9787e65)\\n'\n")
      .appending("printf 'home=%s allowed=%s\\n' \"${HOME-unset}\" \"${FINITE_GRAPH_ALLOWED_VALUE-unset}\"\n")
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let processOutput = try executeProcess(
      executable: executable,
      arguments: [],
      directory: directory,
      timeout: 1,
      environment: ["FINITE_GRAPH_ALLOWED_VALUE": "declared"]
    )
    #expect(processOutput.stdout.contains("home=unset allowed=declared"))
  }

  @Test("JSON validation rejects escaped duplicate keys and malformed string values at their source line")
  func validatesJSONStringsAndKeys() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let prefix = try header(finiteGraphCase) + "\n"
    let duplicateKeys = [
      (#"{"":0,"":1}"#, ""),
      (#"{"plain":0,"plain":1}"#, "plain"),
      (#"{"slash/":0,"slash\/":1}"#, "slash/"),
      (#"{"value":"escaped quote: \" and slash: \\","nested":{"x":0,"\u0078":1}}"#, "x"),
      (#"{"\uD83D\uDE00":0,"😀":1}"#, "😀")
    ]
    for (record, key) in duplicateKeys {
      #expect(throws: TLCGraphEventError.duplicateKey(line: 2, key: key)) {
        try reader.parse(Data((prefix + record + "\n").utf8))
      }
    }
    let malformed = [
      "{\"control\u{001f}key\":0}",
      #"{"\q":0}"#, #"{"\uD800":0}"#,
      #"{"value":"\q"}"#, #"{"value":"\uD800"}"#, #"{"value":"\uDC00"}"#,
      #"{"value":"\u12"}"#, #"{"value":"unterminated}"#
    ]
    for record in malformed {
      #expect(throws: TLCGraphEventError.malformedJSON(line: 2)) {
        try reader.parse(Data((prefix + record + "\n").utf8))
      }
    }
  }

  @Test("JSON keys preserve plain, escaped, and Unicode spellings")
  func decodesObjectKeys() throws {
    let source = #"{"":0,"plain":1,"space key":2,"\"quote\"":3,"slash\\":4,"\uD83D\uDE00":5,"café":6}"#
    let values = try decodeJSONObject(Data(source.utf8), line: 7)
    #expect(Set(values.keys) == ["", "plain", "space key", "\"quote\"", "slash\\", "😀", "café"])
    for (key, value) in ["": 0, "plain": 1, "space key": 2, "\"quote\"": 3, "slash\\": 4, "😀": 5, "café": 6] {
      #expect(values[key] as? Int == value)
    }
    let invalidUTF8 = Data([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x30, 0x7d])
    #expect(throws: TLCGraphEventError.malformedJSON(line: 7)) {
      try decodeJSONObject(invalidUTF8, line: 7)
    }
  }

  @Test("graph event reader rejects malformed footer and unsupported callbacks")
  func rejectsMalformedStreams() throws {
    let pin = try testReferencePin()
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
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":3,\"type\":\"initial\",",
      "\"callback\":\"writeState.initial\",\"seq\":2,",
      "\"runId\":\"00000000-0000-4000-8000-000000000001\",\"caseId\":\"fixture\",\"state\":{}}\n"
    ].joined()
    #expect(throws: TLCGraphEventError.self) {
      try stream.parse(Data(invalidInitial.utf8))
    }
    let unsupportedCallback = [
      "\(try header(finiteGraphCase))\n",
      "{\"schema\":\"swifttla.tlc.graph-events\",\"version\":3,\"type\":\"unsupported\",",
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
        bridgeSourceHashes: pin.bridgeSourceHashes, bridgeBinarySHA256: pin.bridgeBinarySHA256
      )
    }
  }

  @Test("graph event stream requires stable identity, order, closure, counts, and body bytes")
  func validatesStreamIntegrity() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
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
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let stream = try completeGraphStreamWithStutteringObservation(finiteGraphCase)
    #expect(try reader.parse(stream).transitions.count == 1)
    let rejected = Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "STUTTERING", with: "ARBITRARY").utf8)
    #expect(throws: TLCGraphEventError.unsupportedCallback("writeState.visualization")) {
      try reader.parse(rejected)
    }
  }

  @Test("excluded predicate observations still require decodable values", arguments: ["source", "target"])
  func rejectsUndecodableExcludedValues(_ position: String) throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let stream = try completeGraphStreamWithExcludedPredicateObservation(finiteGraphCase,
      sourceValue: position == "source" ? "<<" : "2",
      targetValue: position == "target" ? "<<" : "2")
    #expect(throws: TLCGraphEventError.unsupportedValue("<<")) {
      try reader.parse(stream)
    }
  }

  @Test("graph event reader retains only exact excluded predicate observations")
  func acceptsExcludedPredicateObservationsWithoutAddingGraphEdges() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
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
    let expected = try fixtureCase(try testReferencePin(), renderedActions: [call])
    let reader = TLCGraphReader(finiteGraphCase: expected)
    let stream = try functionRecordNormalizationStream(expected, actionLocation: "<Step(0) line 1, col 1 to line 1, col 2 of module Fixture>")
    let run = try completedGraph(
      stream,
      with: reader,
      outcome: .completed)
    #expect(run.observableActions == ["Step__0"])
    #expect(run.graph.initialStateKeys.first?.canonicalEncoding.contains("63617273=record") == true)
    let undeclared = try refreshedFooterDigest(Data(String(decoding: stream, as: UTF8.self)
      .replacingOccurrences(of: "<Step(0)", with: "<Step(1)").utf8))
    #expect(throws: TLCGraphEventError.invalidRecord(line: 3, reason: "undeclared invocation identity")) {
      try reader.parse(undeclared)
    }
  }

  @Test("argument-free actions resolve alongside parameterized actions", arguments: ["Next", "NextAlias"])
  func resolvesMixedActionArities(_ renderedName: String) throws {
    let action = RenderedAction(sourceName: "Next", arguments: [], renderedName: renderedName)
    let parameterized = RenderedAction(sourceName: "Step", arguments: [.int(0)], renderedName: "Step__0")
    let finiteGraphCase = try fixtureCase(try testReferencePin(), renderedActions: [action, parameterized])
    let stream = try refreshedFooterDigest(Data(String(
      decoding: completeGraphStream(finiteGraphCase), as: UTF8.self
    ).replacingOccurrences(
      of: "\"location\":\"\"",
      with: "\"location\":\"<Next line 1, col 1 to line 1, col 2 of module Fixture>\""
    ).utf8))

    let parsed = try TLCGraphReader(finiteGraphCase: finiteGraphCase).parse(stream)

    #expect(parsed.transitions.map(\.action) == [renderedName])
  }

  @Test("one INSTANCE callback retains every distinct resolved invocation")
  func retainsResolvedInstanceActions() throws {
    let actions = (1...2).map { RenderedAction(sourceName: "Step", arguments: [.int($0)], renderedName: "Step__\($0)") }
    let finiteGraphCase = try fixtureCase(try testReferencePin(), renderedActions: actions)
    let resolved: [[String: Any]] = (1...2).map {
      ["name": "Step", "location": "<Step(\($0)) line 1, col 1 to line 1, col 2 of module Original>", "named": true]
    }
    let data = try completeGraphStream(finiteGraphCase, resolvedActions: resolved)
    let run = try completedGraph(data, with: TLCGraphReader(finiteGraphCase: finiteGraphCase), outcome: .completed)
    #expect(run.observableActions == ["Step__1", "Step__2"])
    #expect(run.graph.edges.count == 2)
    #expect(Set(run.graph.edges.map(\.source)).count == 1)
    #expect(Set(run.graph.edges.map(\.target)).count == 1)
    let record = try #require(try JSONSerialization.jsonObject(with: Data(data.split(separator: 10)[2])) as? [String: Any])
    let original = try #require(record["action"] as? [String: Any])
    #expect(original["name"] as? String == "Next")

    for invalid in [[], [resolved[0], resolved[0]],
                    [["name": "Foreign", "location": "", "named": true]],
                    [["name": "Step", "location": "", "named": false]],
                    [["name": "Step", "named": true]]] {
      #expect(throws: TLCGraphEventError.self) {
        try TLCGraphReader(finiteGraphCase: finiteGraphCase).parse(
          completeGraphStream(finiteGraphCase, resolvedActions: invalid))
      }
    }
    let obsolete = try refreshedFooterDigest(Data(String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "\"version\":3", with: "\"version\":2").utf8))
    #expect(throws: TLCGraphEventError.self) {
      try TLCGraphReader(finiteGraphCase: finiteGraphCase).parse(obsolete)
    }
  }

  @Test("fingerprint matching preserves exact Unicode value bytes", arguments: [false, true])
  func rejectsUnicodeFingerprintAlias(_ seen: Bool) throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let stream = try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: seen,
      representativeValue: "\"é\"", aliasValue: "\"e\u{301}\"")
    #expect(throws: TLCGraphEventError.invalidRecord(line: 4, reason: "fingerprint binding mismatch")) {
      try TLCGraphReader(finiteGraphCase: finiteGraphCase).parse(stream)
    }
  }

  @Test("reduced TLC fingerprint aliases must belong to the declared symmetry orbit")
  func acceptsOnlyDeclaredSymmetryAliases() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let parsed = try reader.parse(try fingerprintAliasGraphStream(finiteGraphCase, aliasSeen: true))
    #expect(parsed.transitions.count == 1)
    #expect(Set(parsed.transitions.map(\.target)) == ["2"])
    #expect(parsed.states["2"]?.bindings.first?.tla == "A")
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
      try testReferencePin(),
      symmetryReduction: .enabled(maximumPermutationCount: 2),
      symmetryGenerators: [try SymmetryPermutation(constantMapping: ["A": "B", "B": "A"])]
    )
    let reduced = try TLCGraphReader(finiteGraphCase: reducedCase).parse(
      try fingerprintAliasGraphStream(reducedCase, aliasSeen: true, aliasValue: "B")
    )
    #expect(reduced.transitions.count == 1)
    #expect(Set(reduced.transitions.map(\.target)) == ["2"])
    #expect(reduced.states["2"]?.bindings.first?.tla == "A")
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
    #expect(throws: SymmetryOrbitError.emptyPermutationGroup) {
      try fixtureCase(
        try testReferencePin(),
        symmetryReduction: .enabled(maximumPermutationCount: 2))
    }
  }

  @Test("process capture requests graph and counterexample in one invocation", arguments: [Int32(0), 12, 13])
  func capturesOnce(status: Int32) throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    let events = try completeGraphStream(request.finiteGraphCase)
    try events.write(to: request.graphEvents, options: .atomic)
    let originalFile = try FileManager.default.attributesOfItem(atPath: request.graphEvents.path)[.systemFileNumber] as? NSNumber
    try Data("stale trace".utf8).write(to: request.traceOutput)
    let executor = RecordingTLCExecutor(results: [.init(status: status, stdout: "TLC output", stderr: "")])
    let output = directory.appendingPathComponent("retained")
    let capture = try TLCProcessAdapter(executor: executor).capture(request, retainingIn: output)
    #expect(executor.requests.count == 1)
    #expect(executor.requests.first == request)
    #expect(request.launchArguments.contains("-dumpTrace"))
    #expect(capture.graph.isComplete == (status == 0))
    #expect(!FileManager.default.fileExists(atPath: request.traceOutput.path))
    #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("counterexample.json").path))
    let retained = output.appendingPathComponent("graph-events.jsonl")
    #expect(!FileManager.default.fileExists(atPath: request.graphEvents.path))
    #expect(try Data(contentsOf: retained) == events)
    #expect(originalFile != nil)
    #expect(try FileManager.default.attributesOfItem(atPath: retained.path)[.systemFileNumber] as? NSNumber == originalFile)
    try Data("later invocation".utf8).write(to: request.graphEvents)
    #expect(try Data(contentsOf: retained) == events)
  }

  @Test("graph retention rejects symbolic links without moving their targets")
  func rejectsSymbolicGraphOutput() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    let original = directory.appendingPathComponent("original.jsonl")
    let events = try completeGraphStream(request.finiteGraphCase)
    try events.write(to: original)
    try FileManager.default.createSymbolicLink(at: request.graphEvents, withDestinationURL: original)
    let executor = RecordingTLCExecutor(results: [.init(status: 0, stdout: "TLC output", stderr: "")])
    #expect(throws: EvidenceFormatError.self) {
      try TLCProcessAdapter(executor: executor).capture(request, retainingIn: directory.appendingPathComponent("retained"))
    }
    #expect(try Data(contentsOf: original) == events)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: request.graphEvents.path) == original.path)
  }

  @Test("TLC exit status defines the process outcome")
  func executionOutcomeUsesExitStatusAndClosedStream() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    try completeGraphStream(request.finiteGraphCase).write(to: request.graphEvents, options: .atomic)
    let executor = RecordingTLCExecutor(results: [
      .init(status: 0, stdout: "Error: violation text from a module path", stderr: "")
    ])

    let capture = try TLCProcessAdapter(executor: executor).capture(
      request,
      retainingIn: directory.appendingPathComponent("evidence")
    )

    #expect(capture.outcome == .completed)
    #expect(capture.graph.isComparable)
    #expect(executor.requests.count == 1)
  }

  @Test("TLC completion requires a closed graph stream")
  func executionOutcomeRequiresClosedStream() throws {
    let directory = try helperProcessDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try retainedCaptureRequest(in: directory)
    let lines = String(
      decoding: try completeGraphStream(request.finiteGraphCase),
      as: UTF8.self
    ).split(separator: "\n")
    try Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
      .write(to: request.graphEvents, options: .atomic)
    let executor = RecordingTLCExecutor(results: [
      .init(status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    ])

    #expect(throws: TLCGraphEventError.missingFooter) {
      try TLCProcessAdapter(executor: executor).capture(
        request,
        retainingIn: directory.appendingPathComponent("evidence")
      )
    }
    #expect(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("evidence/logs/tlc.stdout.log").path
    ))
  }

  @Test("graph event integers reject overflow before narrowing")
  func rejectsIntegerOverflow() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    for value in [String(UInt64(Int.max) + 1), String(UInt64.max)] {
      let data = try mutatedCompleteGraphStream(finiteGraphCase) {
        $0.replacingOccurrences(of: "\"level\":1", with: "\"level\":\(value)")
      }
      #expect(throws: TLCGraphEventError.invalidRecord(line: 2, reason: "level")) {
        try reader.parse(data)
      }
    }
    _ = try reader.parse(mutatedCompleteGraphStream(finiteGraphCase) {
      $0.replacingOccurrences(of: "\"level\":1", with: "\"level\":\(Int.max)")
    })
  }

  @Test("graph event reader rejects booleans for integers and numbers for booleans")
  func rejectsWrongJSONPrimitiveTypes() throws {
    let finiteGraphCase = try fixtureCase(try testReferencePin())
    let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
    let mutations = [
      { (line: String) in line.replacingOccurrences(of: "\"version\":3", with: "\"version\":true")
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
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeJar: valid.bridgeJar,
      bundle: wrongModule, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      workingDirectory: directory.appendingPathComponent("wrong-module"),
      finiteGraphCase: finiteGraphCase, runID: UUID(), invocation: .finiteGraph
    )
    #expect(throws: FiniteGraphCaseError.moduleDigestMismatch) {
      let wrongStaged = try wrongModuleRequest.stageDeclaredBundle()
      try wrongModuleRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
    let wrongConfiguration = TLAModuleBundle.external(
      root: TLAModuleFile(name: "Module", tla: "module bytes", cfg: "wrong cfg")
    )
    let wrongConfigurationRequest = TLCProcessRequest(
      javaExecutable: valid.javaExecutable, jar: valid.jar, bridgeJar: valid.bridgeJar,
      bundle: wrongConfiguration, graphEvents: valid.graphEvents, traceOutput: valid.traceOutput,
      workingDirectory: directory.appendingPathComponent("wrong-configuration"),
      finiteGraphCase: finiteGraphCase, runID: UUID(), invocation: .finiteGraph
    )
    #expect(throws: FiniteGraphCaseError.cfgDigestMismatch) {
      let wrongStaged = try wrongConfigurationRequest.stageDeclaredBundle()
      try wrongConfigurationRequest.validateLaunchBinding(module: wrongStaged.module, configuration: wrongStaged.configuration)
    }
  }
}

private func completedGraph(
  _ data: Data,
  with reader: TLCGraphReader,
  outcome: TLCExecutionOutcome
) throws -> GraphRun {
  try reader.makeGraphRun(reader.parse(data), outcome: outcome)
}

private func retainedCaptureRequest(in directory: URL) throws -> TLCProcessRequest {
  return TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeJar: URL(fileURLWithPath: "/tmp/bridge.jar"),
    bundle: fixtureBundle(),
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("counterexample.json"),
    workingDirectory: directory,
    finiteGraphCase: try fixtureCase(try testReferencePin(), arguments: ["-workers", "1", "-fp", "1"]),
    runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
    invocation: .finiteGraph
  )
}

private func fixtureBundle() -> TLAModuleBundle {
  .external(root: TLAModuleFile(name: "Fixture", tla: "---- MODULE Fixture ----", cfg: "SPECIFICATION Spec"))
}
