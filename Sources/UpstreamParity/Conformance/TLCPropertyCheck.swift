import Foundation
import SwiftTLA

package enum TLCPropertyCheckError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case requestMismatch
  case incompleteGraph
  case invalidNativeGraph
  case uncoveredReferenceChecks([String])
  case inconsistentBatchResults
}

package enum TLCPropertySource: Sendable {
  case generated
  case reference(TLAModuleBundle, TLCReferenceConfiguration)

  func checks(for native: NativeModelRun) throws -> ModelCheckResults {
    switch self {
    case .generated:
      return native.checks
    case .reference(_, let configuration):
      try configuration.validateCoverage(native)
      let names = Set(configuration.invariants + configuration.properties)
      return ModelCheckResults(
        properties: native.checks.properties.filter { names.contains($0.key) },
        deadlock: configuration.checksDeadlock ? native.checks.deadlock : nil)
    }
  }

  func bundle(for native: NativeModelRun, checkingSatisfied: Bool) throws -> TLAModuleBundle {
    let selected = try checks(for: native)
    let names = checkingSatisfied ? Set(selected.properties.filter { $0.value == .satisfied }.keys) : []
    switch self {
    case .generated:
      return try native.rendered.tlaBundle(checking: names,
        checkDeadlock: checkingSatisfied && selected.deadlock == .satisfied)
    case .reference(let original, let configuration):
      return try configuration.bundle(from: original, native: native, checking: names,
        checkDeadlock: checkingSatisfied && selected.deadlock == .satisfied)
    }
  }
}

package struct TLCPropertyCheck: Sendable {
  private let processAdapter: TLCProcessAdapter

  package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  package func captureGraph(
    _ native: NativeModelRun, request: TLCProcessRequest, source: TLCPropertySource, in directory: URL
  ) throws -> TLCProcessCapture {
    guard native.graph.isComparable else { throw TLCPropertyCheckError.invalidNativeGraph }
    let unchecked = try source.bundle(for: native, checkingSatisfied: false)
    guard request.bundle == unchecked else { throw TLCPropertyCheckError.requestMismatch }
    let checked = try source.bundle(for: native, checkingSatisfied: true)
    if checked != unchecked {
      let batch = try request.selecting(bundle: checked, work: request.workingDirectory,
        runID: UUID(), invocation: .finiteGraph)
      let output = directory.appendingPathComponent("checked-graph")
      let capture = try processAdapter.capture(batch, retainingIn: output)
      if capture.outcome == .completed { return capture }
      let outcome: TLCExecutionOutcome = capture.outcome == .failed(exitStatus: 13)
        ? .livenessViolation : capture.outcome
      let check: ModelCheck
      if outcome == .deadlock {
        check = .deadlock
      } else {
        let selected = try source.checks(for: native)
        guard let name = selected.properties.keys.sorted().first(where: {
          selected.properties[$0] == .satisfied
        }) else { throw TLCPropertyCheckError.requestMismatch }
        check = .property(name)
      }
      guard case .violated = try propertyResult(check: check, outcome: outcome,
        graph: native.graph, outputDirectory: output) else {
        throw TLCPropertyCheckError.incompleteGraph
      }
    }
    return try processAdapter.capture(request, retainingIn: directory)
  }

  package func captureAll(
    _ native: NativeModelRun, completeGraph: Result<TLCProcessCapture, Error>,
    source: TLCPropertySource, in directory: URL
  ) throws -> (
    graphComparison: GraphComparison?,
    checks: [(check: ModelCheck, result: Result<PropertyComparison, Error>)]
  ) {
    let configured = try source.checks(for: native)
    var selected = configured.properties.sorted { $0.key < $1.key }.map {
      (check: ModelCheck.property($0.key), result: $0.value)
    }
    if let deadlock = configured.deadlock { selected.append((.deadlock, deadlock)) }
    let passingChecks = selected.filter { $0.result == .satisfied }.map(\.check)
    let prepared = Result {
      let capture = try completeGraph.get()
      guard native.graph.isComparable else { throw TLCPropertyCheckError.invalidNativeGraph }
      guard capture.outcome == .completed, capture.graph.isComparable else {
        throw TLCPropertyCheckError.incompleteGraph
      }
      guard capture.request.invocation == .finiteGraph else { throw TLCPropertyCheckError.requestMismatch }
      let unchecked = try source.bundle(for: native, checkingSatisfied: false)
      let checked = try source.bundle(for: native, checkingSatisfied: true)
      guard capture.request.bundle == unchecked || capture.request.bundle == checked else {
        throw TLCPropertyCheckError.requestMismatch
      }
      try capture.request.validateDeclaredBundle()
      guard SHA256.hex(Data(capture.request.bundle.tla.utf8)) == capture.request.finiteGraphCase.moduleSHA256,
            SHA256.hex(Data(capture.request.bundle.cfg.utf8)) == capture.request.finiteGraphCase.cfgSHA256 else {
        throw TLCPropertyCheckError.requestMismatch
      }
      return (capture, compareFiniteGraphs(tlc: capture.graph, swift: native.graph),
        checked == capture.request.bundle)
    }
    let batch = Result {
      let (capture, _, alreadyChecked) = try prepared.get()
      if alreadyChecked { return true }
      guard passingChecks.count > 1 else { return false }
      let work = capture.request.workingDirectory.appendingPathComponent(UUID().uuidString)
      try RetainedFiles.createDirectory(work, beneath: capture.request.workingDirectory)
      defer { try? FileManager.default.removeItem(at: work) }
      let bundle = try source.bundle(for: native, checkingSatisfied: true)
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
        let (capture, graphComparison, _) = try prepared.get()
        var tlcResult: PropertyResult
        if passingChecks.contains(check), try batch.get() {
          tlcResult = .satisfied
        } else {
          let work = capture.request.workingDirectory.appendingPathComponent(UUID().uuidString)
          try RetainedFiles.createDirectory(work, beneath: capture.request.workingDirectory)
          defer { try? FileManager.default.removeItem(at: work) }
          let bundle: TLAModuleBundle
          switch source {
          case .generated: bundle = try check.bundle(from: native.rendered)
          case .reference(let original, let configuration):
            let names: Set<String>
            switch check {
            case .property(let name): names = [name]
            case .deadlock: names = []
            }
            bundle = try configuration.bundle(from: original, native: native,
              checking: names, checkDeadlock: check == .deadlock)
          }
          let request = try capture.request.selecting(bundle: bundle,
            work: work, runID: UUID(), invocation: .propertyCheck)
          try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
          let outcome = try processAdapter.run(request, retainingIn: output)
          tlcResult = try propertyResult(check: check, outcome: outcome,
            graph: capture.graph, outputDirectory: output)
        }
        if case .property(let name) = check, native.rendered.reachabilityNames.contains(name) {
          switch tlcResult {
          case .satisfied: tlcResult = .unreachable
          case .violated(let trace):
            try native.validateReachabilityWitness(trace, for: name)
            tlcResult = .reached(trace)
          case .unavailable: break
          case .reached, .unreachable:
            throw EvidenceFormatError.invalidField(record: name, field: "unexpected TLC reachability outcome")
          }
        }
        let status: PropertyComparisonStatus
        switch (nativeResult, tlcResult) {
        case (.unavailable, _), (_, .unavailable): status = .unavailable
        case (.satisfied, .satisfied), (.violated, .violated), (.reached, .reached), (.unreachable, .unreachable):
          status = graphComparison.matches ? .exact : .graphDifference
        default: status = .propertyOutcomeDifference
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
