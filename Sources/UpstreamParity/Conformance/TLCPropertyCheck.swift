import Foundation
import SwiftTLA

package enum TLCPropertyCheckError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case requestMismatch
  case incompleteGraph
  case invalidNativeGraph
  case inconsistentBatchResults
}

package enum TLCPropertySource: Sendable {
  case generated
  case reference
}

package struct TLCPropertyCheck: Sendable {
  private let processAdapter: TLCProcessAdapter

  package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  package func captureAll(
    _ native: NativeModelRun, completeGraph: Result<TLCProcessCapture, Error>,
    source: TLCPropertySource, in directory: URL
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
      guard capture.request.invocation == .finiteGraph else { throw TLCPropertyCheckError.requestMismatch }
      switch source {
      case .generated:
        guard try capture.request.bundle == native.rendered.tlaBundle(checking: [], checkDeadlock: false) else {
          throw TLCPropertyCheckError.requestMismatch
        }
      case .reference:
        let request = capture.request
        try request.validateDeclaredBundle()
        guard SHA256.hex(Data(request.bundle.tla.utf8)) == request.finiteGraphCase.moduleSHA256,
              SHA256.hex(Data(request.bundle.cfg.utf8)) == request.finiteGraphCase.cfgSHA256 else {
          throw TLCPropertyCheckError.requestMismatch
        }
      }
      return (capture, compareFiniteGraphs(tlc: capture.graph, swift: native.graph))
    }
    var selected = native.checks.properties.sorted { $0.key < $1.key }.map {
      (check: ModelCheck.property($0.key), result: $0.value)
    }
    if case .generated = source, let deadlock = native.checks.deadlock { selected.append((.deadlock, deadlock)) }
    let passingChecks = selected.filter { $0.result == .satisfied }.map(\.check)
    let batch = Result {
      guard passingChecks.count > 1 else { return false }
      let (capture, _) = try prepared.get()
      let work = capture.request.workingDirectory.appendingPathComponent(UUID().uuidString)
      try RetainedFiles.createDirectory(work, beneath: capture.request.workingDirectory)
      defer { try? FileManager.default.removeItem(at: work) }
      let names = Set(passingChecks.compactMap { check -> String? in
        if case .property(let name) = check { return name }
        return nil
      })
      let bundle = switch source {
      case .generated: try native.rendered.tlaBundle(checking: names,
        checkDeadlock: passingChecks.contains(.deadlock))
      case .reference: try native.rendered.referenceBundle(checking: names, in: capture.request.bundle)
      }
      let request = try capture.request.selecting(bundle: bundle,
        work: work, runID: UUID(), invocation: .propertyCheck)
      let output = directory.appendingPathComponent("batch")
      guard !FileManager.default.fileExists(atPath: output.path) else {
        throw TLCPropertyCheckError.outputAlreadyExists
      }
      let outcome = try processAdapter.run(request, retainingIn: output)
      if outcome == .completed { return true }
      // A failed batch establishes no individual verdict. Validate its trace,
      // then isolate the checks to identify the disagreement with Swift.
      guard let property = passingChecks.first(where: { $0 != .deadlock }) else {
        throw TLCPropertyCheckError.requestMismatch
      }
      let check: ModelCheck = outcome == .deadlock ? .deadlock : property
      guard case .violated = try propertyResult(check: check, outcome: outcome,
        graph: capture.graph, outputDirectory: output) else {
        throw TLCPropertyCheckError.incompleteGraph
      }
      return false
    }
    var results: [(check: ModelCheck, result: Result<PropertyComparison, Error>)] = []
    for (check, nativeResult) in selected {
      let output = try RetainedFiles.resolve(directory.appendingPathComponent(check.artifactPath), beneath: directory)
      guard !FileManager.default.fileExists(atPath: output.path) else {
        throw TLCPropertyCheckError.outputAlreadyExists
      }
      do {
        let (capture, graphComparison) = try prepared.get()
        let tlcResult: PropertyResult
        if passingChecks.contains(check), try batch.get() {
          tlcResult = .satisfied
        } else {
          let work = capture.request.workingDirectory.appendingPathComponent(UUID().uuidString)
          try RetainedFiles.createDirectory(work, beneath: capture.request.workingDirectory)
          defer { try? FileManager.default.removeItem(at: work) }
          let bundle: TLAModuleBundle
          switch source {
          case .generated: bundle = try check.bundle(from: native.rendered)
          case .reference:
            guard case .property(let name) = check else { throw TLCPropertyCheckError.requestMismatch }
            bundle = try native.rendered.referenceBundle(checking: [name], in: capture.request.bundle)
          }
          let request = try capture.request.selecting(bundle: bundle,
            work: work, runID: UUID(), invocation: .propertyCheck)
          try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
          let outcome = try processAdapter.run(request, retainingIn: output)
          tlcResult = try propertyResult(check: check, outcome: outcome,
            graph: capture.graph, outputDirectory: output)
        }
        let status: PropertyComparisonStatus
        switch (nativeResult, tlcResult) {
        case (.unavailable, _), (_, .unavailable): status = .unavailable
        case (.satisfied, .violated), (.violated, .satisfied): status = .propertyOutcomeDifference
        case (.satisfied, .satisfied), (.violated, .violated):
          status = graphComparison.matches ? .exact : .graphDifference
        }
        let comparison = PropertyComparison(caseID: capture.request.caseID, check: check, status: status,
          swiftResult: nativeResult, tlcResult: tlcResult)
        try RetainedFiles.createDirectory(output, beneath: directory)
        try RetainedFiles.writeCanonical(comparison, to: output.appendingPathComponent("property-comparison.json"))
        results.append((check, .success(comparison)))
      } catch {
        results.append((check, .failure(error)))
        try RetainedFiles.createDirectory(output, beneath: directory)
        try RetainedFiles.writeText(redactingSecrets(in: String(describing: error)),
          to: output.appendingPathComponent("check-error.txt"))
      }
    }
    if passingChecks.count > 1, (try? batch.get()) == false {
      let reproducedFailure = results.contains { check, result in
        guard passingChecks.contains(check), let comparison = try? result.get() else { return false }
        if case .violated = comparison.tlcResult { return true }
        return false
      }
      guard reproducedFailure else { throw TLCPropertyCheckError.inconsistentBatchResults }
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
    guard requiresCycle || trace.cycleStartIndex == nil else {
      throw GraphRunError.invalidLasso
    }
    var steps = try [first] + zip(trace.steps, trace.steps.dropFirst()).map { source, target in
      guard let action = target.action else { return target }
      let edge = CanonicalEdge(source: source.state, action: action, target: target.state)
      if graph.edges.contains(edge) { return target }
      // TLC can reuse the preceding action's label for an implicit temporal
      // stutter. An unrelated or unknown action must still fail graph binding.
      guard requiresCycle, source.state == target.state, source.action == action else {
        throw GraphRunError.traceEdgeMissing(edge)
      }
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
