import Foundation

package struct TLCTemporalCaptureInput: Sendable {
  package let temporalCase: TemporalCase
  package let request: TLCProcessRequest
  package let completeGraphRequest: TLCProcessRequest
  package let swiftRun: CompletedGraphRun
  package let swiftResult: TemporalPropertyResult
  package let sourceInputURL: URL
  package let outputDirectory: URL

  package init(
    temporalCase: TemporalCase,
    request: TLCProcessRequest,
    completeGraphRequest: TLCProcessRequest,
    swiftRun: CompletedGraphRun,
    swiftResult: TemporalPropertyResult,
    sourceInputURL: URL,
    outputDirectory: URL
  ) {
    self.temporalCase = temporalCase
    self.request = request
    self.completeGraphRequest = completeGraphRequest
    self.swiftRun = swiftRun
    self.swiftResult = swiftResult
    self.sourceInputURL = sourceInputURL
    self.outputDirectory = outputDirectory
  }
}

package enum TLCTemporalAdapterError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case configurationMismatch
  case requestMismatch
  case provenanceMismatch
  case sourceInputMismatch
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
    try FileManager.default.copyItem(
      at: input.sourceInputURL,
      to: input.outputDirectory.appendingPathComponent("source-input"))
    try CompletedGraphRunRecords.write(
      input.swiftRun,
      to: input.outputDirectory.appendingPathComponent("swift-graph.jsonl")
    )
    try clearTraceOutput(for: input.request)
    let capture = try processAdapter.capture(input.request, retainingIn: input.outputDirectory)
    let run = capture.run
    let completeGraph = capture.graph.isPassEligible
      ? capture.graph
      : try captureCompleteGraph(input)
    try CompletedGraphRunRecords.write(
      completeGraph,
      to: input.outputDirectory.appendingPathComponent("tlc-graph.jsonl")
    )
    let result = try temporalResult(
      run: run,
      graph: completeGraph,
      outputDirectory: input.outputDirectory,
      property: input.temporalCase.configuration.property,
      allowsImplicitStuttering: input.temporalCase.configuration.allowsImplicitStuttering)
    let comparison = try TemporalComparison(
      caseID: input.temporalCase.id,
      configuration: input.temporalCase.configuration,
      swiftRun: input.swiftRun,
      tlcRun: completeGraph,
      swiftResult: input.swiftResult,
      tlcResult: result)
    try RetainedFiles.writeCanonical(
      comparison, to: input.outputDirectory.appendingPathComponent("temporal-comparison.json"))
    return comparison
  }

  private func validate(_ input: TLCTemporalCaptureInput) throws {
    let sourceInput = input.temporalCase.sourceInput
    try validateTraceOutputs(input)
    guard input.swiftRun.isPassEligible else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard input.request.caseID == input.temporalCase.id,
          input.request.invocation == .temporalProperty else {
      throw TLCTemporalAdapterError.requestMismatch
    }
    let request = input.request.finiteGraphCase
    let propertyConfiguration = input.temporalCase.configuration.renderedPropertyConfiguration
    guard input.request.bundle.cfg == propertyConfiguration,
          request.cfgSHA256 == SHA256.hex(Data(propertyConfiguration.utf8)) else {
      throw TLCTemporalAdapterError.configurationMismatch
    }
    guard request.moduleSHA256 == sourceInput.sha256 else {
      throw TLCTemporalAdapterError.provenanceMismatch
    }
    guard try SHA256.hex(Data(contentsOf: input.sourceInputURL)) == sourceInput.sha256 else {
      throw TLCTemporalAdapterError.sourceInputMismatch
    }
    let graphRequest = input.completeGraphRequest
    let graphConfiguration = TemporalCaseConfiguration.renderedGraphConfiguration
    guard graphRequest.bundle.cfg == graphConfiguration,
          graphRequest.finiteGraphCase.cfgSHA256 == SHA256.hex(Data(graphConfiguration.utf8)) else {
      throw TLCTemporalAdapterError.configurationMismatch
    }
    guard graphRequest.invocation == .finiteGraph,
          (graphRequest.runID == input.request.runID) == false,
          graphRequest.caseID == input.request.caseID,
          graphRequest.bundle.root.name == input.request.bundle.root.name,
          graphRequest.bundle.root.tla == input.request.bundle.root.tla,
          graphRequest.bundle.imports == input.request.bundle.imports,
          graphRequest.bundle.provenance == input.request.bundle.provenance,
          graphRequest.finiteGraphCase.arguments == input.request.finiteGraphCase.arguments,
          graphRequest.finiteGraphCase.pin == input.request.finiteGraphCase.pin,
          graphRequest.finiteGraphCase.environment == input.request.finiteGraphCase.environment,
          graphRequest.finiteGraphCase.moduleSHA256 == sourceInput.sha256 else {
      throw TLCTemporalAdapterError.requestMismatch
    }
  }

  private func validateTraceOutputs(_ input: TLCTemporalCaptureInput) throws {
    let requests = [input.request, input.completeGraphRequest]
    let protected = Set(
      requests.flatMap(protectedArtifacts(for:)) + [resolvedURL(input.sourceInputURL)]
    )
    let outputDirectory = resolvedURL(input.outputDirectory)
    let outputPath = outputDirectory.path.hasSuffix("/") ? outputDirectory.path : outputDirectory.path + "/"
    for request in requests {
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
  ) throws -> CompletedGraphRun {
    let request = input.completeGraphRequest
    try clearTraceOutput(for: request)
    let directory = input.outputDirectory.appendingPathComponent("complete-graph-pass", isDirectory: true)
    try RetainedFiles.createDirectory(directory, beneath: input.outputDirectory)
    let capture = try processAdapter.capture(request, retainingIn: directory)
    guard capture.run.outcome == .completed, capture.graph.isPassEligible else {
      throw TLCTemporalAdapterError.incompleteGraph
    }
    return capture.graph
  }

}

extension TLCTemporalAdapter {
  private func temporalResult(
    run: TLCProcessRun,
    graph: CompletedGraphRun,
    outputDirectory: URL,
    property: TemporalPropertyKind,
    allowsImplicitStuttering: Bool
  ) throws -> TemporalPropertyResult {
    if run.outcome == .completed {
      return .satisfied
    }
    let violationOutcome: TLCExecutionOutcome = switch property {
    case .always: .safetyViolation
    case .eventually, .alwaysEventually, .eventuallyAlways, .leadsTo: .livenessViolation
    }
    guard run.outcome == violationOutcome,
          FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("counterexample.json").path),
          let counterexample = try? TLCTraceParser().parseCounterexample(
            Data(contentsOf: outputDirectory.appendingPathComponent("counterexample.json"))),
          traceIsBound(counterexample, to: graph, allowsImplicitStuttering: allowsImplicitStuttering),
          let lasso = lasso(from: counterexample, allowsImplicitStuttering: allowsImplicitStuttering) else {
      return .unavailable
    }
    return .violated(lasso)
  }

  private func lasso(
    from evidence: TLCCounterexampleEvidence, allowsImplicitStuttering: Bool
  ) -> TemporalLassoWitness? {
    let stateIDs = evidence.states.map { $0.key.canonicalEncoding }
    if evidence.transitions.isEmpty, allowsImplicitStuttering, let state = stateIDs.first {
      return try? TemporalLassoWitness(prefixStateIDs: [], cycleStateIDs: [state, state])
    }
    guard evidence.transitions.count == stateIDs.count,
          let finalTarget = evidence.transitions.last?.target.key.canonicalEncoding,
          let loopStart = stateIDs.firstIndex(of: finalTarget) else {
      return nil
    }
    return try? TemporalLassoWitness(
      prefixStateIDs: Array(stateIDs[..<loopStart]),
      cycleStateIDs: Array(stateIDs[loopStart...]) + [stateIDs[loopStart]])
  }

  private func traceIsBound(
    _ trace: TLCCounterexampleEvidence,
    to graph: CompletedGraphRun,
    allowsImplicitStuttering: Bool
  ) -> Bool {
    var states = trace.states
    var edges = trace.transitions.map(\.edge)
    if edges.isEmpty, allowsImplicitStuttering, let state = states.first {
      states.append(state)
      edges.append(CanonicalEdge(source: state.key, action: "UnnamedAction", target: state.key))
    } else if let target = edges.last?.target,
              let finalState = graph.graph.states[target] {
      states.append(finalState)
    }
    return graph.containsTemporalTrace(
      states: states,
      edges: edges,
      implicitStutterActions: ["UnnamedAction"],
      allowsImplicitStuttering: allowsImplicitStuttering
    )
  }

  private func clearTraceOutput(for request: TLCProcessRequest) throws {
    let originalTraceOutput = request.traceOutput.standardizedFileURL
    let traceOutput = resolvedURL(originalTraceOutput)
    let workingDirectory = resolvedURL(request.workingDirectory)
    let workingPath = workingDirectory.path.hasSuffix("/") ? workingDirectory.path : workingDirectory.path + "/"
    guard traceOutput.path.hasPrefix(workingPath),
          !protectedArtifacts(for: request).contains(traceOutput) else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard FileManager.default.fileExists(atPath: originalTraceOutput.path) else { return }
    let values = try originalTraceOutput.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    try FileManager.default.removeItem(at: traceOutput)
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
