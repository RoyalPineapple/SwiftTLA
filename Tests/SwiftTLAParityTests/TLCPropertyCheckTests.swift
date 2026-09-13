import Foundation
import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct TLCPropertyCheckTests {
  @Test("temporal trace membership requires the ordered labeled path")
  func temporalTraceMembershipRequiresOrderedLabeledPath() throws {
    let zero = CanonicalState(bindings: ["value": .integer(0)])
    let one = CanonicalState(bindings: ["value": .integer(1)])
    let advance = CanonicalEdge(source: zero.key, action: "Advance", target: one.key)
    let run = try GraphRun(
      isComplete: true,
      graph: CanonicalGraph(initialStates: [zero], states: [zero, one], edges: [advance]),
      observableActions: ["Advance"],
      outcome: .noViolation
    )

    let valid = GraphTrace(id: "path", steps: [
      .init(state: zero.key, action: nil), .init(state: one.key, action: "Advance")])
    try valid.validate(in: run.graph)
    #expect(throws: GraphRunError.self) {
      try GraphTrace(id: "wrong action", steps: [
        .init(state: zero.key, action: nil), .init(state: one.key, action: "Other")]).validate(in: run.graph)
    }
    #expect(throws: GraphRunError.self) {
      try GraphTrace(id: "wrong initial", steps: [
        .init(state: one.key, action: nil), .init(state: zero.key, action: "Advance")]).validate(in: run.graph)
    }
  }

  @Test("Temporal property results encode only valid states")
  func propertyResultIsClosed() throws {
    let lasso = testCycle(["s", "s"])
    let violated = PropertyResult.violated(lasso)
    #expect(try JSONDecoder().decode(
      PropertyResult.self,
      from: JSONEncoder().encode(violated)) == violated)

    let impossible = Data(#"{"status":"satisfied","trace":{"id":"bad","steps":[{"state":"s"}]}}"#.utf8)
    #expect(throws: EvidenceFormatError.self) {
      try JSONDecoder().decode(PropertyResult.self, from: impossible)
    }
  }

  @Test("property reports retain results without copying shared graphs", arguments: ["AlwaysEventuallyP", "Positive"])
  func retainsResultsWithoutGraphCopies(property: String) throws {
    let fixture = try Fixture(check: .property(property))
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase)
    let swiftResult = PropertyResult.satisfied
    let input = try fixture.input(swiftRun: graph, swiftResult: swiftResult)
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.success)))
      .capture(input)

    #expect(comparison.status == .exact)
    let process = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
      fixture.output.appendingPathComponent("tlc-process.json"))) as? [String: Any])
    #expect(process["configuration"] as? String == fixture.request.bundle.cfg)
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("source-input").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("swift-graph.jsonl").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-graph.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("property-comparison.json").path))
    #expect(FileManager.default.fileExists(
      atPath: fixture.output.appendingPathComponent("complete-graph-pass").path) == false)
  }

  @Test("property comparisons reuse one captured graph")
  func reusesCapturedGraph() throws {
    let fixture = try Fixture()
    let shared = try fixture.captureGraph()
    let rawGraph = try Data(contentsOf: shared.request.graphEvents)
    let executor = PropertyExecutor(
      propertyResult: Fixture.success)
    let adapter = TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: executor))
    for index in 0..<2 {
      let result = try adapter.capture(fixture.input(completeGraph: shared, swiftResult: .satisfied,
        outputDirectory: fixture.root.appendingPathComponent("property-\(index)")))
      #expect(result.status == .exact)
    }
    #expect(try Data(contentsOf: shared.request.graphEvents) == rawGraph)
  }

  @Test("shared graphs must use the property's exploration bounds")
  func rejectsDifferentSharedBounds() throws {
    let fixture = try Fixture(completeGraphStateLimit: 20)
    #expect(throws: TLCPropertyCheckError.requestMismatch) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input())
    }
  }

  @Test("TLC property checker rejects equal property outcomes over different graphs")
  func rejectsDifferentGraphWithEqualPropertyOutcome() throws {
    let fixture = try Fixture()
    let swiftStream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let swiftGraph = try completedGraph(swiftStream, for: fixture.launchCase)
    let swiftResult = PropertyResult.satisfied

    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(
        executor: PropertyExecutor(propertyResult: Fixture.success)
      )
    ).capture(try fixture.input(swiftRun: swiftGraph, swiftResult: swiftResult))

    #expect(comparison.status == .graphDifference)
  }

  @Test("TLC property checker rejects an incomplete Swift graph")
  func rejectsIncompleteSwiftGraph() throws {
    let fixture = try Fixture()
    let incomplete = try GraphRun(
      isComplete: false,
      graph: fixture.swiftRun.graph,
      observableActions: fixture.swiftRun.observableActions,
      outcome: .incomplete(reason: "test bound")
    )
    let swiftResult = PropertyResult.satisfied

    #expect(throws: TLCPropertyCheckError.graphEvidenceInvalid) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(swiftRun: incomplete, swiftResult: swiftResult))
    }
  }

  @Test("TLC property checker rejects a property configuration that does not match the typed case")
  func rejectsMismatchedTypedProperty() throws {
    let fixture = try Fixture()
    #expect(throws: TLCPropertyCheckError.configurationMismatch) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(check: .property("EventuallyP")))
    }
  }

  @Test("declared property names need no validation registry entry")
  func checksCustomProperty() throws {
    let fixture = try Fixture(check: .property("CustomProgress"))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.success)))
      .capture(try fixture.input(swiftResult: .satisfied))
    #expect(comparison.check == .property("CustomProgress"))
    #expect(comparison.status == .exact)
  }

  @Test("TLC property checker does not invent a lasso from an open trace")
  func recordsUnattributableTemporalTraceAsUnavailable() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase, outcome: .livenessViolation)
    let swiftResult = PropertyResult.satisfied
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor()))
      .capture(try fixture.input(completeGraph: completeGraph, swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .unavailable)
    #expect(comparison.tlcResult == .unavailable)
  }

  @Test("temporal comparison rejects an incomplete shared graph")
  func rejectsIncompleteSharedGraph() throws {
    let fixture = try Fixture()
    let shared = try fixture.captureGraph(result: Fixture.temporalViolation)
    #expect(throws: TLCPropertyCheckError.incompleteGraph) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(completeGraph: shared))
    }
  }

  @Test("TLC property checker accepts a numbered two-state loop-back lasso")
  func capturesPinnedLoopBackLasso() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase, outcome: .livenessViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = PropertyResult.violated(
      testCycle(ids + [ids[0]]))
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: try numberedLoopBackTrace())))
      .capture(try fixture.input(completeGraph: completeGraph, swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .exact)
    #expect(counterexample(in: comparison.tlcResult)?.steps.count == 3)
  }

  @Test("TLC property checker reports different property outcomes over a complete graph")
  func reportsPropertyOutcomeDifference() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase, outcome: .livenessViolation)
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: try numberedLoopBackTrace())))
      .capture(try fixture.input(completeGraph: completeGraph,
        swiftRun: completedSwiftRun(graph),
        swiftResult: .satisfied))

    #expect(comparison.status == .propertyOutcomeDifference)
  }

  @Test("TLC property checker binds an actionless lasso over a completed graph")
  func bindsActionlessLasso() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase, outcome: .livenessViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = PropertyResult.violated(
      testCycle([state, state]))
    let trace = try numberedStutteringTrace()
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: trace)))
      .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))

    #expect(comparison.status == .exact)
    #expect(counterexample(in: comparison.tlcResult) != nil)
  }

  @Test("initial safety violations use the same property checker", arguments: ["AlwaysP", "IsTwo"])
  func bindsInitialSafetyViolation(property: String) throws {
    let fixture = try Fixture(check: .property(property))
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = PropertyResult.violated(
      testCycle([state, state]))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation,
        trace: try numberedInitialStateTrace())))
      .capture(try fixture.input(
        swiftRun: graph,
        swiftResult: swiftResult))

    #expect(comparison.status == .exact)
    let retained = try #require(counterexample(in: comparison.tlcResult))
    #expect(retained.cycleStartIndex == nil)
    #expect(retained.steps.map { $0.state.canonicalEncoding } == [state])
  }

  @Test("deadlock checks retain finite counterexamples independently of named properties")
  func retainsDeadlock() throws {
    let fixture = try Fixture(check: .deadlock)
    let trace = try numberedInitialStateTrace()
    let nativeTrace = try TLCTraceParser().parseCounterexample(trace)
    let comparison = try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
      propertyResult: .init(status: 11, stdout: "Deadlock reached.", stderr: ""), trace: trace)))
      .capture(try fixture.input(swiftResult: .violated(nativeTrace)))
    #expect(comparison.status == .exact)
    #expect(comparison.check == .deadlock)
    #expect(counterexample(in: comparison.tlcResult)?.cycleStartIndex == nil)
  }

  @Test("a deadlock counterexample must end at a state without outgoing transitions", arguments: [false, true])
  func rejectsFalseDeadlock(nativeFailure: Bool) throws {
    let fixture = try Fixture(check: .deadlock)
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase)
    let shared = try fixture.captureGraph(stream: temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let trace = try numberedInitialStateTrace()
    let nativeResult: PropertyResult = nativeFailure
      ? .violated(try TLCTraceParser().parseCounterexample(trace)) : .satisfied
    let tlcResult = nativeFailure ? Fixture.success : TLCProcessResult(status: 11, stdout: "Deadlock reached.", stderr: "")
    #expect(throws: EvidenceFormatError.self) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: tlcResult, trace: trace)))
        .capture(try fixture.input(completeGraph: shared, swiftRun: graph, swiftResult: nativeResult))
    }
  }

  @Test("a named property failure cannot satisfy a deadlock check")
  func rejectsWrongFailureKind() throws {
    let fixture = try Fixture(check: .deadlock)
    let comparison = try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
      propertyResult: Fixture.safetyViolation, trace: numberedInitialStateTrace())))
      .capture(try fixture.input(swiftResult: .satisfied))
    #expect(comparison.status == .unavailable)
  }

  @Test("safety counterexamples retain finite paths without inventing a cycle")
  func retainsFiniteSafetyPath() throws {
    let fixture = try Fixture(check: .property("AlwaysP"))
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase)
    let first: [Any] = [1, ["x": 1]]
    let second: [Any] = [2, ["x": 2]]
    let data = try JSONSerialization.data(withJSONObject: ["vars": ["x"], "counterexample": [
      "state": [first, second], "action": [[first, ["name": "A"], second]]]])
    let nativeTrace = try TLCTraceParser().parseCounterexample(data)
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation, trace: data)))
      .capture(try fixture.input(completeGraph: completeGraph, swiftRun: graph, swiftResult: .violated(nativeTrace)))
    #expect(comparison.status == .exact)
    let retained = try #require(counterexample(in: comparison.tlcResult))
    #expect(retained.cycleStartIndex == nil)
    #expect(retained.steps == nativeTrace.steps)
  }

  @Test("generated specifications bind TLC's named implicit stuttering")
  func bindsNamedImplicitStuttering() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let comparison = try TLCPropertyCheck(
      processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: try numberedStutteringTrace(action: "A"))))
      .capture(try fixture.input(swiftRun: graph, swiftResult: .violated(testCycle([state, state]))))
    #expect(comparison.status == .exact)
    let trace = try #require(counterexample(in: comparison.tlcResult))
    #expect(trace.steps.allSatisfy { $0.action == nil })
  }

  @Test("TLC property checker rejects a lasso that is foreign to the captured graph")
  func rejectsForeignTraceEvenWhenItsLoopCloses() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.launchCase, runID: fixture.request.runID)
    let graph = try completedGraph(stream, for: fixture.launchCase, outcome: .livenessViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = PropertyResult.violated(
      testCycle(ids + [ids[0]]))
    #expect(throws: GraphRunError.self) {
      try TLCPropertyCheck(
        processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
          trace: try numberedLoopBackTrace(secondValue: 99))))
        .capture(try fixture.input(swiftRun: completedSwiftRun(graph), swiftResult: swiftResult))
    }
  }

  @Test("comparison rejects a native counterexample outside its graph")
  func rejectsForeignNativeCounterexample() throws {
    let fixture = try Fixture()
    let trace = GraphTrace(id: "foreign", steps: [
      .init(state: CanonicalState(bindings: ["x": .integer(99)]).key, action: nil)])
    #expect(throws: GraphRunError.self) {
      try PropertyComparison(caseID: "foreign", check: fixture.check,
        swiftRun: fixture.swiftRun, tlcRun: fixture.swiftRun,
        swiftResult: .violated(trace), tlcResult: .satisfied)
    }
  }

  @Test("TLC property checker retains partial output when execution throws")
  func retainsPartialOutputAfterExecutionFailure() throws {
    let fixture = try Fixture()
    try Data("stale trace".utf8).write(to: fixture.request.traceOutput, options: .atomic)
    #expect(throws: TLCProcessError.self) {
      try TLCPropertyCheck(
        processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
          executionFails: true)))
        .capture(try fixture.input())
    }
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-process.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("counterexample.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.request.traceOutput.path))
    let resultJSON = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixture.output.appendingPathComponent("tlc-process.json"))) as? [String: Any]
    let invocation = resultJSON?["invocation"] as? [String: Any]
    #expect(invocation?["executionError"] as? String != nil)
    #expect(resultJSON?["configuration"] as? String == fixture.request.bundle.cfg)
  }

  @Test("TLC property checker rejects a trace path that collides with generated evidence")
  func rejectsTraceOutputThatCollidesWithEvidence() throws {
    let fixture = try Fixture()
    let protectedOutput = fixture.output.appendingPathComponent("property-comparison.json")
    let request = fixture.makeRequest(traceOutput: protectedOutput)
    #expect(throws: TLCPropertyCheckError.graphEvidenceInvalid) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(request: request))
    }
    #expect(FileManager.default.fileExists(atPath: fixture.output.path) == false)
    #expect(FileManager.default.fileExists(atPath: protectedOutput.path) == false)
  }

  @Test("TLC property checker rejects a trace symlink that aliases the module input")
  func rejectsTraceOutputThatAliasesModuleInput() throws {
    let fixture = try Fixture()
    let traceAlias = fixture.root.appendingPathComponent("trace-alias.json")
    try FileManager.default.createSymbolicLink(at: traceAlias, withDestinationURL: fixture.module)
    let module = try Data(contentsOf: fixture.module)
    #expect(throws: TLCPropertyCheckError.graphEvidenceInvalid) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(request: fixture.makeRequest(traceOutput: traceAlias)))
    }
    #expect(try Data(contentsOf: fixture.module) == module)
    #expect(FileManager.default.fileExists(atPath: traceAlias.path))
  }

  @Test("TLC property checker requires both passes to use the same declared module closure")
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

    #expect(throws: TLCPropertyCheckError.requestMismatch) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(completeGraphRequest: completeGraphRequest))
    }
  }

  @Test("TLC property checker rejects a complete-graph trace symlink that aliases the module input")
  func rejectsCompleteGraphTraceOutputThatAliasesModuleInput() throws {
    let fixture = try Fixture()
    let traceAlias = fixture.root.appendingPathComponent("complete-trace-alias.json")
    try FileManager.default.createSymbolicLink(at: traceAlias, withDestinationURL: fixture.module)
    let module = try Data(contentsOf: fixture.module)
    let completeGraphRequest = fixture.makeCompleteGraphRequest(traceOutput: traceAlias)

    #expect(throws: EvidenceFormatError.self) {
      try TLCPropertyCheck(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()))
        .capture(try fixture.input(completeGraphRequest: completeGraphRequest))
    }
    #expect(try Data(contentsOf: fixture.module) == module)
    #expect(FileManager.default.fileExists(atPath: traceAlias.path))
  }

  private func testCycle(_ states: [String]) -> GraphTrace {
    GraphTrace(id: "test", steps: states.enumerated().map { index, state in
      let action: String? = index == 0 || state == states[index - 1] ? nil : (index == 1 ? "A" : "B")
      return GraphTraceStep(state: .init(canonicalEncoding: state), action: action)
    }, cycleStartIndex: 0)
  }

  private func counterexample(in propertyResult: PropertyResult) -> GraphTrace? {
    if case .violated(let lasso) = propertyResult { return lasso }
    return nil
  }

  private func completedSwiftRun(_ run: GraphRun) throws -> GraphRun {
    try GraphRun(
      isComplete: true,
      graph: run.graph,
      observableActions: run.observableActions,
      outcome: .noViolation
    )
  }

  private final class FixtureExecutor: TLCProcessExecuting, Sendable {
    private let stream: Data?
    private let processResult: TLCProcessResult

    init(stream: Data? = nil, processResult: TLCProcessResult = Fixture.success) {
      self.stream = stream
      self.processResult = processResult
    }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if let stream { try stream.write(to: request.graphEvents, options: .atomic) }
      return processResult
    }
  }

  private final class PropertyExecutor: TLCProcessExecuting, Sendable {
    let propertyResult: TLCProcessResult
    let trace: Data?
    let executionFails: Bool

    init(
      propertyResult: TLCProcessResult = Fixture.temporalViolation,
      trace: Data? = nil,
      executionFails: Bool = false
    ) {
      self.propertyResult = propertyResult
      self.trace = trace
      self.executionFails = executionFails
    }

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      #expect(!request.launchArguments.contains("-dump"))
      #expect(!request.launchArguments.contains { $0.hasPrefix("-Dswifttla.tlc.graph.") })
      #expect(request.launchArguments.contains("-dumpTrace"))
      guard request.invocation == .propertyCheck else {
        throw TLCProcessError.failedToStart("Unexpected graph pass during property checking")
      }
      if executionFails {
        throw TLCProcessError.timedOut(partialStdout: "partial stdout", partialStderr: "partial stderr")
      }
      if let trace { try trace.write(to: request.traceOutput, options: .atomic) }
      return propertyResult
    }
  }

  private final class Fixture {
    static let digest = String(repeating: "a", count: 64)
    static let success = TLCProcessResult(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    static let temporalViolation = TLCProcessResult(
      status: 13, stdout: "Error: Temporal property is violated.", stderr: "")
    static let safetyViolation = TLCProcessResult(
      status: 12, stdout: "Error: Invariant P is violated.", stderr: "")

    let root: URL
    let module: URL
    let configuration: URL
    let graphConfiguration: URL
    let output: URL
    let launchCase: FiniteGraphCase
    let completeGraphCase: FiniteGraphCase
    let check: ModelCheck
    let request: TLCProcessRequest
    let completeGraphRequest: TLCProcessRequest
    let swiftRun: GraphRun
    let rendered: RenderedSpecification

    init(check: ModelCheck = .property("AlwaysEventuallyP"), completeGraphStateLimit: Int = 10) throws {
      self.check = check
      root = FileManager.default.temporaryDirectory.appendingPathComponent("TLCPropertyCheckTests-\(UUID())")
      module = root.appendingPathComponent("TemporalFixture.tla")
      configuration = root.appendingPathComponent("TemporalFixture.cfg")
      graphConfiguration = root.appendingPathComponent("TemporalFixtureGraph.cfg")
      output = root.appendingPathComponent("evidence")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let x = Var<Int>("x")
      rendered = try TLASpec("TemporalFixture") {
        Variable(x, 1)
        Invariant("Positive") { x > 0 }
        Invariant("IsTwo") { x == 2 }
        Always("AlwaysP", x == 2)
        Eventually("EventuallyP", x == 2)
        AlwaysEventually("AlwaysEventuallyP", x == 2)
        EventuallyAlways("EventuallyAlwaysP", x == 2)
        LeadsTo("LeadsToPQ", x == 2, x == 1)
        LeadsTo("LeavesZero", x == 0, x != 0)
        Eventually("CustomProgress", x == 2)
      }.compile().render()
      let propertyBundle = try check.bundle(from: rendered)
      let graphBundle = try rendered.tlaBundle(checking: [], checkDeadlock: false)
      try Data(propertyBundle.tla.utf8).write(to: module)
      try Data(propertyBundle.cfg.utf8).write(to: configuration)
      try Data(graphBundle.cfg.utf8).write(to: graphConfiguration)
      launchCase = try FiniteGraphCase(
        id: "temporal",
        exploration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
        moduleSHA256: SHA256.hex(Data(contentsOf: module)),
        cfgSHA256: SHA256.hex(Data(contentsOf: configuration)), arguments: [],
        environment: [:], pin: try testReferencePin())
      completeGraphCase = try FiniteGraphCase(
        id: "temporal",
        exploration: try .init(maximumStateLimit: completeGraphStateLimit, symmetryReduction: .disabled),
        moduleSHA256: SHA256.hex(Data(contentsOf: module)),
        cfgSHA256: SHA256.hex(Data(contentsOf: graphConfiguration)), arguments: [],
        environment: [:], pin: try testReferencePin())
      request = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeClasses: root.appendingPathComponent("bridge"),
        bundle: propertyBundle,
        graphEvents: root.appendingPathComponent("events.jsonl"), traceOutput: root.appendingPathComponent("trace.json"),
        workingDirectory: root,
        finiteGraphCase: launchCase, runID: UUID(), invocation: .propertyCheck)
      completeGraphRequest = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeClasses: root.appendingPathComponent("bridge"),
        bundle: graphBundle,
        graphEvents: root.appendingPathComponent("complete-events.jsonl"),
        traceOutput: root.appendingPathComponent("complete-trace.json"),
        workingDirectory: root,
        finiteGraphCase: completeGraphCase, runID: UUID(), invocation: .finiteGraph)
      swiftRun = try completedGraph(
        graphStream(case: launchCase, runID: request.runID),
        for: launchCase)
    }

    func input(
      completeGraph: TLCProcessCapture? = nil,
      swiftRun: GraphRun? = nil,
      swiftResult: PropertyResult? = nil,
      request: TLCProcessRequest? = nil,
      completeGraphRequest: TLCProcessRequest? = nil,
      check: ModelCheck? = nil,
      outputDirectory: URL? = nil
    ) throws -> TLCPropertyCheckInput {
      let graphResult = swiftResult ?? .unavailable
      return TLCPropertyCheckInput(
        check: check ?? self.check,
        request: request ?? self.request,
        completeGraph: try completeGraph ?? captureGraph(request: completeGraphRequest),
        swiftRun: swiftRun ?? self.swiftRun,
        swiftResult: graphResult,
        rendered: rendered,
        outputDirectory: outputDirectory ?? output)
    }

    func captureGraph(
      stream: Data? = nil, request: TLCProcessRequest? = nil, result: TLCProcessResult = Fixture.success
    ) throws -> TLCProcessCapture {
      let request = request ?? completeGraphRequest
      let executor = FixtureExecutor(
        stream: try stream ?? graphStream(case: request.finiteGraphCase, runID: request.runID),
        processResult: result)
      return try TLCProcessAdapter(executor: executor).capture(request,
        retainingIn: root.appendingPathComponent("shared-\(UUID())"))
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
        invocation: request.invocation,
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
        invocation: completeGraphRequest.invocation,
        referenceArtifacts: completeGraphRequest.referenceArtifacts
      )
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
  let body = try records.reduce(into: Data()) { payload, record in
    payload.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    payload.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 2, "status": "closed",
    "counts": ["header": 1, "initial": 1], "lastBodySeq": 1, "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}

private func completedGraph(
  _ stream: Data,
  for finiteGraphCase: FiniteGraphCase,
  outcome: TLCExecutionOutcome = .completed
) throws -> GraphRun {
  let reader = TLCGraphReader(finiteGraphCase: finiteGraphCase)
  return try reader.makeGraphRun(reader.parse(stream), outcome: outcome)
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
  let body = try records.reduce(into: Data()) { payload, record in
    payload.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    payload.append(10)
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

private func numberedInitialStateTrace() throws -> Data {
  let state: [Any] = [1, ["x": 1]]
  return try JSONSerialization.data(withJSONObject: [
    "vars": ["x"],
    "counterexample": ["state": [state], "action": []]
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
