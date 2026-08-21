import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct TLCTemporalAdapterTests {
  @Test("TLC temporal adapter retains current exact evidence")
  func capturesCorrelatedExactEvidence() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: fixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.success)
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding), traceAvailability: .notApplicable)
    let input = try fixture.input(swiftResult: swiftResult)
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: FixtureExecutor(stream: stream, result: Fixture.success)))
      .capture(input)

    #expect(result.status == .captured)
    #expect(result.comparison?.outcome == .exact)
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("manifest.json").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("toolchain.json").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("temporal-comparison.json").path))
  }

  @Test("TLC temporal adapter blocks foreign and incomplete evidence before comparison")
  func blocksForeignOrIncompleteEvidence() throws {
    let foreign = try Fixture()
    let foreignCorrelation = try TemporalSymmetryCaseRunCorrelation(
      caseID: foreign.declaredCase.id, gateRunID: foreign.correlation.gateRunID, swiftRunID: foreign.correlation.swiftRunID,
      tlcRunID: UUID(), comparisonRunID: foreign.correlation.comparisonRunID)
    let result = TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
      .capture(try foreign.input(correlation: foreignCorrelation))
    #expect(result.status == .unavailable)
    #expect(result.comparison == nil)
    #expect(result.diagnostic?.code == "foreign-run")

    let incomplete = try Fixture()
    try Data("changed".utf8).write(to: incomplete.module, options: .atomic)
    let incompleteResult = TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
      .capture(try incomplete.input())
    #expect(incompleteResult.status == .unavailable)
    #expect(incompleteResult.comparison == nil)
    #expect(incompleteResult.diagnostic?.code == "source-input-mismatch")
  }

  @Test("TLC temporal adapter does not invent a lasso from an open trace")
  func recordsUnattributableTemporalTraceAsUnavailable() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: fixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.success)
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .satisfied, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding), traceAvailability: .notApplicable)
    let temporalViolation = TLCProcessResult(status: 12, stdout: "Error: Temporal property is violated.", stderr: "")
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: FixtureExecutor(stream: stream, result: temporalViolation)))
      .capture(try fixture.input(swiftResult: swiftResult))

    #expect(result.status == .unavailable)
    #expect(result.comparison?.outcome == .unavailable)
    #expect(result.comparison?.tlcResult.availability == .unavailable)
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("diagnostic.json").path))
  }

  @Test("TLC temporal adapter accepts a numbered two-state loop-back lasso")
  func capturesPinnedLoopBackLasso() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: fixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.temporalViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding), traceAvailability: .available,
      traceEvidence: try Fixture.reference(fixture.module, path: "runs/swift-lasso.json"),
      lasso: try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: ids + [ids[0]]))
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TemporalFixtureExecutor(
        primaryStream: stream, trace: try numberedLoopBackTrace())))
      .capture(try fixture.input(swiftResult: swiftResult))

    #expect(result.status == .captured)
    #expect(result.comparison?.outcome == .exact)
    #expect(result.comparison?.tlcResult.lasso?.cycleStateIDs.count == 3)
  }

  @Test("TLC temporal adapter binds an exact actionless stuttering lasso to a retained state")
  func capturesPinnedStutteringLasso() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: fixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.temporalViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: [state], traceAvailability: .available,
      traceEvidence: try Fixture.reference(fixture.module, path: "runs/swift-lasso.json"),
      lasso: try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [state, state]))
    let trace = try numberedStutteringTrace()
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TemporalFixtureExecutor(primaryStream: stream, trace: trace)))
      .capture(try fixture.input(swiftResult: swiftResult))

    #expect(result.status == .captured)
    #expect(result.comparison?.outcome == .exact)
  }

  @Test("TLC temporal adapter binds a named same-state dump step only when the declared behavior allows stuttering")
  func bindsNamedSameStateDumpStepOnlyWithDeclaredStuttering() throws {
    let rejectedFixture = try Fixture()
    let stream = try graphStream(case: rejectedFixture.coreCase, runID: rejectedFixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: rejectedFixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.temporalViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: [state], traceAvailability: .available,
      traceEvidence: try Fixture.reference(rejectedFixture.module, path: "runs/swift-lasso.json"),
      lasso: try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [state, state]))
    let namedTrace = try numberedStutteringTrace(action: "A")
    let rejected = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TemporalFixtureExecutor(primaryStream: stream, trace: namedTrace)))
      .capture(try rejectedFixture.input(swiftResult: swiftResult))
    #expect(rejected.status == .unavailable)

    let admittedFixture = try Fixture()
    let admittedStream = try graphStream(case: admittedFixture.coreCase, runID: admittedFixture.correlation.tlcRunID)
    let admittedGraph = try TLCGraphEventParser(expectedCase: admittedFixture.coreCase).parseCanonicalRun(
      admittedStream, result: Fixture.temporalViolation)
    let admittedState = try #require(admittedGraph.graph.initialStateKeys.first).canonicalEncoding
    let admittedSwiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: TLCTemporalAdapter.graphID(admittedGraph),
      initialStateIDs: [admittedState], traceAvailability: .available,
      traceEvidence: try Fixture.reference(admittedFixture.module, path: "runs/swift-lasso.json"),
      lasso: try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [admittedState, admittedState]))
    let admitted = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TemporalFixtureExecutor(primaryStream: admittedStream, trace: namedTrace)))
      .capture(try admittedFixture.input(swiftResult: admittedSwiftResult, allowsImplicitStuttering: true))
    #expect(admitted.status == .captured)
    #expect(admitted.comparison?.outcome == .exact)
  }

  @Test("TLC temporal adapter rejects a lasso that is foreign to the captured graph")
  func rejectsForeignTraceEvenWhenItsLoopCloses() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    let graph = try TLCGraphEventParser(expectedCase: fixture.coreCase).parseCanonicalRun(
      stream, result: Fixture.temporalViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: TLCTemporalAdapter.graphID(graph),
      initialStateIDs: graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding), traceAvailability: .available,
      traceEvidence: try Fixture.reference(fixture.module, path: "runs/swift-lasso.json"),
      lasso: try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: ids + [ids[0]]))
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TemporalFixtureExecutor(
        primaryStream: stream, trace: try numberedLoopBackTrace(secondValue: 99))))
      .capture(try fixture.input(swiftResult: swiftResult))

    #expect(result.status == .unavailable)
    #expect(result.comparison?.tlcResult.availability == .unavailable)
  }

  @Test("TLC temporal adapter retains primary evidence when trace capture throws")
  func retainsPrimaryEvidenceAfterTraceCaptureFailure() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.coreCase, runID: fixture.correlation.tlcRunID)
    try Data("stale trace".utf8).write(to: fixture.request.traceOutput, options: .atomic)
    let result = TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: TraceFailingExecutor(primaryStream: stream)))
      .capture(try fixture.input())

    #expect(result.status == .unavailable)
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-result.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("counterexample.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.request.traceOutput.path))
    let resultJSON = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixture.output.appendingPathComponent("tlc-result.json"))) as? [String: Any]
    #expect(resultJSON?["status"] as? Int == 12)
    #expect(resultJSON?["isViolation"] as? Bool == true)
    #expect(resultJSON?["reportedExhaustiveCompletion"] as? Bool == false)
  }

  @Test("TLC temporal adapter rejects a trace path that collides with generated evidence")
  func rejectsTraceOutputThatCollidesWithEvidence() throws {
    let fixture = try Fixture()
    let request = fixture.makeRequest(traceOutput: fixture.output.appendingPathComponent("manifest.json"))
    let manifest = try Data(contentsOf: fixture.manifest)
    let result = TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
      .capture(try fixture.input(request: request))

    #expect(result.status == .unavailable)
    #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    #expect(try Data(contentsOf: fixture.manifest) == manifest)
  }

  @Test("TLC temporal adapter rejects a trace symlink that aliases the module input")
  func rejectsTraceOutputThatAliasesModuleInput() throws {
    let fixture = try Fixture()
    let traceAlias = fixture.root.appendingPathComponent("trace-alias.json")
    try FileManager.default.createSymbolicLink(at: traceAlias, withDestinationURL: fixture.module)
    let module = try Data(contentsOf: fixture.module)
    let result = TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
      .capture(try fixture.input(request: fixture.makeRequest(traceOutput: traceAlias)))

    #expect(result.status == .unavailable)
    #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    #expect(try Data(contentsOf: fixture.module) == module)
    #expect(FileManager.default.fileExists(atPath: traceAlias.path))
  }

  private final class FixtureExecutor: TLCProcessExecuting, Sendable {
    private let stream: Data?
    private let result: TLCProcessResult

    init(stream: Data? = nil, result: TLCProcessResult = Fixture.success) {
      self.stream = stream
      self.result = result
    }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if let stream { try stream.write(to: request.graphEvents, options: .atomic) }
      return result
    }
  }

  private final class TemporalFixtureExecutor: TLCProcessExecuting, Sendable {
    let primaryStream: Data
    let trace: Data

    init(primaryStream: Data, trace: Data) {
      self.primaryStream = primaryStream
      self.trace = trace
    }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if request.traceMode == .dumpJSON {
        try trace.write(to: request.traceOutput, options: .atomic)
      } else {
        try primaryStream.write(to: request.graphEvents, options: .atomic)
      }
      return Fixture.temporalViolation
    }
  }

  private final class TraceFailingExecutor: TLCProcessExecuting, Sendable {
    let primaryStream: Data

    init(primaryStream: Data) { self.primaryStream = primaryStream }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if request.traceMode == .dumpJSON { throw TLCProcessError.failedToStart("trace failed") }
      try primaryStream.write(to: request.graphEvents, options: .atomic)
      return Fixture.temporalViolation
    }
  }

  private final class Fixture {
    static let digest = String(repeating: "a", count: 64)
    static let success = TLCProcessResult(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    static let temporalViolation = TLCProcessResult(
      status: 12, stdout: "Error: Temporal property is violated.", stderr: "")

    let root: URL
    let module: URL
    let configuration: URL
    let manifest: URL
    let toolchain: URL
    let output: URL
    let coreCase: CoreConformanceCase
    let declaredCase: TemporalSymmetryCase
    let correlation: TemporalSymmetryCaseRunCorrelation
    let request: TLCProcessRequest

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent("TLCTemporalAdapterTests-\(UUID())")
      module = root.appendingPathComponent("TemporalFixture.tla")
      configuration = root.appendingPathComponent("TemporalFixture.cfg")
      manifest = root.appendingPathComponent("manifest.json")
      toolchain = root.appendingPathComponent("toolchain.json")
      output = root.appendingPathComponent("evidence")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try Data("---- MODULE TemporalFixture ----\n====\n".utf8).write(to: module)
      try Data("SPECIFICATION Spec\n".utf8).write(to: configuration)
      try Data("{\"schema\":\"TemporalSymmetryCases\"}".utf8).write(to: manifest)
      try Data("{\"toolchain\":\"locked\"}".utf8).write(to: toolchain)
      coreCase = try CoreConformanceCase(
        id: "temporal", moduleSHA256: SHA256.hex(Data(contentsOf: module)),
        cfgSHA256: SHA256.hex(Data(contentsOf: configuration)), arguments: [],
        argumentsSHA256: try CoreConformanceCase.argumentsDigest([]), workers: 1, fingerprintPolynomial: 1,
        deadlock: false, operatingSystem: "macos", architecture: "arm64", environment: [:], pin: .fixture)
      let pin = coreCase.pin
      declaredCase = try TemporalSymmetryCase(
        id: coreCase.id, kind: .temporal, swiftSpec: "TemporalFixture",
        provenance: try CoreDivergenceProvenance(
          caseID: coreCase.id, moduleSHA256: coreCase.moduleSHA256, cfgSHA256: coreCase.cfgSHA256,
          argumentsSHA256: coreCase.argumentsSHA256, tlcTag: pin.tag, tlcCommit: pin.commit,
          tlcJarSHA256: pin.jarSHA256, javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
          javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
          bridgeSourceSHA256: pin.bridgeSourceSHA256, bridgeBinarySHA256: pin.bridgeBinarySHA256),
        finiteBounds: try CoreFiniteBounds(summary: "two states", limits: ["states": 2]),
        semanticCitations: ["TLA+ temporal semantics"],
        sourceInput: try Fixture.reference(module, path: "Verification/TemporalSymmetryConformance/TemporalFixture.tla"),
        configuration: try TemporalSymmetryConfiguration(property: "[] P", fairness: TemporalFairnessMode.none),
        expectedOutcome: .exact)
      correlation = try TemporalSymmetryCaseRunCorrelation(
        caseID: coreCase.id, gateRunID: UUID(), swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
      request = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeClasses: root.appendingPathComponent("bridge"),
        bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
        graphEvents: root.appendingPathComponent("events.jsonl"), traceOutput: root.appendingPathComponent("trace.json"),
        replayInput: root.appendingPathComponent("replay.json"), workingDirectory: root, arguments: [],
        expectedCase: coreCase, runID: correlation.tlcRunID)
    }

    func input(
      swiftResult: TemporalPropertyResult? = nil,
      correlation: TemporalSymmetryCaseRunCorrelation? = nil,
      request: TLCProcessRequest? = nil,
      allowsImplicitStuttering: Bool = false
    ) throws -> TLCTemporalCaptureInput {
      let graphResult = try swiftResult ?? TemporalPropertyResult(
        availability: .unavailable, outcome: nil, graphID: "unavailable", initialStateIDs: ["unavailable"],
        traceAvailability: .unavailable))
      return TLCTemporalCaptureInput(
        declaredCase: declaredCase, correlation: correlation ?? self.correlation, request: request ?? self.request,
        swiftResult: graphResult,
        swiftEvidence: try Fixture.reference(module, path: "runs/swift.json"),
        enablednessEvidence: try Fixture.reference(module, path: "runs/enabled.json"), fairComponents: [], rejectedComponents: [],
        allowsImplicitStuttering: allowsImplicitStuttering,
        manifest: try Fixture.reference(manifest, path: "runs/manifest.json"), manifestURL: manifest,
        toolchain: try Fixture.reference(toolchain, path: "runs/toolchain.json"), toolchainURL: toolchain,
        sourceInputURL: module, outputDirectory: output, relativeOutputDirectory: "runs/temporal")
    }

    func makeRequest(traceOutput: URL) -> TLCProcessRequest {
      TLCProcessRequest(
        javaExecutable: request.javaExecutable,
        jar: request.jar,
        bridgeClasses: request.bridgeClasses,
        bundle: request.bundle,
        graphEvents: request.graphEvents,
        traceOutput: traceOutput,
        replayInput: request.replayInput,
        workingDirectory: request.workingDirectory,
        arguments: request.arguments,
        expectedCase: request.expectedCase,
        runID: request.runID,
        timeout: request.timeout,
        traceMode: request.traceMode,
        referencePin: request.referencePin,
        referenceArtifacts: request.referenceArtifacts
      )
    }

    static func reference(_ url: URL, path: String) throws -> CoreEvidenceReference {
      try CoreEvidenceReference(path: path, sha256: SHA256.hex(Data(contentsOf: url)))
    }
  }
}

private func graphStream(case declaredCase: CoreConformanceCase, runID: UUID) throws -> Data {
  let state: [String: Any] = [
    "fingerprint": "1", "level": 1,
    "bindings": [["ordinal": 0, "name": "x", "tla": "1", "tlaSha256": SHA256.hex(Data("1".utf8))]]
  ]
  let pin = declaredCase.pin
  let provenance: [String: Any] = [
    "tlcTag": pin.tag, "tlcCommit": pin.commit, "tlcJarSha256": pin.jarSHA256,
    "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion, "javaArchiveSha256": pin.javaArchiveSHA256,
    "bridgeClass": pin.bridgeClass, "bridgeSourceSha256": pin.bridgeSourceSHA256, "bridgeBinarySha256": pin.bridgeBinarySHA256,
    "moduleSha256": declaredCase.moduleSHA256, "cfgSha256": declaredCase.cfgSHA256,
    "arguments": declaredCase.arguments, "argumentsSha256": declaredCase.argumentsSHA256,
    "workers": declaredCase.workers, "fingerprintPolynomial": declaredCase.fingerprintPolynomial, "deadlock": declaredCase.deadlock,
    "os": declaredCase.operatingSystem, "architecture": declaredCase.architecture, "environment": declaredCase.environment
  ]
  let common: [String: Any] = [
    "schema": "swifttla.tlc.graph-events", "version": 1, "runId": runID.uuidString.lowercased(), "caseId": declaredCase.id
  ]
  let records = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0, "provenance": provenance]) { $1 },
    common.merging(["type": "initial", "callback": "writeState.initial", "seq": 1, "state": state]) { $1 }
  ]
  let body = try records.reduce(into: Data()) { result, record in
    result.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    result.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 2, "status": "closed",
    "counts": ["header": 1, "initial": 1], "lastBodySeq": 1, "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}

private func temporalGraphStream(case declaredCase: CoreConformanceCase, runID: UUID) throws -> Data {
  let first = graphState(fingerprint: "1", value: 1)
  let second = graphState(fingerprint: "2", value: 2)
  let common = graphCommon(case: declaredCase, runID: runID)
  let records = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0, "provenance": graphProvenance(declaredCase)]) { $1 },
    common.merging(["type": "initial", "callback": "writeState.initial", "seq": 1, "state": first]) { $1 },
    graphTransition(common: common, sequence: 2, source: first, target: second, action: "A"),
    graphTransition(common: common, sequence: 3, source: second, target: first, action: "B")
  ]
  let body = try records.reduce(into: Data()) { result, record in
    result.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    result.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 4, "status": "closed",
    "counts": ["header": 1, "initial": 1, "transition": 2], "lastBodySeq": 3, "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}

private func numberedLoopBackTrace(secondValue: Int = 2) throws -> Data {
  let first: [Any] = [1, ["x": 1]]
  let second: [Any] = [2, ["x": secondValue]]
  let trace: [String: Any] = [
    "vars": ["x"],
    "counterexample": [
      "state": [first, second],
      "action": [
        [first, ["name": "A"], second],
        [second, ["name": "B"], first]
      ]
    ]
  ]
  return try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
}

private func numberedStutteringTrace(action: String = "UnnamedAction") throws -> Data {
  let state: [Any] = [1, ["x": 1]]
  return try JSONSerialization.data(withJSONObject: [
    "vars": ["x"],
    "counterexample": [
      "state": [state],
      "action": [[state, ["name": action], state]]
    ]
  ], options: [.sortedKeys])
}

private func graphState(fingerprint: String, value: Int) -> [String: Any] {
  [
    "fingerprint": fingerprint, "level": 1,
    "bindings": [["ordinal": 0, "name": "x", "tla": String(value), "tlaSha256": SHA256.hex(Data(String(value).utf8))]]
  ]
}

private func graphTransition(
  common: [String: Any], sequence: Int, source: [String: Any], target: [String: Any], action: String
) -> [String: Any] {
  common.merging([
    "type": "transition", "callback": "writeState.action", "seq": sequence, "source": source, "target": target,
    "action": ["name": action, "location": "TemporalFixture:1", "named": true],
    "stateFlags": ["raw": 0, "seen": false, "notInModel": false], "visualization": "none",
    "predicateLocation": NSNull(), "reachable": "reachable"
  ]) { $1 }
}

private func graphCommon(case declaredCase: CoreConformanceCase, runID: UUID) -> [String: Any] {
  [
    "schema": "swifttla.tlc.graph-events", "version": 1,
    "runId": runID.uuidString.lowercased(), "caseId": declaredCase.id
  ]
}

private func graphProvenance(_ declaredCase: CoreConformanceCase) -> [String: Any] {
  let pin = declaredCase.pin
  return [
    "tlcTag": pin.tag, "tlcCommit": pin.commit, "tlcJarSha256": pin.jarSHA256,
    "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion, "javaArchiveSha256": pin.javaArchiveSHA256,
    "bridgeClass": pin.bridgeClass, "bridgeSourceSha256": pin.bridgeSourceSHA256, "bridgeBinarySha256": pin.bridgeBinarySHA256,
    "moduleSha256": declaredCase.moduleSHA256, "cfgSha256": declaredCase.cfgSHA256,
    "arguments": declaredCase.arguments, "argumentsSha256": declaredCase.argumentsSHA256,
    "workers": declaredCase.workers, "fingerprintPolynomial": declaredCase.fingerprintPolynomial,
    "deadlock": declaredCase.deadlock, "os": declaredCase.operatingSystem,
    "architecture": declaredCase.architecture, "environment": declaredCase.environment
  ]
}
