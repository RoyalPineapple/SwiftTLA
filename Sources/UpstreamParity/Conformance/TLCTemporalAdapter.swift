import Foundation

package struct TLCTemporalCaptureDiagnostic: Equatable, Sendable {
  package let code: String
  package let message: String

  package init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

package enum TLCTemporalCapture: Sendable {
  case comparison(TemporalComparison)
  case failure(TLCTemporalCaptureDiagnostic)
}

package struct TLCTemporalCaptureInput: Sendable {
  package let temporalCase: TemporalCase
  package let request: TLCProcessRequest
  package let completeGraphRequest: TLCProcessRequest
  package let swiftRun: CompletedGraphRun
  package let swiftResult: TemporalPropertyResult
  package let manifestURL: URL
  package let toolchainURL: URL
  package let sourceInputURL: URL
  package let outputDirectory: URL

  package init(
    temporalCase: TemporalCase,
    request: TLCProcessRequest,
    completeGraphRequest: TLCProcessRequest,
    swiftRun: CompletedGraphRun,
    swiftResult: TemporalPropertyResult,
    manifestURL: URL,
    toolchainURL: URL,
    sourceInputURL: URL,
    outputDirectory: URL
  ) {
    self.temporalCase = temporalCase
    self.request = request
    self.completeGraphRequest = completeGraphRequest
    self.swiftRun = swiftRun
    self.swiftResult = swiftResult
    self.manifestURL = manifestURL
    self.toolchainURL = toolchainURL
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

  package func capture(_ input: TLCTemporalCaptureInput) -> TLCTemporalCapture {
    do {
      guard !FileManager.default.fileExists(atPath: input.outputDirectory.path) else {
        throw TLCTemporalAdapterError.outputAlreadyExists
      }
      try validate(input)
      try RetainedFiles.outputDirectory(
        input.outputDirectory, beneath: input.outputDirectory.deletingLastPathComponent())
      try retainInput(input)
      try CompletedGraphRunRecords.write(
        input.swiftRun,
        to: input.outputDirectory.appendingPathComponent("swift-graph.jsonl")
      )
      let completeGraph = try captureCompleteGraph(input)
      try clearTraceOutput(for: input.request)

      let capture = try processAdapter.capture(input.request, retainingIn: input.outputDirectory)
      let run = capture.run
      try CompletedGraphRunRecords.write(
        completeGraph,
        to: input.outputDirectory.appendingPathComponent("tlc-graph.jsonl")
      )
      let result = try temporalResult(
        run: run,
        graph: completeGraph,
        outputDirectory: input.outputDirectory,
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
      let diagnostic = diagnostic(for: comparison.status)
      if let diagnostic {
        try RetainedFiles.writeJSON(
          ["code": diagnostic.code, "message": diagnostic.message],
          to: input.outputDirectory.appendingPathComponent("diagnostic.json"))
      }
      return .comparison(comparison)
    } catch {
      let directory = retainedFailureDirectory(for: input)
      _ = try? RetainedFiles.createDirectory(
        directory, beneath: input.outputDirectory.deletingLastPathComponent())
      let diagnostic = TLCTemporalCaptureDiagnostic(
        code: diagnosticCode(for: error), message: String(describing: error))
      _ = try? RetainedFiles.writeJSON(["code": diagnostic.code, "message": diagnostic.message], to: directory.appendingPathComponent("diagnostic.json"))
      return .failure(diagnostic)
    }
  }

  private func validate(_ input: TLCTemporalCaptureInput) throws {
    let sourceInput = input.temporalCase.sourceInput
    try validateTraceOutput(input)
    guard input.swiftRun.isPassEligible else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard input.request.caseID == input.temporalCase.id else {
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
    guard graphRequest.runID != input.request.runID,
          graphRequest.caseID == input.request.caseID,
          graphRequest.bundle.root.name == input.request.bundle.root.name,
          graphRequest.bundle.root.tla == input.request.bundle.root.tla,
          graphRequest.finiteGraphCase.arguments == input.request.finiteGraphCase.arguments,
          graphRequest.finiteGraphCase.pin == input.request.finiteGraphCase.pin,
          graphRequest.finiteGraphCase.environment == input.request.finiteGraphCase.environment,
          graphRequest.finiteGraphCase.moduleSHA256 == sourceInput.sha256 else {
      throw TLCTemporalAdapterError.requestMismatch
    }
  }

  private func validateTraceOutput(_ input: TLCTemporalCaptureInput) throws {
    let traceOutput = resolvedURL(input.request.traceOutput)
    let outputDirectory = resolvedURL(input.outputDirectory)
    let outputPath = outputDirectory.path.hasSuffix("/") ? outputDirectory.path : outputDirectory.path + "/"
    guard traceOutput != outputDirectory, !traceOutput.path.hasPrefix(outputPath) else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard !protectedArtifacts(for: input.request).contains(traceOutput) else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
  }

  private func retainInput(_ input: TLCTemporalCaptureInput) throws {
    try FileManager.default.copyItem(at: input.sourceInputURL, to: input.outputDirectory.appendingPathComponent("source-input"))
    try FileManager.default.copyItem(at: input.manifestURL, to: input.outputDirectory.appendingPathComponent("manifest.json"))
    try FileManager.default.copyItem(at: input.toolchainURL, to: input.outputDirectory.appendingPathComponent("toolchain.json"))
  }

  private func captureCompleteGraph(
    _ input: TLCTemporalCaptureInput
  ) throws -> CompletedGraphRun {
    let request = input.completeGraphRequest
    try clearTraceOutput(for: request)
    let directory = input.outputDirectory.appendingPathComponent("complete-graph-pass", isDirectory: true)
    try RetainedFiles.createDirectory(directory, beneath: input.outputDirectory)
    let capture = try processAdapter.capture(request, retainingIn: directory)
    guard capture.run.primary.reportedExhaustiveCompletion, capture.graph.isPassEligible else {
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
    allowsImplicitStuttering: Bool
  ) throws -> TemporalPropertyResult {
    if run.primary.reportedExhaustiveCompletion {
      return .satisfied
    }
    guard isTemporalViolation(run.primary),
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
          let loopStart = stateIDs.firstIndex(of: evidence.transitions.last?.target.key.canonicalEncoding ?? "") else {
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
    guard let first = trace.states.first,
          graph.graph.initialStateKeys.contains(first.key),
          trace.states.allSatisfy({ graph.graph.states[$0.key] == $0 }) else {
      return false
    }
    return trace.transitions.allSatisfy { transition in
      graph.graph.edgeOccurrences[transition.edge] != nil
        || (transition.source == transition.target
          && (transition.name == "UnnamedAction" || allowsImplicitStuttering))
    }
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

  private func isTemporalViolation(_ result: TLCProcessResult) -> Bool {
    let output = result.stdout + "\n" + result.stderr
    return result.isViolation && (
      output.localizedCaseInsensitiveContains("temporal")
        || output.localizedCaseInsensitiveContains("liveness")
    )
  }

  private func retainedFailureDirectory(for input: TLCTemporalCaptureInput) -> URL {
    if FileManager.default.fileExists(atPath: input.outputDirectory.path) { return input.outputDirectory }
    return input.outputDirectory.deletingLastPathComponent()
      .appendingPathComponent("\(input.outputDirectory.lastPathComponent)-unavailable")
  }

  private func diagnosticCode(for error: Error) -> String {
    switch error {
    case TLCTemporalAdapterError.outputAlreadyExists: "output-already-exists"
    case TLCTemporalAdapterError.configurationMismatch: "configuration-mismatch"
    case TLCTemporalAdapterError.requestMismatch: "request-mismatch"
    case TLCTemporalAdapterError.provenanceMismatch: "toolchain-mismatch"
    case TLCTemporalAdapterError.sourceInputMismatch: "source-input-mismatch"
    case TLCTemporalAdapterError.incompleteGraph: "incomplete-graph"
    default: "temporal-evidence-unavailable"
    }
  }

  private func diagnostic(for status: TemporalComparisonStatus) -> TLCTemporalCaptureDiagnostic? {
    switch status {
    case .unavailable:
      .init(
        code: "temporal-evidence-unavailable",
        message: "SwiftTLA or TLC could not produce a bound temporal result.")
    case .exact, .propertyOutcomeDifference, .graphDifference:
      nil
    }
  }

}
