import Foundation
import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct TLCPropertyCheckTests {
  @Test("positive reachability compares complete graphs and finite matching witnesses", arguments: [false, true])
  func comparesPositiveReachability(reached: Bool) throws {
    let x = Var<Int>("x", 1)
    let rendered = try TLASpec("TemporalFixture") {
      Variable(x)
      Reachable("Target") { x == (reached ? 1 : 2) }
    }.compile().render()
    let fixture = try Fixture(check: .property("Target"), renderedOverride: rendered)
    let witness = try TLCTraceParser().parseCounterexample(numberedInitialStateTrace(),
      states: fixture.swiftRun.graph.states.values)
    let targets: Set<CanonicalStateKey> = reached ? Set(fixture.swiftRun.graph.states.keys) : []
    let comparison = try fixture.capture(processAdapter: .init(executor: PropertyExecutor(
      propertyResult: reached ? Fixture.safetyViolation : Fixture.success,
      trace: reached ? numberedInitialStateTrace() : nil)),
      swiftResult: reached ? .reached(witness) : .unreachable, reachabilityTargets: ["Target": targets])
    #expect(comparison.status == .exact)
    #expect(comparison.tlcResult.isSatisfied == reached)
    #expect(PropertyExpectation.satisfied.accepts(comparison.tlcResult) == reached)
    #expect(PropertyExpectation.violated.accepts(comparison.tlcResult) == !reached)
  }

  @Test("a graph-valid TLC witness must end at a native matching state")
  func rejectsFalseReachabilityEndpoint() throws {
    let x = Var<Int>("x", 1)
    let rendered = try TLASpec("TemporalFixture") {
      Variable(x)
      Reachable("Target") { x == 2 }
    }.compile().render()
    let fixture = try Fixture(check: .property("Target"), renderedOverride: rendered)
    #expect(throws: EvidenceFormatError.invalidField(record: "Target", field: "reachability witness endpoint")) {
      try fixture.capture(processAdapter: .init(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation, trace: numberedInitialStateTrace())),
        swiftResult: .unreachable, reachabilityTargets: ["Target": []])
    }
  }

  @Test("reachability evidence rejects missing witnesses, cycles, and impossible traces")
  func reachabilityResultIsClosed() throws {
    let witness = GraphTrace(id: "goal", steps: [.init(state: .init(canonicalEncoding: "s"), action: nil)])
    for result in [PropertyResult.reached(witness), .unreachable] {
      #expect(try JSONDecoder().decode(PropertyResult.self, from: JSONEncoder().encode(result)) == result)
    }
    for json in [#"{"status":"reached"}"#,
      #"{"status":"unreachable","trace":{"id":"bad","steps":[{"state":"s"}]}}"#] {
      #expect(throws: EvidenceFormatError.self) {
        try JSONDecoder().decode(PropertyResult.self, from: Data(json.utf8))
      }
    }
    #expect(throws: EvidenceFormatError.self) {
      try JSONEncoder().encode(PropertyResult.reached(testCycle(["s", "s"])))
    }
  }

  @Test("passing checks share TLC graph capture and batch failures are isolated",
    arguments: [(false, false), (true, false), (false, true), (true, true)])
  func batchesPassingChecks(isTwoFails: Bool, reuseGraph: Bool) throws {
    let x = Var<Int>("x", 1)
    let rendered = try TLASpec("TemporalFixture") {
      Variable(x)
      Invariant("Positive") { x > 0 }
      Invariant("IsTwo") { x == 2 }
    }.compile().render()
    let fixture = try Fixture(renderedOverride: rendered)
    let deadlock = try TLCTraceParser().parseCounterexample(numberedInitialStateTrace(),
      states: fixture.swiftRun.graph.states.values)
    let native = try NativeModelRun(rendered: rendered, graph: fixture.swiftRun,
      checks: .init(properties: ["Positive": .satisfied, "IsTwo": .satisfied], deadlock: .violated(deadlock)))
    let checker = TLCPropertyCheck(processAdapter: .init(executor: BatchExecutor(isTwoFails: isTwoFails)))
    let graphDirectory = fixture.root.appendingPathComponent("graph")
    let capture = try reuseGraph
      ? checker.captureGraph(native, request: fixture.completeGraphRequest, source: .generated, in: graphDirectory)
      : fixture.captureGraph()
    let result = try checker.captureAll(native, completeGraph: .success(capture), source: .generated,
      in: fixture.directory)
    #expect(result.checks.map(\.check) == [.property("IsTwo"), .property("Positive"), .deadlock])
    for (check, comparison) in result.checks {
      let expected: PropertyComparisonStatus = isTwoFails && check == .property("IsTwo")
        ? .propertyOutcomeDifference : .exact
      #expect(try comparison.get().status == expected)
    }
    let files = try #require(FileManager.default.enumerator(atPath: fixture.directory.path))
      .allObjects.compactMap { $0 as? String }
    let expectedPropertyRuns = (isTwoFails ? 3 : (reuseGraph ? 0 : 1)) + 1
    #expect(files.filter { $0.hasSuffix("tlc-process.json") }.count == expectedPropertyRuns)
    let batchFile = reuseGraph && !isTwoFails
      ? graphDirectory.appendingPathComponent("checked-graph/tlc-process.json")
      : fixture.directory.appendingPathComponent("batch/tlc-process.json")
    let batch = try String(contentsOf: batchFile, encoding: .utf8)
    #expect(batch.contains("INVARIANT Positive"))
    #expect(batch.contains("INVARIANT IsTwo"))
  }

  private struct BatchExecutor: TLCProcessExecuting {
    let isTwoFails: Bool

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
      if request.invocation == .finiteGraph {
        try graphStream(case: request.finiteGraphCase, runID: request.runID).write(to: request.graphEvents)
      }
      if isTwoFails && request.bundle.cfg.contains("INVARIANT IsTwo") {
        try numberedInitialStateTrace().write(to: request.traceOutput)
        return Fixture.safetyViolation
      }
      if request.bundle.cfg.contains("CHECK_DEADLOCK TRUE") {
        try numberedInitialStateTrace().write(to: request.traceOutput)
        return .init(status: 11, stdout: "Deadlock reached.", stderr: "")
      }
      return Fixture.success
    }
  }

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

  @Test("reference checks preserve original configuration and use the declared property kind",
    arguments: [("Safe", "INVARIANT Safe"), ("Progress", "PROPERTY Progress")])
  func preservesReferenceConfiguration(name: String, directive: String) throws {
    let x = Var<Int>("x", 0)
    let rendered = try TLASpec("Generated") {
      Variable(x)
      Invariant("Safe") { x >= 0 }
      Eventually("Progress", x == 1)
    }.compile().render()
    let configuration = "CONSTANT N = 4\nSPECIFICATION LiveSpec\n"
    let reference = TLAModuleBundle.external(root: .init(name: "Original", tla: "original module bytes", cfg: configuration))
    let selected = try rendered.referenceBundle(checking: [name], checkDeadlock: false, declarations: configuration, in: reference)
    #expect(selected.root.name == "Original")
    #expect(selected.tla == reference.tla)
    #expect(selected.imports == reference.imports)
    #expect(selected.provenance == reference.provenance)
    #expect(selected.cfg.hasPrefix(configuration))
    #expect(selected.cfg.hasSuffix(directive + "\nCHECK_DEADLOCK FALSE\n"))
    #expect(selected.cfg.components(separatedBy: "CHECK_DEADLOCK").count == 2)
    #expect(!selected.cfg.contains("SPECIFICATION Spec\n"))
  }

  @Test("property counterexamples retain their cycle boundary and implicit stuttering")
  func retainsLassoAndRejectsInvalidCycles() throws {
    let first = CanonicalState(bindings: ["x": .integer(0)])
    let second = CanonicalState(bindings: ["x": .integer(1)])
    let graph = try CanonicalGraph(initialStates: [first], states: [first, second], edges: [
      .init(source: first.key, action: "advance", target: second.key)
    ])
    let steps: [GraphTraceStep] = [
      .init(state: first.key, action: nil),
      .init(state: second.key, action: "advance"),
      .init(state: second.key, action: nil)
    ]
    let lasso = GraphTrace(id: "lasso", steps: steps, cycleStartIndex: 1)
    let encoded = try JSONEncoder().encode(PropertyResult.violated(lasso))
    let decoded = try JSONDecoder().decode(PropertyResult.self, from: encoded)
    #expect(decoded == .violated(lasso))
    guard case .violated(let trace) = decoded else {
      Issue.record("Expected the retained temporal counterexample")
      return
    }
    try trace.validate(in: graph)
    #expect(trace.cycleStartIndex == 1)
    #expect(trace.steps.map(\.action) == [nil, "advance", nil])
    for start in [-1, 0, 2, 3] {
      #expect(throws: GraphRunError.self) {
        try GraphTrace(id: "invalid-cycle", steps: steps, cycleStartIndex: start).validate(in: graph)
      }
    }
  }

  @Test("property reports retain results without copying shared graphs", arguments: ["AlwaysEventuallyP", "Positive"])
  func retainsResultsWithoutGraphCopies(property: String) throws {
    let fixture = try Fixture(check: .property(property))
    let stream = try graphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase)
    let swiftResult = PropertyResult.satisfied
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.success)), swiftRun: graph, swiftResult: swiftResult)

    #expect(comparison.status == .exact)
    let process = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
      fixture.output.appendingPathComponent("tlc-process.json"))) as? [String: Any])
    #expect(process["configuration"] as? String == (try fixture.check.bundle(from: fixture.rendered).cfg))
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
    for index in 0..<2 {
      let result = try fixture.capture(processAdapter: TLCProcessAdapter(executor: executor),
        completeGraph: shared, swiftResult: .satisfied,
        outputDirectory: fixture.root.appendingPathComponent("property-\(index)"))
      #expect(result.status == .exact)
    }
    #expect(try Data(contentsOf: shared.request.graphEvents) == rawGraph)
  }

  @Test("TLC property checker rejects equal property outcomes over different graphs")
  func rejectsDifferentGraphWithEqualPropertyOutcome() throws {
    let fixture = try Fixture()
    let swiftStream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let swiftGraph = try completedGraph(swiftStream, for: fixture.completeGraphCase)
    let swiftResult = PropertyResult.satisfied

    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(
        executor: PropertyExecutor(propertyResult: Fixture.success)
      ), swiftRun: swiftGraph, swiftResult: swiftResult)

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

    #expect(throws: TLCPropertyCheckError.invalidNativeGraph) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()), swiftRun: incomplete, swiftResult: swiftResult)
    }
  }

  @Test("declared property names need no validation registry entry")
  func checksCustomProperty() throws {
    let fixture = try Fixture(check: .property("CustomProgress"))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.success)), swiftResult: .satisfied)
    #expect(comparison.check == .property("CustomProgress"))
    #expect(comparison.status == .exact)
  }

  @Test("TLC property checker does not invent a lasso from an open trace")
  func recordsUnattributableTemporalTraceAsUnavailable() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase, outcome: .livenessViolation)
    let swiftResult = PropertyResult.satisfied
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor()), completeGraph: completeGraph, swiftRun: completedSwiftRun(graph), swiftResult: swiftResult)

    #expect(comparison.status == .unavailable)
    #expect(comparison.tlcResult == .unavailable)
  }

  @Test("temporal comparison rejects an incomplete shared graph")
  func rejectsIncompleteSharedGraph() throws {
    let fixture = try Fixture()
    let shared = try fixture.captureGraph(result: Fixture.temporalViolation)
    #expect(throws: TLCPropertyCheckError.incompleteGraph) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()), completeGraph: shared)
    }
  }

  @Test("TLC property checker accepts a numbered two-state loop-back lasso")
  func capturesPinnedLoopBackLasso() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase, outcome: .livenessViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = PropertyResult.violated(
      testCycle(ids + [ids[0]]))
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: try numberedLoopBackTrace())), completeGraph: completeGraph, swiftRun: completedSwiftRun(graph), swiftResult: swiftResult)

    #expect(comparison.status == .exact)
    #expect(counterexample(in: comparison.tlcResult)?.steps.count == 3)
  }

  @Test("TLC property checker reports different property outcomes over a complete graph")
  func reportsPropertyOutcomeDifference() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase, outcome: .livenessViolation)
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: try numberedLoopBackTrace())), completeGraph: completeGraph,
        swiftRun: completedSwiftRun(graph),
        swiftResult: .satisfied)

    #expect(comparison.status == .propertyOutcomeDifference)
  }

  @Test("TLC property checker binds an actionless lasso over a completed graph")
  func bindsActionlessLasso() throws {
    let fixture = try Fixture()
    let stream = try graphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase, outcome: .livenessViolation)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = PropertyResult.violated(
      testCycle([state, state]))
    let trace = try numberedStutteringTrace()
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        trace: trace)), swiftRun: completedSwiftRun(graph), swiftResult: swiftResult)

    #expect(comparison.status == .exact)
    #expect(counterexample(in: comparison.tlcResult) != nil)
  }

  @Test("initial safety violations use the same property checker", arguments: ["AlwaysP", "IsTwo"])
  func bindsInitialSafetyViolation(property: String) throws {
    let fixture = try Fixture(check: .property(property))
    let stream = try graphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase)
    let state = try #require(graph.graph.initialStateKeys.first).canonicalEncoding
    let swiftResult = PropertyResult.violated(
      testCycle([state, state]))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation,
        trace: try numberedInitialStateTrace())), swiftRun: graph,
        swiftResult: swiftResult)

    #expect(comparison.status == .exact)
    let retained = try #require(counterexample(in: comparison.tlcResult))
    #expect(retained.cycleStartIndex == nil)
    #expect(retained.steps.map { $0.state.canonicalEncoding } == [state])
  }

  @Test("a safety violation cannot carry a repeating temporal counterexample")
  func rejectsCyclicSafetyTrace() throws {
    let fixture = try Fixture(check: .property("IsTwo"))
    #expect(throws: GraphRunError.invalidLasso) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation, trace: numberedStutteringTrace())),
        swiftResult: .satisfied)
    }
  }

  @Test("deadlock checks retain finite counterexamples independently of named properties")
  func retainsDeadlock() throws {
    let fixture = try Fixture(check: .deadlock)
    let trace = try numberedInitialStateTrace()
    let nativeTrace = try TLCTraceParser().parseCounterexample(trace, states: fixture.swiftRun.graph.states.values)
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
      propertyResult: .init(status: 11, stdout: "Deadlock reached.", stderr: ""), trace: trace)), swiftResult: .violated(nativeTrace))
    #expect(comparison.status == .exact)
    #expect(comparison.check == .deadlock)
    #expect(counterexample(in: comparison.tlcResult)?.cycleStartIndex == nil)
  }

  @Test("a deadlock counterexample must end at a state without outgoing transitions", arguments: [false, true])
  func rejectsFalseDeadlock(nativeFailure: Bool) throws {
    let fixture = try Fixture(check: .deadlock)
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase)
    let shared = try fixture.captureGraph(stream: temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let trace = try numberedInitialStateTrace()
    let nativeResult: PropertyResult = nativeFailure
      ? .violated(try TLCTraceParser().parseCounterexample(trace, states: graph.graph.states.values)) : .satisfied
    let tlcResult = nativeFailure ? Fixture.success : TLCProcessResult(status: 11, stdout: "Deadlock reached.", stderr: "")
    #expect(throws: EvidenceFormatError.self) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: tlcResult, trace: trace)), completeGraph: shared, swiftRun: graph, swiftResult: nativeResult)
    }
  }

  @Test("a named property failure cannot satisfy a deadlock check")
  func rejectsWrongFailureKind() throws {
    let fixture = try Fixture(check: .deadlock)
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
      propertyResult: Fixture.safetyViolation, trace: numberedInitialStateTrace())), swiftResult: .satisfied)
    #expect(comparison.status == .unavailable)
  }

  @Test("safety counterexamples retain finite paths without inventing a cycle")
  func retainsFiniteSafetyPath() throws {
    let fixture = try Fixture(check: .property("AlwaysP"))
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase)
    let first: [Any] = [1, ["x": 1]]
    let second: [Any] = [2, ["x": 2]]
    let data = try JSONSerialization.data(withJSONObject: ["vars": ["x"], "counterexample": [
      "state": [first, second], "action": [[first, ["name": "A"], second]]]])
    let nativeTrace = try TLCTraceParser().parseCounterexample(data, states: graph.graph.states.values)
    let completeGraph = try fixture.captureGraph(stream: try temporalGraphStream(
      case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID))
    let comparison = try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
        propertyResult: Fixture.safetyViolation, trace: data)), completeGraph: completeGraph, swiftRun: graph, swiftResult: .violated(nativeTrace))
    #expect(comparison.status == .exact)
    let retained = try #require(counterexample(in: comparison.tlcResult))
    #expect(retained.cycleStartIndex == nil)
    #expect(retained.steps == nativeTrace.steps)
  }

  @Test("only the preceding action can label an implicit temporal stutter", arguments: ["A", "B", "Missing", "UnnamedAction"])
  func bindsNamedImplicitStuttering(action: String) throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let complete = try fixture.captureGraph(stream: stream)
    let first: [Any] = [1, ["x": 1]]
    let second: [Any] = [2, ["x": 2]]
    let data = try JSONSerialization.data(withJSONObject: ["vars": ["x"], "counterexample": [
      "state": [first, second], "action": [[first, ["name": "A"], second], [second, ["name": action], second]]]])
    func capture() throws -> PropertyComparison {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(trace: data)),
        completeGraph: complete, swiftRun: complete.graph, swiftResult: .satisfied)
    }
    if action == "A" {
      let trace = try #require(counterexample(in: capture().tlcResult))
      #expect(trace.steps.map(\.action) == [nil, "A", nil])
      #expect(trace.cycleStartIndex == 1)
    } else {
      let state = CanonicalState(bindings: ["x": .integer(2)]).key
      #expect(throws: GraphRunError.traceEdgeMissing(.init(source: state, action: action, target: state))) {
        try capture()
      }
    }
  }

  @Test("TLC property checker rejects a lasso that is foreign to the captured graph")
  func rejectsForeignTraceEvenWhenItsLoopCloses() throws {
    let fixture = try Fixture()
    let stream = try temporalGraphStream(case: fixture.completeGraphCase, runID: fixture.completeGraphRequest.runID)
    let graph = try completedGraph(stream, for: fixture.completeGraphCase, outcome: .livenessViolation)
    let ids = graph.graph.states.keys.sorted().map(\.canonicalEncoding)
    let swiftResult = PropertyResult.violated(
      testCycle(ids + [ids[0]]))
    #expect(throws: TLCTraceError.invalidState(1)) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
          trace: try numberedLoopBackTrace(secondValue: 99))), swiftRun: completedSwiftRun(graph), swiftResult: swiftResult)
    }
  }

  @Test("comparison rejects a native counterexample outside its graph")
  func rejectsForeignNativeCounterexample() throws {
    let fixture = try Fixture()
    let trace = GraphTrace(id: "foreign", steps: [
      .init(state: CanonicalState(bindings: ["x": .integer(99)]).key, action: nil)])
    #expect(throws: GraphRunError.self) {
      try fixture.capture(swiftResult: .violated(trace))
    }
  }

  @Test("TLC property checker retains partial output when execution throws")
  func retainsPartialOutputAfterExecutionFailure() throws {
    let fixture = try Fixture()
    #expect(throws: TLCProcessError.self) {
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: PropertyExecutor(
          executionFails: true)))
    }
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("graph-events.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("tlc-process.json").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("counterexample.json").path))
    let resultJSON = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixture.output.appendingPathComponent("tlc-process.json"))) as? [String: Any]
    let invocation = resultJSON?["invocation"] as? [String: Any]
    #expect(invocation?["executionError"] as? String != nil)
    #expect(resultJSON?["configuration"] as? String == (try fixture.check.bundle(from: fixture.rendered).cfg))
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
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()), completeGraphRequest: completeGraphRequest)
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
      try fixture.capture(processAdapter: TLCProcessAdapter(executor: FixtureExecutor()), completeGraphRequest: completeGraphRequest)
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
    let directory: URL
    let output: URL
    let completeGraphCase: FiniteGraphCase
    let check: ModelCheck
    let completeGraphRequest: TLCProcessRequest
    let swiftRun: GraphRun
    let rendered: RenderedSpecification

    init(check: ModelCheck = .property("AlwaysEventuallyP"), renderedOverride: RenderedSpecification? = nil) throws {
      self.check = check
      root = FileManager.default.temporaryDirectory.appendingPathComponent("TLCPropertyCheckTests-\(UUID())")
      module = root.appendingPathComponent("TemporalFixture.tla")
      directory = root.appendingPathComponent("reports")
      output = directory.appendingPathComponent(check.artifactPath)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let x = Var<Int>("x")
      rendered = try renderedOverride ?? TLASpec("TemporalFixture") {
        Variable(x, 1)
        if case .property(let name) = check {
          switch name {
          case "Positive": Invariant(name) { x > 0 }
          case "IsTwo": Invariant(name) { x == 2 }
          case "AlwaysP": Always(name, x == 2)
          case "AlwaysEventuallyP": AlwaysEventually(name, x == 2)
          default: Eventually(name, x == 2)
          }
        }
      }.compile().render()
      let graphBundle = try rendered.tlaBundle(checking: [], checkDeadlock: false)
      try Data(graphBundle.tla.utf8).write(to: module)
      completeGraphCase = try FiniteGraphCase(
        id: "temporal",
        exploration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
        moduleSHA256: SHA256.hex(Data(graphBundle.tla.utf8)),
        cfgSHA256: SHA256.hex(Data(graphBundle.cfg.utf8)), arguments: [],
        environment: [:], pin: try testReferencePin())
      completeGraphRequest = TLCProcessRequest(
        javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: root.appendingPathComponent("tla2tools.jar"),
        bridgeJar: root.appendingPathComponent("bridge"),
        bundle: graphBundle,
        graphEvents: root.appendingPathComponent("complete-events.jsonl"),
        traceOutput: root.appendingPathComponent("complete-trace.json"),
        workingDirectory: root,
        finiteGraphCase: completeGraphCase, runID: UUID(), invocation: .finiteGraph)
      swiftRun = try completedGraph(
        graphStream(case: completeGraphCase, runID: completeGraphRequest.runID),
        for: completeGraphCase)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func capture(
      processAdapter: TLCProcessAdapter = TLCProcessAdapter(executor: FixtureExecutor()),
      completeGraph: TLCProcessCapture? = nil,
      swiftRun: GraphRun? = nil,
      swiftResult: PropertyResult? = nil,
      reachabilityTargets: [String: Set<CanonicalStateKey>] = [:],
      completeGraphRequest: TLCProcessRequest? = nil,
      outputDirectory: URL? = nil
    ) throws -> PropertyComparison {
      let result = swiftResult ?? .unavailable
      let checks: ModelCheckResults = switch check {
      case .property(let name): .init(properties: [name: result], deadlock: .unavailable)
      case .deadlock: .init(properties: [:], deadlock: result)
      }
      let native = try NativeModelRun(rendered: rendered, graph: swiftRun ?? self.swiftRun, checks: checks,
        reachabilityTargets: reachabilityTargets)
      let graph = try completeGraph ?? captureGraph(request: completeGraphRequest)
      let batch = try TLCPropertyCheck(processAdapter: processAdapter).captureAll(
        native, completeGraph: .success(graph), source: .generated, in: outputDirectory ?? directory)
      return try #require(batch.checks.first { $0.check == check }).result.get()
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

    func makeCompleteGraphRequest(
      bundle: TLAModuleBundle? = nil,
      traceOutput: URL? = nil
    ) -> TLCProcessRequest {
      TLCProcessRequest(
        javaExecutable: completeGraphRequest.javaExecutable,
        jar: completeGraphRequest.jar,
        bridgeJar: completeGraphRequest.bridgeJar,
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

private func numberedStutteringTrace() throws -> Data {
  let state: [Any] = [1, ["x": 1]]
  return try JSONSerialization.data(withJSONObject: [
    "vars": ["x"],
    "counterexample": [
      "state": [state],
      "action": [[state, ["name": "UnnamedAction", "location": [
        "module": "--TLA+ BUILTINS--", "beginLine": 0, "beginColumn": 0, "endLine": 0, "endColumn": 0
      ]], state]]
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
