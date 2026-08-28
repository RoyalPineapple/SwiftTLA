import Foundation
import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct TLCTemporalAdapterTests {
  @Test("Temporal property results encode only valid states")
  func temporalPropertyResultIsClosed() throws {
    let lasso = try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: ["s", "s"])
    let violated = TemporalPropertyResult.violated(lasso)
    #expect(try JSONDecoder().decode(
      TemporalPropertyResult.self,
      from: JSONEncoder().encode(violated)) == violated)

    let impossible = Data(#"{"status":"satisfied","lasso":{"prefixStateIDs":[],"cycleStateIDs":["s","s"]}}"#.utf8)
    #expect(throws: EvidenceFormatError.self) {
      try JSONDecoder().decode(TemporalPropertyResult.self, from: impossible)
    }
  }

  @Test("TLC temporal adapter retains exact graph evidence")
  func retainsExactEvidence() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.success)
    let swiftResult = TemporalPropertyResult.satisfied
    let input = try fixture.input(swiftRun: graph, swiftResult: swiftResult)
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: try fixture.executor(
        propertyStream: stream, propertyResult: Fixture.success)))
      .capture(input)

    #expect(comparison.status == .exact)
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("source-input").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("swift-graph.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-graph.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("temporal-comparison.json").path))
  }

  @Test("TLC temporal adapter rejects equal property outcomes over different graphs")
  func rejectsDifferentGraphWithEqualPropertyOutcome() throws {
    let fixture = try Fixture()
    let tlcStream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let swiftStream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let swiftGraph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      swiftStream,
      result: Fixture.success
    )
    let swiftResult = TemporalPropertyResult.satisfied

    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(
        executor: try fixture.executor(propertyStream: tlcStream, propertyResult: Fixture.success)
      )
    ).capture(try fixture.input(swiftRun: swiftGraph, swiftResult: swiftResult))

    #expect(comparison.status == .graphDifference)
  }

  @Test("TLC temporal adapter rejects an incomplete Swift graph")
  func rejectsIncompleteSwiftGraph() throws {
    let fixture = try Fixture()
    let incomplete = try CompletedGraphRun(
      graph: fixture.swiftRun.graph,
      observableActions: fixture.swiftRun.observableActions,
      outcome: .incomplete(reason: "test bound")
    )
    let swiftResult = TemporalPropertyResult.satisfied

    #expect(throws: TLCTemporalAdapterError.graphEvidenceInvalid) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(swiftRun: incomplete, swiftResult: swiftResult))
    }
  }

  @Test("TLC temporal adapter rejects changed source before comparison")
  func rejectsChangedSource() throws {
    let fixture = try Fixture()
    try Data("changed".utf8).write(to: fixture.module, options: .atomic)
    #expect(throws: TLCTemporalAdapterError.sourceInputMismatch) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input())
    }
  }

  @Test("TLC temporal adapter rejects a property configuration that does not match the typed case")
  func rejectsMismatchedTypedProperty() throws {
    let fixture = try Fixture()
    #expect(throws: TLCTemporalAdapterError.configurationMismatch) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(property: .eventually))
    }
  }

  @Test("TLC temporal adapter does not invent a lasso from an open trace")
  func recordsUnattributableTemporalTraceAsUnavailable() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let swiftResult = TemporalPropertyResult.satisfied
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: CompleteGraphExecutor(
        propertyStream: stream,
        graphStream: try temporalGraphStream(
          case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID),
        graphRunID: fixture.completeGraphRequest.runID)))
      .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .unavailable)
    #expect(comparison.tlcResult == .unavailable)
  }

  @Test("TLC temporal adapter rejects an incomplete declared complete-graph pass")
  func rejectsIncompleteCompleteGraphPass() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(
      case: fixture.completeGraphCase,
      runID: fixture.completeGraphRequest.runID)
    #expect(throws: TLCTemporalAdapterError.incompleteGraph) {
      try TLCTemporalAdapter(
        processAdapter: TLCProcessAdapter(executor: FixtureExecutor(
          stream: stream,
          result: Fixture.temporalViolation)))
        .capture(try fixture.input())
    }
  }

  @Test("TLC temporal adapter accepts a numbered two-state loop-back lasso")
  func capturesPinnedLoopBackLasso() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = TemporalPropertyResult.violated(
      try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: ids + [ids[0]]))
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: CompleteGraphExecutor(
        propertyStream: stream,
        graphStream: try temporalGraphStream(
          case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID),
        graphRunID: fixture.completeGraphRequest.runID,
        trace: try numberedLoopBackTrace())))
      .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .exact)
    #expect(lasso(in: comparison.tlcResult)?.cycleStateIDs.count == 3)
  }

  @Test("TLC temporal adapter reports different property outcomes over a complete graph")
  func reportsPropertyOutcomeDifference() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: CompleteGraphExecutor(
        propertyStream: stream,
        graphStream: try temporalGraphStream(
          case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID),
        graphRunID: fixture.completeGraphRequest.runID,
        trace: try numberedLoopBackTrace())))
      .capture(try fixture.input(
        swiftRun: completedSwiftRun(graph),
        swiftResult: .satisfied))

    #expect(comparison.status == .propertyOutcomeDifference)
  }

  @Test("TLC temporal adapter binds an actionless lasso over a completed graph")
  func bindsActionlessLasso() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = TemporalPropertyResult.violated(
      try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [state, state]))
    let trace = try numberedStutteringTrace()
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: try fixture.executor(
        propertyStream: stream,
        trace: trace)))
      .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .exact)
    #expect(lasso(in: comparison.tlcResult) != nil)
  }

  @Test("TLC temporal adapter binds a named same-state dump step only when the declared behavior allows stuttering")
  func bindsNamedSameStateDumpStepOnlyWithDeclaredStuttering() throws {
    let rejectedFixture = try Fixture()
    let stream = try graphStream(case: rejectedFixture.launchCase, runID: rejectedFixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: rejectedFixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = TemporalPropertyResult.violated(
      try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [state, state]))
    let namedTrace = try numberedStutteringTrace(action: "A")
    let rejected = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: try rejectedFixture.executor(
        propertyStream: stream,
        trace: namedTrace)))
      .capture(try rejectedFixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))
    #expect(rejected.tlcResult == .unavailable)

    let admittedFixture = try Fixture()
    let admittedStream = try graphStream(case: admittedFixture.launchCase, runID: admittedFixture.request.runID)
    let admittedGraph = try TLCGraphReader(finiteGraphCase: admittedFixture.launchCase).readCompletedGraph(
      admittedStream, result: Fixture.temporalViolation)
    let admittedState = try #require(admittedGraph.graph.initialStateKeys.first).canonicalEncoding
    let admittedSwiftResult = TemporalPropertyResult.violated(
      try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [admittedState, admittedState]))
    let admitted = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: try admittedFixture.executor(
        propertyStream: admittedStream,
        trace: namedTrace)))
      .capture(try admittedFixture.input(
        swiftRun: completedSwiftRun(admittedGraph),
        swiftResult: admittedSwiftResult,
        allowsImplicitStuttering: true
      ))
    #expect(admitted.status == .exact)
    _ = try #require(lasso(in: admitted.tlcResult))
  }

  @Test("TLC temporal adapter rejects a lasso that is foreign to the captured graph")
  func rejectsForeignTraceEvenWhenItsLoopCloses() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try TLCGraphReader(finiteGraphCase: fixture.launchCase).readCompletedGraph(
      stream, result: Fixture.temporalViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = TemporalPropertyResult.violated(
      try TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: ids + [ids[0]]))
    let comparison = try TLCTemporalAdapter(
      processAdapter: TLCProcessAdapter(executor: try fixture.executor(
        propertyStream: stream,
        trace: try numberedLoopBackTrace(secondValue: 99))))
      .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.tlcResult == .unavailable)
  }

  @Test("TLC temporal adapter retains primary evidence when trace capture throws")
  func retainsPrimaryEvidenceAfterTraceCaptureFailure() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    try Data("stale trace".utf8).write(to: fixture.request.traceOutput, options: .atomic)
    #expect(throws: TLCProcessError.self) {
      try TLCTemporalAdapter(
        processAdapter: TLCProcessAdapter(executor: try fixture.executor(
          propertyStream: stream,
          traceFails: true)))
        .capture(try fixture.input())
    }
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-process.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("counterexample.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.request.traceOutput.path))
    let resultJSON = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixture.output.appendingPathComponent("tlc-process.json"))) as? [String: Any]
    let primary = resultJSON?["primary"] as? [String: Any]
    #expect(primary?["exitStatus"] as? Int == 12)
  }

  @Test("TLC temporal adapter rejects a trace path that collides with generated evidence")
  func rejectsTraceOutputThatCollidesWithEvidence() throws {
    let fixture = try Fixture()
    let protectedOutput = fixture.output.appendingPathComponent("source-input")
    let request = fixture.makeRequest(traceOutput: protectedOutput)
    #expect(throws: TLCTemporalAdapterError.graphEvidenceInvalid) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(request: request))
    }
    #expect(FileManager.default.fileExists(atPath: fixture.output.path) == false)
    #expect(FileManager.default.fileExists(atPath: protectedOutput.path) == false)
  }

  @Test("TLC temporal adapter rejects a trace symlink that aliases the module input")
  func rejectsTraceOutputThatAliasesModuleInput() throws {
    let fixture = try Fixture()
    let traceAlias = fixture.root.appendingPathComponent("trace-alias.json")
    try FileManager.default.createSymbolicLink(at: traceAlias, withDestinationURL: fixture.module)
    let module = try Data(contentsOf: fixture.module)
    #expect(throws: TLCTemporalAdapterError.graphEvidenceInvalid) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(request: fixture.makeRequest(traceOutput: traceAlias)))
    }
    #expect(try Data(contentsOf: fixture.module) == module)
    #expect(FileManager.default.fileExists(atPath: traceAlias.path))
  }

  @Test("TLC temporal adapter requires both passes to use the same declared module closure")
  func rejectsDifferentCompleteGraphBundle() throws {
    let fixture = try Fixture()
    let imported = TLAModuleFile(name: "Imported", tla: "---- MODULE Imported ----\n====\n")
    let bundle = TLAModuleBundle.external(
      root: fixture.completeGraphRequest.bundle.root,
      imports: [imported],
      dependencies: [.init(
        importingModule: fixture.completeGraphRequest.bundle.root.name,
        importedModule: imported.name,
        structuralPath: [])]
    )
    let completeGraphRequest = fixture.makeCompleteGraphRequest(bundle: bundle)

    #expect(throws: TLCTemporalAdapterError.requestMismatch) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(completeGraphRequest: completeGraphRequest))
    }
  }

  @Test("TLC temporal adapter rejects a complete-graph trace symlink that aliases the module input")
  func rejectsCompleteGraphTraceOutputThatAliasesModuleInput() throws {
    let fixture = try Fixture()
    let traceAlias = fixture.root.appendingPathComponent("complete-trace-alias.json")
    try FileManager.default.createSymbolicLink(at: traceAlias, withDestinationURL: fixture.module)
    let module = try Data(contentsOf: fixture.module)
    let completeGraphRequest = fixture.makeCompleteGraphRequest(traceOutput: traceAlias)

    #expect(throws: TLCTemporalAdapterError.graphEvidenceInvalid) {
      try TLCTemporalAdapter(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(completeGraphRequest: completeGraphRequest))
    }
    #expect(try Data(contentsOf: fixture.module) == module)
    #expect(FileManager.default.fileExists(atPath: traceAlias.path))
  }

  private func lasso(in result: TemporalPropertyResult) -> TemporalLassoWitness? {
    if case .violated(let lasso) = result { return lasso }
    return nil
  }

  private func completedSwiftRun(_ run: CompletedGraphRun) throws -> CompletedGraphRun {
    try CompletedGraphRun(
      graph: run.graph,
      observableActions: run.observableActions,
      outcome: .exhaustiveSuccess
    )
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

  private final class CompleteGraphExecutor: TLCProcessExecuting, Sendable {
    let propertyStream: Data
    let graphStream: Data
    let graphRunID: UUID
    let propertyResult: TLCProcessResult
    let trace: Data?
    let traceFails: Bool

    init(
      propertyStream: Data,
      graphStream: Data,
      graphRunID: UUID,
      propertyResult: TLCProcessResult = Fixture.temporalViolation,
      trace: Data? = nil,
      traceFails: Bool = false
    ) {
      self.propertyStream = propertyStream
      self.graphStream = graphStream
      self.graphRunID = graphRunID
      self.propertyResult = propertyResult
      self.trace = trace
      self.traceFails = traceFails
    }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if request.traceMode == .dumpJSON {
        if traceFails { throw TLCProcessError.failedToStart("trace failed") }
        if let trace { try trace.write(to: request.traceOutput, options: .atomic) }
        return Fixture.temporalViolation
      }
      if request.runID == graphRunID {
        try graphStream.write(to: request.graphEvents, options: .atomic)
        return Fixture.success
      }
      try propertyStream.write(to: request.graphEvents, options: .atomic)
      return propertyResult
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
    let graphConfiguration: URL
    let output: URL
    let launchCase: FiniteGraphCase
    let completeGraphCase: FiniteGraphCase
    let temporalCase: TemporalCase
    let request: TLCProcessRequest
    let completeGraphRequest: TLCProcessRequest
    let swiftRun: CompletedGraphRun

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent("TLCTemporalAdapterTests-\(UUID())")
      module = root.appendingPathComponent("TemporalFixture.tla")
      configuration = root.appendingPathComponent("TemporalFixture.cfg")
      graphConfiguration = root.appendingPathComponent("TemporalFixtureGraph.cfg")
      output = root.appendingPathComponent("evidence")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let caseConfiguration = TemporalCaseConfiguration(
        property: .always,
        fairness: .none,
        allowsImplicitStuttering: false)
      try Data("---- MODULE TemporalFixture ----\n====\n".utf8).write(to: module)
      try Data(caseConfiguration.renderedPropertyConfiguration.utf8).write(to: configuration)
      try Data(TemporalCaseConfiguration.renderedGraphConfiguration.utf8).write(to: graphConfiguration)
      launchCase = try FiniteGraphCase(
        id: "temporal",
        exploration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
        moduleSHA256: SHA256.hex(Data(contentsOf: module)),
        cfgSHA256: SHA256.hex(Data(contentsOf: configuration)), arguments: [],
        environment: [:], pin: try testReferencePin())
      completeGraphCase = try FiniteGraphCase(
        id: "temporal",
        exploration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
        moduleSHA256: SHA256.hex(Data(contentsOf: module)),
        cfgSHA256: SHA256.hex(Data(contentsOf: graphConfiguration)), arguments: [],
        environment: [:], pin: try testReferencePin())
      temporalCase = try TemporalCase(
        id: launchCase.id,
        sourceInput: try Fixture.reference(module, path: "Verification/TemporalSymmetryConformance/TemporalFixture.tla"),
        configuration: caseConfiguration,
        exploration: launchCase.exploration)
      request = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeClasses: root.appendingPathComponent("bridge"),
        bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
        graphEvents: root.appendingPathComponent("events.jsonl"), traceOutput: root.appendingPathComponent("trace.json"),
        workingDirectory: root,
        finiteGraphCase: launchCase, runID: UUID())
      completeGraphRequest = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeClasses: root.appendingPathComponent("bridge"),
        bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: graphConfiguration),
        graphEvents: root.appendingPathComponent("complete-events.jsonl"),
        traceOutput: root.appendingPathComponent("complete-trace.json"),
        workingDirectory: root,
        finiteGraphCase: completeGraphCase, runID: UUID())
      swiftRun = try TLCGraphReader(finiteGraphCase: launchCase).readCompletedGraph(
        graphStream(case: launchCase, runID: request.runID),
        result: Self.success
      )
    }

    func input(
      swiftRun: CompletedGraphRun? = nil,
      swiftResult: TemporalPropertyResult? = nil,
      request: TLCProcessRequest? = nil,
      completeGraphRequest: TLCProcessRequest? = nil,
      property: TemporalPropertyKind? = nil,
      allowsImplicitStuttering: Bool = false
    ) throws -> TLCTemporalCaptureInput {
      let graphResult = swiftResult ?? .unavailable
      let selectedCase = try TemporalCase(
          id: temporalCase.id,
          sourceInput: temporalCase.sourceInput,
          configuration: TemporalCaseConfiguration(
            property: property ?? temporalCase.configuration.property,
            fairness: temporalCase.configuration.fairness,
            allowsImplicitStuttering: allowsImplicitStuttering),
          exploration: temporalCase.exploration)
      return TLCTemporalCaptureInput(
        temporalCase: selectedCase,
        request: request ?? self.request,
        completeGraphRequest: completeGraphRequest ?? self.completeGraphRequest,
        swiftRun: swiftRun ?? self.swiftRun,
        swiftResult: graphResult,
        sourceInputURL: module,
        outputDirectory: output)
    }

    func makeRequest(traceOutput: URL) -> TLCProcessRequest {
      TLCProcessRequest(
        javaExecutable: request.javaExecutable,
        jar: request.jar,
        bridgeClasses: request.bridgeClasses,
        bundle: request.bundle,
        graphEvents: request.graphEvents,
        traceOutput: traceOutput,
        workingDirectory: request.workingDirectory,
        finiteGraphCase: request.finiteGraphCase,
        runID: request.runID,
        timeout: request.timeout,
        traceMode: request.traceMode,
        referenceArtifacts: request.referenceArtifacts
      )
    }

    func makeCompleteGraphRequest(
      bundle: TLAModuleBundle? = nil,
      traceOutput: URL? = nil
    ) -> TLCProcessRequest {
      TLCProcessRequest(
        javaExecutable: completeGraphRequest.javaExecutable,
        jar: completeGraphRequest.jar,
        bridgeClasses: completeGraphRequest.bridgeClasses,
        bundle: bundle ?? completeGraphRequest.bundle,
        graphEvents: completeGraphRequest.graphEvents,
        traceOutput: traceOutput ?? completeGraphRequest.traceOutput,
        workingDirectory: completeGraphRequest.workingDirectory,
        finiteGraphCase: completeGraphRequest.finiteGraphCase,
        runID: completeGraphRequest.runID,
        timeout: completeGraphRequest.timeout,
        traceMode: completeGraphRequest.traceMode,
        referenceArtifacts: completeGraphRequest.referenceArtifacts
      )
    }

    func executor(
      propertyStream: Data,
      propertyResult: TLCProcessResult = Fixture.temporalViolation,
      trace: Data? = nil,
      traceFails: Bool = false
    ) throws -> CompleteGraphExecutor {
      try CompleteGraphExecutor(
        propertyStream: propertyStream,
        graphStream: graphStream(case: completeGraphCase, runID: completeGraphRequest.runID),
        graphRunID: completeGraphRequest.runID,
        propertyResult: propertyResult,
        trace: trace,
        traceFails: traceFails)
    }

    static func reference(_ url: URL, path: String) throws -> RetainedFileReference {
      try RetainedFileReference(path: path, sha256: SHA256.hex(Data(contentsOf: url)))
    }
  }
}

private func graphStream(case finiteGraphCase: FiniteGraphCase, runID: UUID) throws -> Data {
  let state: [String: Any] = [
    "fingerprint": "1", "level": 1,
    "bindings": [["ordinal": 0, "name": "x", "tla": "1"]]
  ]
  let common: [String: Any] = [
    "schema": "swifttla.tlc.graph-events", "version": 2, "runId": runID.uuidString.lowercased(), "caseId": finiteGraphCase.id
  ]
  let records = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0]) { $1 },
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

private func temporalGraphStream(case finiteGraphCase: FiniteGraphCase, runID: UUID) throws -> Data {
  let first = graphState(fingerprint: "1", value: 1)
  let second = graphState(fingerprint: "2", value: 2)
  let common = graphCommon(case: finiteGraphCase, runID: runID)
  let records = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0]) { $1 },
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
    "bindings": [["ordinal": 0, "name": "x", "tla": String(value)]]
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

private func graphCommon(case finiteGraphCase: FiniteGraphCase, runID: UUID) -> [String: Any] {
  [
    "schema": "swifttla.tlc.graph-events", "version": 2,
    "runId": runID.uuidString.lowercased(), "caseId": finiteGraphCase.id
  ]
}
