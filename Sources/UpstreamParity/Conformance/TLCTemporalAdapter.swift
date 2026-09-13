import Foundation
import SwiftTLA

package struct TLCTemporalCaptureInput: Sendable {
  package let temporalCase: TemporalCase
  package let property: String
  package let request: TLCProcessRequest
  package let completeGraphRequest: TLCProcessRequest
  package let swiftRun: GraphRun
  package let swiftResult: TemporalPropertyResult
  package let rendered: RenderedSpecification
  package let outputDirectory: URL

  package init(
    temporalCase: TemporalCase,
    property: String,
    request: TLCProcessRequest,
    completeGraphRequest: TLCProcessRequest,
    swiftRun: GraphRun,
    swiftResult: TemporalPropertyResult,
    rendered: RenderedSpecification,
    outputDirectory: URL
  ) {
    self.temporalCase = temporalCase
    self.property = property
    self.request = request
    self.completeGraphRequest = completeGraphRequest
    self.swiftRun = swiftRun
    self.swiftResult = swiftResult
    self.rendered = rendered
    self.outputDirectory = outputDirectory
  }
}

package enum TLCTemporalAdapterError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case configurationMismatch
  case requestMismatch
  case incompleteGraph
  case graphEvidenceInvalid
}

package struct TLCTemporalAdapter: Sendable {
  private let processAdapter: TLCProcessAdapter

  package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  package func capture(_ input: TLCTemporalCaptureInput) throws -> TemporalComparison {
    guard FileManager.default.fileExists(atPath: input.outputDirectory.path) == false else {
      throw TLCTemporalAdapterError.outputAlreadyExists
    }
    try validate(input)
    try RetainedFiles.outputDirectory(
      input.outputDirectory, beneath: input.outputDirectory.deletingLastPathComponent())
    try Data(input.rendered.tlaBundle.tla.utf8).write(
      to: input.outputDirectory.appendingPathComponent("source-input"), options: .atomic)
    try GraphRunRecords.write(
      input.swiftRun,
      to: input.outputDirectory.appendingPathComponent("swift-graph.jsonl")
    )
    let capture = try processAdapter.capture(input.request, retainingIn: input.outputDirectory)
    let completeGraph = capture.graph.isComparable
      ? capture.graph
      : try captureCompleteGraph(input)
    try GraphRunRecords.write(
      completeGraph,
      to: input.outputDirectory.appendingPathComponent("tlc-graph.jsonl")
    )
    let tlcOutcome = try temporalResult(
      outcome: capture.outcome,
      graph: completeGraph,
      outputDirectory: input.outputDirectory)
    let comparison = try TemporalComparison(
      caseID: input.temporalCase.id,
      property: input.property,
      fairness: input.temporalCase.fairness,
      swiftRun: input.swiftRun,
      tlcRun: completeGraph,
      swiftResult: input.swiftResult,
      tlcResult: tlcOutcome)
    try RetainedFiles.writeCanonical(
      comparison, to: input.outputDirectory.appendingPathComponent("temporal-comparison.json"))
    return comparison
  }

  private func validate(_ input: TLCTemporalCaptureInput) throws {
    try validateTraceOutputs(input)
    guard input.swiftRun.isComparable else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard input.request.caseID == input.temporalCase.id,
          input.request.invocation == .temporalProperty else {
      throw TLCTemporalAdapterError.requestMismatch
    }
    let request = input.request.finiteGraphCase
    let expected = try input.rendered.tlaBundle(
      checking: [input.property], checkDeadlock: false)
    guard input.request.bundle == expected else {
      throw TLCTemporalAdapterError.configurationMismatch
    }
    let graphRequest = input.completeGraphRequest
    let expectedGraph = try input.rendered.tlaBundle(checking: [], checkDeadlock: false)
    guard graphRequest.bundle == expectedGraph else {
      throw TLCTemporalAdapterError.requestMismatch
    }
    guard graphRequest.invocation == .finiteGraph,
          (graphRequest.runID == input.request.runID) == false,
          graphRequest.caseID == input.request.caseID,
          graphRequest.finiteGraphCase.arguments == input.request.finiteGraphCase.arguments,
          graphRequest.finiteGraphCase.pin == input.request.finiteGraphCase.pin,
          graphRequest.finiteGraphCase.environment == input.request.finiteGraphCase.environment,
          graphRequest.finiteGraphCase.moduleSHA256 == request.moduleSHA256 else {
      throw TLCTemporalAdapterError.requestMismatch
    }
  }

  private func validateTraceOutputs(_ input: TLCTemporalCaptureInput) throws {
    let requests = [input.request, input.completeGraphRequest]
    let protected = Set(requests.flatMap(protectedArtifacts(for:)))
    let outputDirectory = resolvedURL(input.outputDirectory)
    let outputPath = outputDirectory.path.hasSuffix("/") ? outputDirectory.path : outputDirectory.path + "/"
    for request in requests {
      if FileManager.default.fileExists(atPath: request.traceOutput.path) {
        let values = try request.traceOutput.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
          throw TLCTemporalAdapterError.graphEvidenceInvalid
        }
      }
      let traceOutput = resolvedURL(request.traceOutput)
      guard (traceOutput == outputDirectory) == false,
            traceOutput.path.hasPrefix(outputPath) == false,
            protected.contains(traceOutput) == false else {
        throw TLCTemporalAdapterError.graphEvidenceInvalid
      }
    }
  }

  private func captureCompleteGraph(
    _ input: TLCTemporalCaptureInput
  ) throws -> GraphRun {
    let request = input.completeGraphRequest
    let directory = input.outputDirectory.appendingPathComponent("complete-graph-pass", isDirectory: true)
    try RetainedFiles.createDirectory(directory, beneath: input.outputDirectory)
    let capture = try processAdapter.capture(request, retainingIn: directory)
    guard capture.outcome == .completed, capture.graph.isComparable else {
      throw TLCTemporalAdapterError.incompleteGraph
    }
    return capture.graph
  }

}

extension TLCTemporalAdapter {
  private func temporalResult(
    outcome: TLCExecutionOutcome,
    graph: GraphRun,
    outputDirectory: URL
  ) throws -> TemporalPropertyResult {
    if outcome == .completed {
      return .satisfied
    }
    guard outcome == .safetyViolation || outcome == .livenessViolation,
          FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("counterexample.json").path) else {
      return .unavailable
    }
    let trace = try TLCTraceParser().parseCounterexample(
      Data(contentsOf: outputDirectory.appendingPathComponent("counterexample.json")))
    return .violated(try boundTrace(trace, to: graph.graph,
      requiresCycle: outcome == .livenessViolation))
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

  private func protectedArtifacts(for request: TLCProcessRequest) -> [URL] {
    [
      request.javaExecutable,
      request.jar,
      request.bridgeClasses,
      request.graphEvents
    ].map(resolvedURL)
  }

  private func resolvedURL(_ url: URL) -> URL {
    let candidate = url.standardizedFileURL
    var existingAncestor = candidate
    var suffix = [String]()
    while !FileManager.default.fileExists(atPath: existingAncestor.path) {
      let component = existingAncestor.lastPathComponent
      guard component.isEmpty == false, component != "/" else { break }
      suffix.insert(component, at: 0)
      existingAncestor.deleteLastPathComponent()
    }
    return suffix.reduce(existingAncestor.resolvingSymlinksInPath().standardizedFileURL) {
      $0.appendingPathComponent($1)
    }
  }

}
