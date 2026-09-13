import Foundation
import SwiftTLA

package enum TLCPropertyCheckError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case requestMismatch
  case incompleteGraph
  case invalidNativeGraph
}

package struct TLCPropertyCheck: Sendable {
  private let processAdapter: TLCProcessAdapter

  package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  package func captureAll(
    _ native: NativeModelRun, completeGraph: Result<TLCProcessCapture, Error>, in directory: URL
  ) throws -> (
    graphComparison: GraphComparison?,
    checks: [(check: ModelCheck, result: Result<PropertyComparison, Error>)]
  ) {
    let prepared = Result {
      let capture = try completeGraph.get()
      guard native.graph.isComparable else { throw TLCPropertyCheckError.invalidNativeGraph }
      guard capture.outcome == .completed, capture.graph.isComparable else {
        throw TLCPropertyCheckError.incompleteGraph
      }
      let expected = try native.rendered.tlaBundle(checking: [], checkDeadlock: false)
      guard capture.request.invocation == .finiteGraph, capture.request.bundle == expected else {
        throw TLCPropertyCheckError.requestMismatch
      }
      return (capture, compareFiniteGraphs(tlc: capture.graph, swift: native.graph))
    }
    var selected = native.checks.properties.sorted { $0.key < $1.key }.map {
      (check: ModelCheck.property($0.key), result: $0.value)
    }
    if let deadlock = native.checks.deadlock { selected.append((.deadlock, deadlock)) }
    var results: [(check: ModelCheck, result: Result<PropertyComparison, Error>)] = []
    for (check, nativeResult) in selected {
      let output = try RetainedFiles.resolve(directory.appendingPathComponent(check.artifactPath), beneath: directory)
      guard !FileManager.default.fileExists(atPath: output.path) else {
        throw TLCPropertyCheckError.outputAlreadyExists
      }
      do {
        let (capture, graphComparison) = try prepared.get()
        let work = capture.request.workingDirectory.appendingPathComponent(UUID().uuidString)
        try RetainedFiles.createDirectory(work, beneath: capture.request.workingDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let request = try capture.request.selecting(bundle: check.bundle(from: native.rendered),
          work: work, runID: UUID(), invocation: .propertyCheck)
        try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
        let outcome = try processAdapter.run(request, retainingIn: output)
        let tlcResult = try propertyResult(check: check, outcome: outcome,
          graph: capture.graph, outputDirectory: output)
        let status: PropertyComparisonStatus
        switch (nativeResult, tlcResult) {
        case (.unavailable, _), (_, .unavailable): status = .unavailable
        case (.satisfied, .violated), (.violated, .satisfied): status = .propertyOutcomeDifference
        case (.satisfied, .satisfied), (.violated, .violated):
          status = graphComparison.matches ? .exact : .graphDifference
        }
        let comparison = PropertyComparison(caseID: request.caseID, check: check, status: status,
          swiftResult: nativeResult, tlcResult: tlcResult)
        try RetainedFiles.writeCanonical(comparison, to: output.appendingPathComponent("property-comparison.json"))
        results.append((check, .success(comparison)))
      } catch {
        results.append((check, .failure(error)))
        try RetainedFiles.createDirectory(output, beneath: directory)
        try RetainedFiles.writeText(redactingSecrets(in: String(describing: error)),
          to: output.appendingPathComponent("check-error.txt"))
      }
    }
    return (try? prepared.get().1, results)
  }
}

extension TLCPropertyCheck {
  private func propertyResult(
    check: ModelCheck, outcome: TLCExecutionOutcome,
    graph: GraphRun,
    outputDirectory: URL
  ) throws -> PropertyResult {
    if outcome == .completed {
      return .satisfied
    }
    let expectedViolation = switch check {
    case .property: outcome == .safetyViolation || outcome == .livenessViolation
    case .deadlock: outcome == .deadlock
    }
    guard expectedViolation,
          FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("counterexample.json").path) else {
      return .unavailable
    }
    let trace = try TLCTraceParser().parseCounterexample(
      Data(contentsOf: outputDirectory.appendingPathComponent("counterexample.json")), states: graph.graph.states.values)
    let bound = try boundTrace(trace, to: graph.graph, requiresCycle: outcome == .livenessViolation)
    if check == .deadlock {
      guard bound.cycleStartIndex == nil, let final = bound.steps.last,
            !graph.graph.edges.contains(where: { $0.source == final.state }) else {
        throw EvidenceFormatError.invalidField(record: "deadlock", field: "deadlock counterexample")
      }
    }
    return .violated(bound)
  }

  private func boundTrace(
    _ trace: GraphTrace, to graph: CanonicalGraph,
    requiresCycle: Bool
  ) throws -> GraphTrace {
    guard let first = trace.steps.first else { throw GraphRunError.emptyTrace }
    var steps = try [first] + zip(trace.steps, trace.steps.dropFirst()).map { source, target in
      guard let action = target.action else { return target }
      let edge = CanonicalEdge(source: source.state, action: action, target: target.state)
      if graph.edges.contains(edge) { return target }
      guard source.state == target.state else {
        throw GraphRunError.traceEdgeMissing(edge)
      }
      // Generated specifications include [Next]_vars. TLC can label implicit
      // stuttering with the preceding action, even when that action is disabled.
      return GraphTraceStep(state: target.state, action: nil)
    }
    var cycleStart = trace.cycleStartIndex
    if requiresCycle, cycleStart == nil {
      guard steps.count == 1 else { throw GraphRunError.invalidLasso }
      steps.append(GraphTraceStep(state: first.state, action: nil))
      cycleStart = 0
    }
    let bound = GraphTrace(id: trace.id, steps: steps, cycleStartIndex: cycleStart)
    try bound.validate(in: graph)
    return bound
  }

}
