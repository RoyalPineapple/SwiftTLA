import Foundation

package enum TLCTemporalCaptureStatus: Equatable, Sendable {
  case captured
  case unavailable
}

package struct TLCTemporalCaptureDiagnostic: Equatable, Sendable {
  package let code: String
  package let message: String

  package init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

package struct TLCTemporalCaptureResult: Sendable {
  package let status: TLCTemporalCaptureStatus
  package let comparison: TemporalComparison?
  package let evidenceDirectory: URL
  package let diagnostic: TLCTemporalCaptureDiagnostic?

  package init(
    status: TLCTemporalCaptureStatus,
    comparison: TemporalComparison?,
    evidenceDirectory: URL,
    diagnostic: TLCTemporalCaptureDiagnostic?
  ) {
    self.status = status
    self.comparison = comparison
    self.evidenceDirectory = evidenceDirectory
    self.diagnostic = diagnostic
  }
}

package struct TLCTemporalCaptureInput: Sendable {
  package let temporalCase: TemporalSymmetryCase
  package let referencePin: TLCReferencePin
  package let correlation: TemporalSymmetryCaseRunCorrelation
  package let request: TLCProcessRequest
  package let completeGraphRequest: TLCProcessRequest?
  package let swiftRun: CompletedGraphRun
  package let swiftResult: TemporalPropertyResult
  package let swiftEvidence: RetainedFileReference
  package let allowsImplicitStuttering: Bool
  package let manifest: RetainedFileReference
  package let manifestURL: URL
  package let toolchain: RetainedFileReference
  package let toolchainURL: URL
  package let sourceInputURL: URL
  package let outputDirectory: URL
  package let relativeOutputDirectory: String

  package init(
    temporalCase: TemporalSymmetryCase,
    referencePin: TLCReferencePin,
    correlation: TemporalSymmetryCaseRunCorrelation,
    request: TLCProcessRequest,
    completeGraphRequest: TLCProcessRequest? = nil,
    swiftRun: CompletedGraphRun,
    swiftResult: TemporalPropertyResult,
    swiftEvidence: RetainedFileReference,
    allowsImplicitStuttering: Bool = false,
    manifest: RetainedFileReference,
    manifestURL: URL,
    toolchain: RetainedFileReference,
    toolchainURL: URL,
    sourceInputURL: URL,
    outputDirectory: URL,
    relativeOutputDirectory: String
  ) {
    self.temporalCase = temporalCase
    self.referencePin = referencePin
    self.correlation = correlation
    self.request = request
    self.completeGraphRequest = completeGraphRequest
    self.swiftRun = swiftRun
    self.swiftResult = swiftResult
    self.swiftEvidence = swiftEvidence
    self.allowsImplicitStuttering = allowsImplicitStuttering
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.toolchain = toolchain
    self.toolchainURL = toolchainURL
    self.sourceInputURL = sourceInputURL
    self.outputDirectory = outputDirectory
    self.relativeOutputDirectory = relativeOutputDirectory
  }
}

package enum TLCTemporalAdapterError: Error, Equatable, Sendable {
  case outputAlreadyExists
  case invalidDeclaredCase
  case correlationMismatch
  case provenanceMismatch
  case sourceInputMismatch
  case manifestMismatch
  case toolchainMismatch
  case graphEvidenceInvalid
}

package struct TLCTemporalAdapter: Sendable {
  private let processAdapter: TLCProcessAdapter

  package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  package func capture(_ input: TLCTemporalCaptureInput) -> TLCTemporalCaptureResult {
    do {
      guard !FileManager.default.fileExists(atPath: input.outputDirectory.path) else {
        throw TLCTemporalAdapterError.outputAlreadyExists
      }
      try validate(input)
      try ConformanceEvidence.outputDirectory(
        input.outputDirectory, beneath: input.outputDirectory.deletingLastPathComponent())
      try retainInput(input)
      let completeGraph = try captureCompleteGraph(input)
      try clearTraceOutput(for: input.request)

      let capture = try processAdapter.capture(
        input.request, replay: .none, retainingIn: input.outputDirectory)
      let run = capture.run
      let propertyGraph = capture.graph
      let graph = completeGraph?.graph ?? propertyGraph
      let graphID = try CanonicalGraphRecords.digest(for: graph.graph)
      let initialStateIDs = graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
      let tlcEvidence = try ConformanceEvidence.reference(
        for: input.outputDirectory.appendingPathComponent("tlc-process.json"),
        beneath: input.outputDirectory,
        pathPrefix: input.relativeOutputDirectory)
      let result = try temporalResult(
        run: run,
        graphID: graphID,
        initialStateIDs: initialStateIDs,
      graph: graph,
      outputDirectory: input.outputDirectory,
      relativeOutputDirectory: input.relativeOutputDirectory,
      allowsImplicitStuttering: input.allowsImplicitStuttering)
      let comparison = try comparison(
        input: input,
        tlcRun: graph,
        tlcResult: result,
        tlcEvidence: tlcEvidence,
        completeGraphEvidence: completeGraph?.evidence)
      try ConformanceEvidence.writeCanonical(
        comparison, to: input.outputDirectory.appendingPathComponent("temporal-comparison.json"))
      if comparison.outcome == .unavailable {
        try ConformanceEvidence.writeJSON(
          ["code": "temporal-evidence-unavailable", "message": "TLC did not retain an attributable temporal lasso."],
          to: input.outputDirectory.appendingPathComponent("diagnostic.json"))
      }
      return TLCTemporalCaptureResult(
        status: comparison.outcome == .unavailable ? .unavailable : .captured,
        comparison: comparison,
        evidenceDirectory: input.outputDirectory,
        diagnostic: comparison.outcome == .unavailable
          ? .init(code: "temporal-evidence-unavailable", message: "TLC did not retain an attributable temporal lasso.")
          : nil)
    } catch {
      let directory = retainedFailureDirectory(for: input)
      _ = try? ConformanceEvidence.createDirectory(
        directory, beneath: input.outputDirectory.deletingLastPathComponent())
      let diagnostic = TLCTemporalCaptureDiagnostic(
        code: diagnosticCode(for: error), message: String(describing: error))
      _ = try? ConformanceEvidence.writeJSON(["code": diagnostic.code, "message": diagnostic.message], to: directory.appendingPathComponent("diagnostic.json"))
      return TLCTemporalCaptureResult(
        status: .unavailable, comparison: nil, evidenceDirectory: directory, diagnostic: diagnostic)
    }
  }

  private func validate(_ input: TLCTemporalCaptureInput) throws {
    guard let sourceInput = input.temporalCase.sourceInput else {
      throw TLCTemporalAdapterError.sourceInputMismatch
    }
    try validateTraceOutput(input)
    try input.temporalCase.validate()
    try input.swiftResult.validate()
    try input.swiftEvidence.validate()
    try input.manifest.validate()
    try input.toolchain.validate()
    guard input.temporalCase.kind == .temporal,
          input.temporalCase.configuration.property != nil,
          input.correlation.caseID == input.temporalCase.id,
          input.correlation.tlcRunID == input.request.runID,
          input.request.caseID == input.temporalCase.id else {
      throw TLCTemporalAdapterError.correlationMismatch
    }
    let request = input.request.expectedCase
    guard request.pin == input.referencePin,
          input.request.referencePin == input.referencePin,
          request.moduleSHA256 == sourceInput.sha256,
          request.cfgSHA256 == SHA256.hex(Data(input.request.bundle.cfg.utf8)),
          request.argumentsSHA256 == (try FiniteGraphCase.argumentsDigest(input.request.arguments)) else {
      throw TLCTemporalAdapterError.provenanceMismatch
    }
    guard input.relativeOutputDirectory.isEmpty == false, !input.relativeOutputDirectory.hasPrefix("/") else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    guard try SHA256.hex(Data(contentsOf: input.sourceInputURL)) == sourceInput.sha256 else {
      throw TLCTemporalAdapterError.sourceInputMismatch
    }
    guard try SHA256.hex(Data(contentsOf: input.manifestURL)) == input.manifest.sha256 else {
      throw TLCTemporalAdapterError.manifestMismatch
    }
    guard try SHA256.hex(Data(contentsOf: input.toolchainURL)) == input.toolchain.sha256 else {
      throw TLCTemporalAdapterError.toolchainMismatch
    }
    if let graphRequest = input.completeGraphRequest {
      guard graphRequest.runID != input.request.runID,
            graphRequest.caseID == input.request.caseID,
            graphRequest.bundle.root.name == input.request.bundle.root.name,
            graphRequest.bundle.root.tla == input.request.bundle.root.tla,
            graphRequest.arguments == input.request.arguments,
            graphRequest.expectedCase.pin == input.request.expectedCase.pin,
            graphRequest.expectedCase.workers == input.request.expectedCase.workers,
            graphRequest.expectedCase.fingerprintPolynomial == input.request.expectedCase.fingerprintPolynomial,
            graphRequest.expectedCase.deadlock == input.request.expectedCase.deadlock,
            graphRequest.expectedCase.operatingSystem == input.request.expectedCase.operatingSystem,
            graphRequest.expectedCase.architecture == input.request.expectedCase.architecture,
            graphRequest.expectedCase.environment == input.request.expectedCase.environment,
            graphRequest.expectedCase.moduleSHA256 == sourceInput.sha256,
            let declaration = input.temporalCase.configuration.completeGraphPass,
            graphRequest.expectedCase.cfgSHA256 == declaration.configuration.sha256,
            graphRequest.expectedCase.cfgSHA256 == SHA256.hex(Data(graphRequest.bundle.cfg.utf8)),
            graphRequest.expectedCase.argumentsSHA256 == (try FiniteGraphCase.argumentsDigest(graphRequest.arguments)) else {
        throw TLCTemporalAdapterError.correlationMismatch
      }
    } else if input.temporalCase.configuration.completeGraphPass != nil {
      throw TLCTemporalAdapterError.correlationMismatch
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
    try ConformanceEvidence.copy(input.sourceInputURL, to: input.outputDirectory.appendingPathComponent("source-input"))
    try ConformanceEvidence.copy(input.manifestURL, to: input.outputDirectory.appendingPathComponent("manifest.json"))
    try ConformanceEvidence.copy(input.toolchainURL, to: input.outputDirectory.appendingPathComponent("toolchain.json"))
    try ConformanceEvidence.writeJSON([
      "caseID": input.temporalCase.id,
      "runID": input.correlation.runID.uuidString.lowercased(),
      "tlcRunID": input.correlation.tlcRunID.uuidString.lowercased(),
      "arguments": input.request.arguments,
      "module": input.request.moduleFileName,
      "configuration": input.request.configurationFileName
    ], to: input.outputDirectory.appendingPathComponent("invocation.json"))
  }

  private func captureCompleteGraph(
    _ input: TLCTemporalCaptureInput
  ) throws -> (graph: CompletedGraphRun, evidence: TemporalCompleteGraphEvidence)? {
    guard let request = input.completeGraphRequest else { return nil }
    guard let completeGraphPass = input.temporalCase.configuration.completeGraphPass,
          let sourceInput = input.temporalCase.sourceInput else {
      throw TLCTemporalAdapterError.correlationMismatch
    }
    try clearTraceOutput(for: request)
    let directory = input.outputDirectory.appendingPathComponent("complete-graph-pass", isDirectory: true)
    try ConformanceEvidence.createDirectory(directory, beneath: input.outputDirectory)
    let capture = try processAdapter.capture(request, replay: .none, retainingIn: directory)
    guard capture.run.primary.reportedExhaustiveCompletion else {
      throw TLCTemporalAdapterError.graphEvidenceInvalid
    }
    try ConformanceEvidence.writeJSON([
      "caseID": request.caseID,
      "graphRunID": request.runID.uuidString.lowercased(),
      "propertyRunID": input.request.runID.uuidString.lowercased(),
      "configurationSHA256": request.expectedCase.cfgSHA256
    ], to: directory.appendingPathComponent("invocation.json"))
    let graphURL = directory.appendingPathComponent("graph-events.jsonl")
    let processURL = directory.appendingPathComponent("tlc-process.json")
    let graph = capture.graph
    let evidence = try TemporalCompleteGraphEvidence(
      propertyRunID: input.request.runID,
      graphRunID: request.runID,
      arguments: request.arguments,
      fingerprintPolynomial: request.expectedCase.fingerprintPolynomial,
      operatingSystem: request.expectedCase.operatingSystem,
      architecture: request.expectedCase.architecture,
      environment: request.expectedCase.environment,
      sourceInput: sourceInput,
      configuration: try RetainedFileReference(
        path: completeGraphPass.configuration.path,
        sha256: SHA256.hex(Data(request.bundle.cfg.utf8))),
      graphEvents: try RetainedFileReference(
        path: "\(input.relativeOutputDirectory)/complete-graph-pass/graph-events.jsonl",
        sha256: SHA256.hex(Data(contentsOf: graphURL))),
      result: try RetainedFileReference(
        path: "\(input.relativeOutputDirectory)/complete-graph-pass/tlc-process.json",
        sha256: SHA256.hex(Data(contentsOf: processURL))))
    return (graph, evidence)
  }

}

extension TLCTemporalAdapter {
  private func temporalResult(
    run: TLCProcessRun,
    graphID: String,
    initialStateIDs: [String],
    graph: CompletedGraphRun,
    outputDirectory: URL,
    relativeOutputDirectory: String,
    allowsImplicitStuttering: Bool
  ) throws -> TemporalPropertyResult {
    if run.primary.reportedExhaustiveCompletion {
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .satisfied, graphID: graphID, initialStateIDs: initialStateIDs,
        traceAvailability: .notApplicable)
    }
    guard isTemporalViolation(run.primary),
          FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("counterexample.json").path),
          let counterexample = try? TLCTraceParser().parseCounterexample(
            Data(contentsOf: outputDirectory.appendingPathComponent("counterexample.json"))),
          traceIsBound(counterexample, to: graph, allowsImplicitStuttering: allowsImplicitStuttering),
          let lasso = lasso(from: counterexample, allowsImplicitStuttering: allowsImplicitStuttering) else {
      return try TemporalPropertyResult(
        availability: .unavailable, outcome: nil, graphID: graphID, initialStateIDs: initialStateIDs,
        traceAvailability: .unavailable)
    }
    let traceEvidence = try ConformanceEvidence.reference(
      for: outputDirectory.appendingPathComponent("counterexample.json"),
      beneath: outputDirectory,
      pathPrefix: relativeOutputDirectory)
    return try TemporalPropertyResult(
      availability: .evaluated, outcome: .violated, graphID: graphID, initialStateIDs: initialStateIDs,
      traceAvailability: .available, traceEvidence: traceEvidence, lasso: lasso)
  }

  private func comparison(
    input: TLCTemporalCaptureInput,
    tlcRun: CompletedGraphRun,
    tlcResult: TemporalPropertyResult,
    tlcEvidence: RetainedFileReference,
    completeGraphEvidence: TemporalCompleteGraphEvidence?
  ) throws -> TemporalComparison {
    let outcome: TemporalSymmetryOutcome
    let diagnostic: TemporalSymmetryDiagnosticCode
    if input.swiftResult.availability == .unavailable || tlcResult.availability == .unavailable {
      outcome = .unavailable
      diagnostic = .temporalEvidenceUnavailable
    } else if input.swiftResult.outcome == tlcResult.outcome,
              try exactGraph(tlcRun, input.swiftRun) {
      outcome = .exact
      diagnostic = .exactAgreement
    } else if input.swiftResult.outcome != tlcResult.outcome {
      outcome = .difference
      diagnostic = .propertyOutcomeDifference
    } else if try exactGraph(tlcRun, input.swiftRun) == false {
      outcome = .difference
      diagnostic = .graphIdentityDifference
    } else {
      outcome = .difference
      diagnostic = .initialStateDifference
    }
    return try TemporalComparison(
      caseID: input.temporalCase.id,
      configuration: input.temporalCase.configuration,
      correlation: input.correlation,
      outcome: outcome,
      swiftResult: input.swiftResult,
      tlcResult: tlcResult,
      swiftEvidence: input.swiftEvidence,
      tlcEvidence: tlcEvidence,
      completeGraphEvidence: completeGraphEvidence,
      diagnosticCode: diagnostic)
  }

  private func exactGraph(_ expected: CompletedGraphRun, _ actual: CompletedGraphRun) throws -> Bool {
    let expectedGraph = try CompletedGraphRun(
      graph: expected.graph,
      observableActions: expected.observableActions,
      outcome: .exhaustiveSuccess
    )
    let actualGraph = try CompletedGraphRun(
      graph: actual.graph,
      observableActions: actual.observableActions,
      outcome: .exhaustiveSuccess
    )
    return compareFiniteGraphs(expected: expectedGraph, actual: actualGraph).isConformant
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
      request.graphEvents,
      request.replayInput
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
    case TLCTemporalAdapterError.correlationMismatch: "foreign-run"
    case TLCTemporalAdapterError.provenanceMismatch: "toolchain-mismatch"
    case TLCTemporalAdapterError.sourceInputMismatch: "source-input-mismatch"
    case TLCTemporalAdapterError.manifestMismatch: "manifest-mismatch"
    case TLCTemporalAdapterError.toolchainMismatch: "toolchain-mismatch"
    default: "temporal-evidence-unavailable"
    }
  }

}
