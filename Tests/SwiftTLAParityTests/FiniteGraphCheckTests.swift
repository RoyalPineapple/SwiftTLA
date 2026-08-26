import Foundation
import os
import SwiftTLA
import Testing
import UpstreamParity
struct FiniteGraphCheckTests {
  @Test("finite graph check retains complete graphs and reports same-count edge differences")
  func retainsIndependentRunsAtomically() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let executor = FixtureTLCExecutor(
      stream: try graphStream(for: request.expectedCase, runID: request.runID))
    let check = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: executor))
    let output = root.appendingPathComponent("evidence")
    let result = check.run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .semanticDifference)
    #expect(result.comparison?.differences.contains { $0.category == .edges } == true)
    let swiftCompletion = try graphCompletion(
      at: output.appendingPathComponent("swift-graph.jsonl"))
    let tlcCompletion = try graphCompletion(
      at: output.appendingPathComponent("tlc-graph.jsonl"))
    #expect(swiftCompletion["eligible"] as? Bool == true)
    #expect(tlcCompletion["eligible"] as? Bool == true)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("comparison.json").path))
    let process = try json(at: output.appendingPathComponent("tlc-process.json"))
    let processRequest = try #require(process["request"] as? [String: Any])
    #expect((processRequest["case"] as? [String: Any])?["id"] as? String == request.expectedCase.id)
    #expect(processRequest["arguments"] as? [String] == request.expectedCase.arguments)
    #expect((processRequest["toolchain"] as? [String: Any])?["declaredPin"] != nil)
    #expect((processRequest["bundle"] as? [String: Any])?["root"] as? String == "Fixture")
    #expect(!fileManager.fileExists(atPath: output.appendingPathComponent("case.json").path))
    #expect(try json(at: output.appendingPathComponent("comparison.json"))["result"] as? String == "difference")
    let comparison = try #require(result.comparison)
    let report = try #require(comparison.failureReports.first {
      $0.whatFailed == "The labeled transition multisets differ."
    })
    #expect(report.expected.contains("TLC permits"))
    #expect(report.actual.contains("SwiftTLA permits"))
    #expect(report.nextSafeAction.contains("guard"))
  }
  @Test("finite graph check publishes partial evidence and a diagnostic after TLC capture failure")
  func retainsFailureEvidenceAtomically() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: FailingTLCExecutor()))
    let output = root.appendingPathComponent("failed-evidence")
    let result = check.run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .failure)
    #expect(result.evidenceDirectory == output)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("swift-graph.jsonl").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("diagnostic.json").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("tlc-process.json").path))
    #expect(
      fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(
      fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.stderr.log").path))
    let diagnostic = try json(at: output.appendingPathComponent("diagnostic.json"))
    let process = try json(at: output.appendingPathComponent("tlc-process.json"))
    #expect(diagnostic["code"] as? String == "tlc-execution-failed")
    #expect(diagnostic["phase"] as? String == "tlc-execution")
    let report = try #require(diagnostic["report"] as? [String: Any])
    #expect(report["whatFailed"] as? String == "TLC did not finish before the configured time limit.")
    #expect((report["expected"] as? String)?.contains("complete") == true)
    #expect((report["actual"] as? String)?.contains("terminated") == true)
    #expect((report["nextSafeAction"] as? String)?.contains("retained stdout") == true)
    #expect((report["toolOutput"] as? [[String: Any]])?.count == 2)
    #expect((process["request"] as? [String: Any])?["arguments"] as? [String] == request.arguments)
    #expect(
      (try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))).contains(
        "partial stdout"))
    #expect(
      !(try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))).contains(
        "secret"))
  }

  @Test("finite graph check isolates a stale staging directory and retains trace evidence")
  func isolatesStagingAndRetainsTraceEvidence() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let stale = root.appendingPathComponent(
      ".fixture.\(request.runID.uuidString.lowercased()).staging")
    try fileManager.createDirectory(at: stale, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: stale.appendingPathComponent("contamination.txt"))
    try Data("trace".utf8).write(to: request.traceOutput)
    let executor = FixtureTLCExecutor(
      stream: try graphStream(for: request.expectedCase, runID: request.runID),
      status: 12,
      stdout: "Invariant violation"
    )
    let output = root.appendingPathComponent("trace-evidence")
    let result = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: executor)
    ).run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.evidenceDirectory == output)
    #expect(
      !fileManager.fileExists(atPath: output.appendingPathComponent("contamination.txt").path))
    #expect(fileManager.fileExists(atPath: stale.appendingPathComponent("contamination.txt").path))
    #expect(
      fileManager.fileExists(
        atPath: output.appendingPathComponent("logs/tlc.trace.stdout.log").path))
    #expect(
      fileManager.fileExists(atPath: output.appendingPathComponent("counterexample.json").path))
  }
  @Test("finite graph check rejects a complete graph stream from another TLC run")
  func rejectsWrongTLCStreamRunBinding() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let otherRun = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000006"))
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: FixtureTLCExecutor(
          stream: try graphStream(for: request.expectedCase, runID: otherRun))))
    let output = root.appendingPathComponent("wrong-tlc-run")
    let result = check.run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .failure)
    #expect(result.evidenceDirectory == output)
    let diagnostic = try json(at: output.appendingPathComponent("diagnostic.json"))
    #expect(diagnostic["phase"] as? String == "tlc-parsing")
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("graph-events.jsonl").path))
  }
  @Test("finite graph check replaces stale raw output and retains one complete TLC graph")
  func replacesStaleRawOutputAndRetainsCompleteGraph() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    try Data("stale graph stream".utf8).write(to: request.graphEvents)
    let stream = try graphStream(for: request.expectedCase, runID: request.runID)
    let output = root.appendingPathComponent("exact-evidence")
    let result = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: FixtureTLCExecutor(stream: stream))
    ).run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration(action: "Next") },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .exact)
    #expect(try Data(contentsOf: output.appendingPathComponent("graph-events.jsonl")) == stream)
    let tlcGraph = output.appendingPathComponent("tlc-graph.jsonl")
    #expect(try graphCompletion(at: tlcGraph)["eligible"] as? Bool == true)
    let graphRecords = try graphRecords(at: tlcGraph)
    #expect(graphRecords.filter { $0["type"] as? String == "state" }.count == 2)
    #expect(graphRecords.filter { $0["type"] as? String == "edge" }.count == 1)
  }

  @Test("matching evidence retains both complete graphs and one exact comparison")
  func retainsExactComparison() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("matching-evidence")
    let result = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: FixtureTLCExecutor(stream: try graphStream(for: request.expectedCase, runID: request.runID))
    )).run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration(action: "Next") },
      tlcRequest: request,
      outputDirectory: output
    )

    #expect(result.exitCode == .exact)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("comparison.json").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("tlc-process.json").path))
    let swiftCompletion = try graphCompletion(
      at: output.appendingPathComponent("swift-graph.jsonl"))
    let tlcCompletion = try graphCompletion(
      at: output.appendingPathComponent("tlc-graph.jsonl"))
    #expect(swiftCompletion["eligible"] as? Bool == true)
    #expect(tlcCompletion["eligible"] as? Bool == true)
    #expect(try json(at: output.appendingPathComponent("comparison.json"))["result"] as? String == "exact")
  }
}

extension FiniteGraphCheckTests {
  @Test("finite graph check preserves primary logs and the trace stream after a thrown trace execution failure")
  func retainsThrownTraceExecutionEvidenceByPhase() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("trace-execution-failure")
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: ThrowingFollowupTLCExecutor(
          stream: try graphStream(for: request.expectedCase, runID: request.runID),
          failure: .trace
        )
      )
    )
    let result = check.run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .failure)
    let primaryLog = try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))
    let traceLog = try String(contentsOf: output.appendingPathComponent("logs/tlc.trace.stdout.log"))
    #expect(primaryLog.contains("primary stdout"))
    #expect(!primaryLog.contains("primary-secret"))
    #expect(traceLog.contains("trace partial stdout"))
    #expect(!traceLog.contains("trace-secret"))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("graph-events.jsonl").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("graph-events.trace.jsonl").path))
    let process = try json(at: output.appendingPathComponent("tlc-process.json"))
    #expect((process["primary"] as? [String: Any])?["status"] as? Int == 12)
    #expect((process["trace"] as? [String: Any])?["executionError"] as? String != nil)
  }
  @Test("finite graph check retains completed primary evidence after an arbitrary trace execution error")
  func retainsArbitraryTraceExecutionEvidenceByPhase() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("arbitrary-trace-execution-failure")
    let result = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: ArbitraryFollowupFailureTLCExecutor(
          stream: try graphStream(for: request.expectedCase, runID: request.runID),
          failure: .trace
        )
      )
    ).run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .failure)
    #expect((try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))).contains("primary stdout"))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.trace.failure.log").path))
    #expect(!fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.failure.log").path))
    let process = try json(at: output.appendingPathComponent("tlc-process.json"))
    #expect((process["primary"] as? [String: Any])?["status"] as? Int == 12)
    #expect((process["trace"] as? [String: Any])?["executionError"] as? String != nil)
  }
  @Test("finite graph check rejects an existing output without touching it")
  func rejectsExistingOutput() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("existing-evidence")
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: output.appendingPathComponent("existing.txt"))
    let result = FiniteGraphCheck().run(
      case: request.expectedCase,
      swiftExploration: { try swiftExploration() },
      tlcRequest: request,
      outputDirectory: output
    )
    #expect(result.exitCode == .failure)
    #expect(result.evidenceDirectory == nil)
    #expect(result.diagnostic?.code == "output-exists")
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("existing.txt").path))
  }
}

extension FiniteGraphCheckTests {
  @Test("a post-preflight publication loser preserves completed TLC evidence")
  func publicationRaceRetainsPhaseCorrectCompletedEvidence() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let stream = try graphStream(for: request.expectedCase, runID: request.runID)
    let barrier = PublicationRaceBarrier(parties: 2)
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: BarrierTLCExecutor(stream: stream, barrier: barrier)))
    let output = root.appendingPathComponent("shared-evidence")
    let results = ResultBox()
    DispatchQueue.concurrentPerform(iterations: 2) { _ in
      results.append(
        check.run(
          case: request.expectedCase,
          swiftExploration: { try exactSwiftExploration() },
          tlcRequest: request,
          outputDirectory: output
        ))
    }
    #expect(results.values.count == 2)
    #expect(results.values.filter { $0.exitCode == .semanticDifference }.count == 1)
    #expect(results.values.filter { $0.exitCode == .failure }.count == 1)
    let losingEvidence = try #require(
      results.values.first { $0.exitCode == .failure }?.evidenceDirectory)
    #expect(losingEvidence != output)
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("diagnostic.json").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("swift-graph.jsonl").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("tlc-graph.jsonl").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("tlc-process.json").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("logs/tlc.trace.stdout.log").path))
    #expect(fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("raw-artifacts.json").path))
    #expect(!fileManager.fileExists(atPath: losingEvidence.appendingPathComponent("logs/tlc.primary.failure.log").path))
    let loserDiagnostic = try json(at: losingEvidence.appendingPathComponent("diagnostic.json"))
    #expect(loserDiagnostic["phase"] as? String == "publication")
    let loserProcess = try json(at: losingEvidence.appendingPathComponent("tlc-process.json"))
    #expect((loserProcess["primary"] as? [String: Any])?["status"] as? Int == 12)
    #expect((loserProcess["trace"] as? [String: Any])?["status"] as? Int == 12)
    #expect(
      (try String(contentsOf: losingEvidence.appendingPathComponent("logs/tlc.stdout.log"))).contains(
        "primary invocation"))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("swift-graph.jsonl").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("tlc-graph.jsonl").path))
    #expect(try json(at: output.appendingPathComponent("comparison.json"))["result"] as? String == "difference")
  }
  private func swiftExploration(
    action: String = "SwiftNext",
    maximumStateLimit: Int = 10
  ) throws -> ModelExplorationResult {
    let first = StateGraph.StateID(0)
    let second = StateGraph.StateID(1)
    return ModelExplorationResult(
      graph: StateGraph(
        specName: "Fixture",
        variableNames: ["x"],
        transitions: [first: [.init(label: .init(.init(name: action)), target: second)]],
        states: [
          first: try fixtureProjection([("x", .int(1))]),
          second: try fixtureProjection([("x", .int(2))])
        ]
      ),
      initialStateIDs: [first],
      result: .ok(statesCount: 2),
      compilationIdentity: try fixtureCompilationIdentity(),
      configuration: try .init(maximumStateLimit: maximumStateLimit)
    )
  }
  private func temporaryRequest(in root: URL) throws -> TLCProcessRequest {
    let module = root.appendingPathComponent("Fixture.tla")
    let configuration = root.appendingPathComponent("Fixture.cfg")
    try Data().write(to: module)
    try Data().write(to: configuration)
    let finiteGraphCase = try FiniteGraphCase(
      id: "fixture",
      moduleSHA256: String(repeating: "c", count: 64),
      cfgSHA256: String(repeating: "d", count: 64),
      arguments: ["-workers", "1"],
      argumentsSHA256: try FiniteGraphCase.argumentsDigest(["-workers", "1"]),
      workers: 1,
      fingerprintPolynomial: 1,
      deadlock: false,
      operatingSystem: "macos",
      architecture: "arm64",
      environment: [:],
      pin: try testReferencePin()
    )
    return TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: root.appendingPathComponent("tla2tools.jar"),
      bridgeClasses: root.appendingPathComponent("bridge"),
      bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
      graphEvents: root.appendingPathComponent("events.jsonl"),
      traceOutput: root.appendingPathComponent("trace.json"),
      workingDirectory: root,
      arguments: ["-workers", "1"],
      expectedCase: finiteGraphCase,
      runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000005"))
    )
  }
}
private struct FixtureTLCExecutor: TLCProcessExecuting {
  let stream: Data
  let status: Int32
  let stdout: String
  init(
    stream: Data, status: Int32 = 0,
    stdout: String = "Model checking completed. No error has been found."
  ) {
    self.stream = stream
    self.status = status
    self.stdout = stdout
  }
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try stream.write(to: request.graphEvents)
    return TLCProcessResult(
      status: status,
      stdout: stdout,
      stderr: ""
    )
  }
}
private final class PublicationRaceBarrier: Sendable {
  private let arrivals = OSAllocatedUnfairLock(initialState: 0)
  private let release = DispatchSemaphore(value: 0)
  private let parties: Int
  init(parties: Int) {
    self.parties = parties
  }
  func waitForAll() {
    let isLast = arrivals.withLock {
      $0 += 1
      return $0 == parties
    }
    if isLast {
      for _ in 1..<parties {
        release.signal()
      }
    } else {
      release.wait()
    }
  }
}
private struct BarrierTLCExecutor: TLCProcessExecuting {
  let stream: Data
  let barrier: PublicationRaceBarrier
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try stream.write(to: request.graphEvents)
    if request.traceMode == .none {
      barrier.waitForAll()
    }
    let phase: String
    switch request.traceMode {
    case .none: phase = "primary"
    case .dumpJSON: phase = "trace"
    }
    return TLCProcessResult(
      status: 12,
      stdout: "Error: violation from \(phase) invocation",
      stderr: ""
    )
  }
}
private struct FailingTLCExecutor: TLCProcessExecuting {
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    throw TLCProcessError.timedOut(
      partialStdout: "partial stdout TOKEN=secret", partialStderr: "partial stderr")
  }
}
private enum FollowupFailure: Sendable {
  case trace
}
private final class ThrowingFollowupTLCExecutor: TLCProcessExecuting, Sendable {
  let stream: Data
  let failure: FollowupFailure
  init(stream: Data, failure: FollowupFailure) {
    self.stream = stream
    self.failure = failure
  }
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try stream.write(to: request.graphEvents)
    switch request.traceMode {
    case .none:
      return TLCProcessResult(status: 12, stdout: "Error: primary stdout TOKEN=primary-secret", stderr: "")
    case .dumpJSON where failure == .trace:
      throw TLCProcessError.timedOut(
        partialStdout: "trace partial stdout TOKEN=trace-secret", partialStderr: "trace partial stderr")
    case .dumpJSON:
      return TLCProcessResult(status: 12, stdout: "Error: trace stdout", stderr: "")
    }
  }
}
private enum ArbitraryTLCExecutorFailure: Error, Sendable {
  case launchValidation
}
private final class ArbitraryFollowupFailureTLCExecutor: TLCProcessExecuting, Sendable {
  let stream: Data
  let failure: FollowupFailure
  init(stream: Data, failure: FollowupFailure) {
    self.stream = stream
    self.failure = failure
  }
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try stream.write(to: request.graphEvents)
    switch request.traceMode {
    case .none:
      return TLCProcessResult(status: 12, stdout: "Error: primary stdout", stderr: "")
    case .dumpJSON where failure == .trace:
      throw ArbitraryTLCExecutorFailure.launchValidation
    case .dumpJSON:
      return TLCProcessResult(status: 12, stdout: "Error: trace stdout", stderr: "")
    }
  }
}
private final class ResultBox: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: [FiniteGraphCheckOutput]())
  var values: [FiniteGraphCheckOutput] {
    storage.withLock { $0 }
  }
  func append(_ value: FiniteGraphCheckOutput) {
    storage.withLock { $0.append(value) }
  }
}
private func exactSwiftExploration() throws -> ModelExplorationResult {
  let first = StateGraph.StateID(0)
  let second = StateGraph.StateID(1)
  return ModelExplorationResult(
    graph: StateGraph(
      specName: "Fixture",
      variableNames: ["x"],
      transitions: [first: [.init(label: .init(.init(name: "Next")), target: second)]],
      states: [
        first: try fixtureProjection([("x", .int(1))]),
        second: try fixtureProjection([("x", .int(2))])
      ]
      ),
      initialStateIDs: [first],
      result: .ok(statesCount: 2),
      compilationIdentity: try fixtureCompilationIdentity(),
      configuration: try .init(maximumStateLimit: 10)
  )
}
private func json(at url: URL) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func graphRecords(at url: URL) throws -> [[String: Any]] {
  try Data(contentsOf: url).split(separator: 0x0a).map {
    try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
  }
}

private func graphCompletion(at url: URL) throws -> [String: Any] {
  try #require(graphRecords(at: url).last)
}

private func fixtureProjection(_ entries: [(String, TLAValue)]) throws -> TLAStateProjection {
  try projection(entries)
}

private func fixtureCompilationIdentity() throws -> CompilationIdentity {
  let value = Var<Int>("fixture")
  return try TLASpec("Fixture") {
    Variable(value, 0)
  }.compile().identity
}
private func graphStream(for finiteGraphCase: FiniteGraphCase, runID: UUID) throws -> Data {
  let first = state(fingerprint: "1", value: "1")
  let second = state(fingerprint: "2", value: "2")
  let provenance: [String: Any] = [
    "tlcTag": finiteGraphCase.pin.tag,
    "tlcCommit": finiteGraphCase.pin.commit,
    "tlcJarSha256": finiteGraphCase.pin.jarSHA256,
    "javaDistribution": finiteGraphCase.pin.javaDistribution,
    "javaVersion": finiteGraphCase.pin.javaVersion,
    "javaArchiveSha256": finiteGraphCase.pin.javaArchiveSHA256,
    "bridgeClass": finiteGraphCase.pin.bridgeClass,
    "bridgeSourceSha256": finiteGraphCase.pin.bridgeSourceSHA256,
    "bridgeBinarySha256": finiteGraphCase.pin.bridgeBinarySHA256,
    "moduleSha256": finiteGraphCase.moduleSHA256,
    "cfgSha256": finiteGraphCase.cfgSHA256,
    "arguments": finiteGraphCase.arguments,
    "argumentsSha256": finiteGraphCase.argumentsSHA256,
    "workers": finiteGraphCase.workers,
    "fingerprintPolynomial": finiteGraphCase.fingerprintPolynomial,
    "deadlock": finiteGraphCase.deadlock,
    "os": finiteGraphCase.operatingSystem,
    "architecture": finiteGraphCase.architecture,
    "environment": finiteGraphCase.environment
  ]
  let common: [String: Any] = [
    "schema": "swifttla.tlc.graph-events",
    "version": 1,
    "runId": runID.uuidString.lowercased(),
    "caseId": finiteGraphCase.id
  ]
  let records: [[String: Any]] = [
    common.merging([
      "type": "header", "callback": "writer.header", "seq": 0, "provenance": provenance
    ]) { $1 },
    common.merging(["type": "initial", "callback": "writeState.initial", "seq": 1, "state": first]) { $1 },
    common.merging([
      "type": "transition", "callback": "writeState.action", "seq": 2,
      "source": first, "target": second,
      "action": ["name": "Next", "location": "Fixture:1", "named": true],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ]) { $1 }
  ]
  let body = try records.reduce(into: Data()) { data, record in
    data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    data.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 3, "status": "closed",
    "counts": ["header": 1, "initial": 1, "transition": 1], "lastBodySeq": 2,
    "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}
private func state(fingerprint: String, value: String) -> [String: Any] {
  [
    "fingerprint": fingerprint,
    "level": 1,
    "bindings": [
      [
        "ordinal": 0,
        "name": "x",
        "tla": value,
        "tlaSha256": SHA256.hex(Data(value.utf8))
      ]
    ]
  ]
}
