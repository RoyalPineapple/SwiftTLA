import Foundation

public enum TLCTemporalCaptureStatusV1: Equatable, Sendable {
  case captured
  case unavailable
}

public struct TLCTemporalCaptureDiagnosticV1: Equatable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct TLCTemporalCaptureResultV1: Sendable {
  public let status: TLCTemporalCaptureStatusV1
  public let comparison: TemporalComparisonV1?
  public let evidenceDirectory: URL
  public let diagnostic: TLCTemporalCaptureDiagnosticV1?

  public init(
    status: TLCTemporalCaptureStatusV1,
    comparison: TemporalComparisonV1?,
    evidenceDirectory: URL,
    diagnostic: TLCTemporalCaptureDiagnosticV1?
  ) {
    self.status = status
    self.comparison = comparison
    self.evidenceDirectory = evidenceDirectory
    self.diagnostic = diagnostic
  }
}

public struct TLCTemporalCaptureInputV1: Sendable {
  public let declaredCase: TemporalSymmetryCaseV1
  public let correlation: TemporalSymmetryCaseRunCorrelationV1
  public let request: TLCProcessRequestV1
  public let completeGraphRequest: TLCProcessRequestV1?
  public let swiftResult: TemporalPropertyResultV1
  public let swiftEvidence: CoreEvidenceReferenceV1
  public let enablednessEvidence: CoreEvidenceReferenceV1
  public let fairComponents: [TemporalRecurrentComponentV1]
  public let rejectedComponents: [TemporalRecurrentComponentV1]
  public let allowsImplicitStuttering: Bool
  public let manifest: CoreEvidenceReferenceV1
  public let manifestURL: URL
  public let toolchain: CoreEvidenceReferenceV1
  public let toolchainURL: URL
  public let sourceInputURL: URL
  public let outputDirectory: URL
  public let relativeOutputDirectory: String

  public init(
    declaredCase: TemporalSymmetryCaseV1,
    correlation: TemporalSymmetryCaseRunCorrelationV1,
    request: TLCProcessRequestV1,
    completeGraphRequest: TLCProcessRequestV1? = nil,
    swiftResult: TemporalPropertyResultV1,
    swiftEvidence: CoreEvidenceReferenceV1,
    enablednessEvidence: CoreEvidenceReferenceV1,
    fairComponents: [TemporalRecurrentComponentV1],
    rejectedComponents: [TemporalRecurrentComponentV1],
    allowsImplicitStuttering: Bool = false,
    manifest: CoreEvidenceReferenceV1,
    manifestURL: URL,
    toolchain: CoreEvidenceReferenceV1,
    toolchainURL: URL,
    sourceInputURL: URL,
    outputDirectory: URL,
    relativeOutputDirectory: String
  ) {
    self.declaredCase = declaredCase
    self.correlation = correlation
    self.request = request
    self.completeGraphRequest = completeGraphRequest
    self.swiftResult = swiftResult
    self.swiftEvidence = swiftEvidence
    self.enablednessEvidence = enablednessEvidence
    self.fairComponents = fairComponents
    self.rejectedComponents = rejectedComponents
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

public enum TLCTemporalAdapterErrorV1: Error, Equatable, Sendable {
  case outputAlreadyExists
  case invalidDeclaredCase
  case correlationMismatch
  case provenanceMismatch
  case sourceInputMismatch
  case manifestMismatch
  case toolchainMismatch
  case graphEvidenceInvalid
}

public struct TLCTemporalAdapterV1: Sendable {
  private let processAdapter: TLCProcessAdapterV1

  public init(processAdapter: TLCProcessAdapterV1 = TLCProcessAdapterV1()) {
    self.processAdapter = processAdapter
  }

  public func capture(_ input: TLCTemporalCaptureInputV1) -> TLCTemporalCaptureResultV1 {
    do {
      guard !FileManager.default.fileExists(atPath: input.outputDirectory.path) else {
        throw TLCTemporalAdapterErrorV1.outputAlreadyExists
      }
      try validate(input)
      try FileManager.default.createDirectory(at: input.outputDirectory, withIntermediateDirectories: true)
      try retainInput(input)
      let completeGraph = try captureCompleteGraph(input)
      try clearTraceOutput(for: input.request)

      let run: TLCProcessRunV1
      do {
        run = try processAdapter.run(input.request, replay: .none)
      } catch {
        if let completed = completedRun(from: error) {
          try? retain(run: completed, input: input)
          try? retainPrimaryResult(completed.primary, input: input)
          _ = try? retainGraphEvents(from: input.request, to: input.outputDirectory)
        }
        throw error
      }
      try retain(run: run, input: input)
      try retainPrimaryResult(run.primary, input: input)
      let graphData = try retainGraphEvents(from: input.request, to: input.outputDirectory)
      let propertyGraph = try TLCGraphEventParserV1(expectedCase: input.request.expectedCase)
        .parseCanonicalRun(graphData, result: run.primary)
      let graph = completeGraph?.graph ?? propertyGraph
      let graphID = Self.graphID(graph)
      let initialStateIDs = graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
      let tlcEvidence = try reference(
        input.outputDirectory.appendingPathComponent("tlc-result.json"), relativeTo: input.relativeOutputDirectory)
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
        tlcResult: result,
        tlcEvidence: tlcEvidence,
        completeGraphEvidence: completeGraph?.evidence)
      let comparisonData = try JSONEncoder().encode(comparison)
      try comparisonData.write(
        to: input.outputDirectory.appendingPathComponent("temporal-comparison.json"), options: .atomic)
      if comparison.outcome == .unavailable {
        try writeJSON(
          ["code": "temporal-evidence-unavailable", "message": "TLC did not retain an attributable temporal lasso."],
          to: input.outputDirectory.appendingPathComponent("diagnostic.json"))
      }
      return TLCTemporalCaptureResultV1(
        status: comparison.outcome == .unavailable ? .unavailable : .captured,
        comparison: comparison,
        evidenceDirectory: input.outputDirectory,
        diagnostic: comparison.outcome == .unavailable
          ? .init(code: "temporal-evidence-unavailable", message: "TLC did not retain an attributable temporal lasso.")
          : nil)
    } catch {
      let directory = retainedFailureDirectory(for: input)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let diagnostic = TLCTemporalCaptureDiagnosticV1(
        code: diagnosticCode(for: error), message: String(describing: error))
      try? writeJSON(["code": diagnostic.code, "message": diagnostic.message], to: directory.appendingPathComponent("diagnostic.json"))
      return TLCTemporalCaptureResultV1(
        status: .unavailable, comparison: nil, evidenceDirectory: directory, diagnostic: diagnostic)
    }
  }

  public static func graphID(_ graph: CanonicalRunV1) -> String {
    let projection: [String: Any] = [
      "initialStates": graph.graph.initialStateKeys.sorted().map(\.canonicalEncoding),
      "states": graph.graph.states.keys.sorted().map(\.canonicalEncoding),
      "edges": graph.graph.edgeOccurrences.keys.sorted().map { edge in
        ["edge": edge.canonicalEncoding, "count": graph.graph.edgeOccurrences[edge] ?? 0]
      }
    ]
    let data = try! JSONSerialization.data(withJSONObject: projection, options: [.sortedKeys])
    return SHA256V1.hex(data)
  }

  private func validate(_ input: TLCTemporalCaptureInputV1) throws {
    try validateTraceOutput(input)
    try input.declaredCase.validate()
    try input.swiftResult.validate()
    try input.swiftEvidence.validate()
    try input.enablednessEvidence.validate()
    try input.manifest.validate()
    try input.toolchain.validate()
    guard input.declaredCase.kind == .temporal,
          input.declaredCase.configuration.property != nil,
          input.correlation.caseID == input.declaredCase.id,
          input.correlation.tlcRunID == input.request.runID,
          input.request.caseID == input.declaredCase.id else {
      throw TLCTemporalAdapterErrorV1.correlationMismatch
    }
    let declared = input.declaredCase.provenance
    let request = input.request.expectedCase
    guard request.moduleSHA256 == declared.moduleSHA256,
          request.cfgSHA256 == declared.cfgSHA256,
          request.argumentsSHA256 == declared.argumentsSHA256,
          request.pin.tag == declared.tlcTag,
          request.pin.commit == declared.tlcCommit,
          request.pin.jarSHA256 == declared.tlcJarSHA256,
          request.pin.javaArchiveSHA256 == declared.javaArchiveSHA256,
          request.pin.bridgeSourceSHA256 == declared.bridgeSourceSHA256,
          request.pin.bridgeBinarySHA256 == declared.bridgeBinarySHA256 else {
      throw TLCTemporalAdapterErrorV1.provenanceMismatch
    }
    guard input.relativeOutputDirectory.isEmpty == false, !input.relativeOutputDirectory.hasPrefix("/") else {
      throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid
    }
    guard try SHA256V1.hex(Data(contentsOf: input.sourceInputURL)) == input.declaredCase.sourceInput.sha256 else {
      throw TLCTemporalAdapterErrorV1.sourceInputMismatch
    }
    guard try SHA256V1.hex(Data(contentsOf: input.manifestURL)) == input.manifest.sha256 else {
      throw TLCTemporalAdapterErrorV1.manifestMismatch
    }
    guard try SHA256V1.hex(Data(contentsOf: input.toolchainURL)) == input.toolchain.sha256 else {
      throw TLCTemporalAdapterErrorV1.toolchainMismatch
    }
    if let graphRequest = input.completeGraphRequest {
      guard graphRequest.runID != input.request.runID,
            graphRequest.caseID == input.request.caseID,
            graphRequest.module == input.request.module,
            graphRequest.arguments == input.request.arguments,
            graphRequest.expectedCase.pin == input.request.expectedCase.pin,
            graphRequest.expectedCase.workers == input.request.expectedCase.workers,
            graphRequest.expectedCase.fingerprintPolynomial == input.request.expectedCase.fingerprintPolynomial,
            graphRequest.expectedCase.deadlock == input.request.expectedCase.deadlock,
            graphRequest.expectedCase.operatingSystem == input.request.expectedCase.operatingSystem,
            graphRequest.expectedCase.architecture == input.request.expectedCase.architecture,
            graphRequest.expectedCase.environment == input.request.expectedCase.environment,
            graphRequest.expectedCase.moduleSHA256 == input.declaredCase.sourceInput.sha256,
            let declaration = input.declaredCase.configuration.completeGraphPass,
            graphRequest.expectedCase.cfgSHA256 == declaration.configuration.sha256 else {
        throw TLCTemporalAdapterErrorV1.correlationMismatch
      }
    } else if input.declaredCase.configuration.completeGraphPass != nil {
      throw TLCTemporalAdapterErrorV1.correlationMismatch
    }
  }

  private func validateTraceOutput(_ input: TLCTemporalCaptureInputV1) throws {
    let traceOutput = resolvedURL(input.request.traceOutput)
    let outputDirectory = resolvedURL(input.outputDirectory)
    let outputPath = outputDirectory.path.hasSuffix("/") ? outputDirectory.path : outputDirectory.path + "/"
    guard traceOutput != outputDirectory, !traceOutput.path.hasPrefix(outputPath) else {
      throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid
    }
    guard !protectedArtifacts(for: input.request).contains(traceOutput) else {
      throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid
    }
  }

  private func retainInput(_ input: TLCTemporalCaptureInputV1) throws {
    try copy(input.sourceInputURL, as: "source-input", to: input.outputDirectory)
    try copy(input.manifestURL, as: "manifest.json", to: input.outputDirectory)
    try copy(input.toolchainURL, as: "toolchain.json", to: input.outputDirectory)
    try writeJSON([
      "caseID": input.declaredCase.id,
      "gateRunID": input.correlation.gateRunID.uuidString.lowercased(),
      "tlcRunID": input.correlation.tlcRunID.uuidString.lowercased(),
      "arguments": input.request.arguments,
      "module": input.request.module.lastPathComponent,
      "configuration": input.request.configuration.lastPathComponent
    ], to: input.outputDirectory.appendingPathComponent("invocation.json"))
  }

  private func captureCompleteGraph(
    _ input: TLCTemporalCaptureInputV1
  ) throws -> (graph: CanonicalRunV1, evidence: TemporalCompleteGraphEvidenceV1)? {
    guard let request = input.completeGraphRequest else { return nil }
    try clearTraceOutput(for: request)
    let run = try processAdapter.run(request, replay: .none)
    guard run.primary.reportedExhaustiveCompletion else { throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid }
    let directory = input.outputDirectory.appendingPathComponent("complete-graph-pass", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeText(run.primary.stdout, to: directory.appendingPathComponent("tlc.stdout.log"))
    try writeText(run.primary.stderr, to: directory.appendingPathComponent("tlc.stderr.log"))
    try writeJSON(processJSON(run.primary), to: directory.appendingPathComponent("tlc-result.json"))
    try writeJSON([
      "caseID": request.caseID,
      "graphRunID": request.runID.uuidString.lowercased(),
      "propertyRunID": input.request.runID.uuidString.lowercased(),
      "configurationSHA256": request.expectedCase.cfgSHA256
    ], to: directory.appendingPathComponent("invocation.json"))
    let data = try Data(contentsOf: request.graphEvents)
    let graphURL = directory.appendingPathComponent("graph-events.jsonl")
    let resultURL = directory.appendingPathComponent("tlc-result.json")
    try data.write(to: graphURL, options: .atomic)
    let graph = try TLCGraphEventParserV1(expectedCase: request.expectedCase).parseCanonicalRun(data, result: run.primary)
    let evidence = try TemporalCompleteGraphEvidenceV1(
      propertyRunID: input.request.runID,
      graphRunID: request.runID,
      arguments: request.arguments,
      fingerprintPolynomial: request.expectedCase.fingerprintPolynomial,
      operatingSystem: request.expectedCase.operatingSystem,
      architecture: request.expectedCase.architecture,
      environment: request.expectedCase.environment,
      sourceInput: input.declaredCase.sourceInput,
      configuration: try CoreEvidenceReferenceV1(
        path: input.declaredCase.configuration.completeGraphPass!.configuration.path,
        sha256: SHA256V1.hex(Data(contentsOf: request.configuration))),
      graphEvents: try CoreEvidenceReferenceV1(
        path: "\(input.relativeOutputDirectory)/complete-graph-pass/graph-events.jsonl",
        sha256: SHA256V1.hex(Data(contentsOf: graphURL))),
      result: try CoreEvidenceReferenceV1(
        path: "\(input.relativeOutputDirectory)/complete-graph-pass/tlc-result.json",
        sha256: SHA256V1.hex(Data(contentsOf: resultURL))))
    return (graph, evidence)
  }

  private func retain(run: TLCProcessRunV1, input: TLCTemporalCaptureInputV1) throws {
    try writeText(run.primary.stdout, to: input.outputDirectory.appendingPathComponent("tlc.primary.stdout.log"))
    try writeText(run.primary.stderr, to: input.outputDirectory.appendingPathComponent("tlc.primary.stderr.log"))
    if let trace = run.trace {
      try writeText(trace.stdout, to: input.outputDirectory.appendingPathComponent("tlc.trace.stdout.log"))
      try writeText(trace.stderr, to: input.outputDirectory.appendingPathComponent("tlc.trace.stderr.log"))
    }
    let trace = input.request.traceOutput
    if FileManager.default.fileExists(atPath: trace.path) {
      try FileManager.default.copyItem(at: trace, to: input.outputDirectory.appendingPathComponent("counterexample.json"))
    }
  }

  private func retainPrimaryResult(_ result: TLCProcessResultV1, input: TLCTemporalCaptureInputV1) throws {
    try writeJSON(processJSON(result), to: input.outputDirectory.appendingPathComponent("tlc-result.json"))
  }

}

extension TLCTemporalAdapterV1 {
  private func temporalResult(
    run: TLCProcessRunV1,
    graphID: String,
    initialStateIDs: [String],
    graph: CanonicalRunV1,
    outputDirectory: URL,
    relativeOutputDirectory: String,
    allowsImplicitStuttering: Bool
  ) throws -> TemporalPropertyResultV1 {
    if run.primary.reportedExhaustiveCompletion {
      return try TemporalPropertyResultV1(
        availability: .evaluated, outcome: .satisfied, graphID: graphID, initialStateIDs: initialStateIDs,
        traceAvailability: .notApplicable)
    }
    guard isTemporalViolation(run.primary),
          FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("counterexample.json").path),
          let counterexample = try? TLCTraceParserV1().parseCounterexample(
            Data(contentsOf: outputDirectory.appendingPathComponent("counterexample.json"))),
          traceIsBound(counterexample, to: graph, allowsImplicitStuttering: allowsImplicitStuttering),
          let lasso = lasso(from: counterexample, allowsImplicitStuttering: allowsImplicitStuttering) else {
      return try TemporalPropertyResultV1(
        availability: .unavailable, outcome: nil, graphID: graphID, initialStateIDs: initialStateIDs,
        traceAvailability: .unavailable)
    }
    let traceEvidence = try reference(
      outputDirectory.appendingPathComponent("counterexample.json"), relativeTo: relativeOutputDirectory)
    return try TemporalPropertyResultV1(
      availability: .evaluated, outcome: .violated, graphID: graphID, initialStateIDs: initialStateIDs,
      traceAvailability: .available, traceEvidence: traceEvidence, lasso: lasso)
  }

  private func comparison(
    input: TLCTemporalCaptureInputV1,
    tlcResult: TemporalPropertyResultV1,
    tlcEvidence: CoreEvidenceReferenceV1,
    completeGraphEvidence: TemporalCompleteGraphEvidenceV1?
  ) throws -> TemporalComparisonV1 {
    let outcome: TemporalSymmetryExpectedOutcomeV1
    let diagnostic: TemporalSymmetryDiagnosticCodeV1
    if input.swiftResult.availability == .unavailable || tlcResult.availability == .unavailable {
      outcome = .unavailable
      diagnostic = .temporalEvidenceUnavailable
    } else if input.swiftResult.outcome == tlcResult.outcome,
              input.swiftResult.graphID == tlcResult.graphID,
              input.swiftResult.initialStateIDs == tlcResult.initialStateIDs {
      outcome = .exact
      diagnostic = .exactAgreement
    } else if input.swiftResult.outcome != tlcResult.outcome {
      outcome = .difference
      diagnostic = .propertyOutcomeDifference
    } else if input.swiftResult.graphID != tlcResult.graphID {
      outcome = .difference
      diagnostic = .graphIdentityDifference
    } else {
      outcome = .difference
      diagnostic = .initialStateDifference
    }
    return try TemporalComparisonV1(
      caseID: input.declaredCase.id,
      configuration: input.declaredCase.configuration,
      correlation: input.correlation,
      outcome: outcome,
      swiftResult: input.swiftResult,
      tlcResult: tlcResult,
      swiftEvidence: input.swiftEvidence,
      tlcEvidence: tlcEvidence,
      completeGraphEvidence: completeGraphEvidence,
      enablednessEvidence: input.enablednessEvidence,
      fairComponents: input.fairComponents,
      rejectedComponents: input.rejectedComponents,
      diagnosticCode: diagnostic)
  }

  private func lasso(
    from evidence: TLCCounterexampleEvidenceV1, allowsImplicitStuttering: Bool
  ) -> TemporalLassoWitnessV1? {
    let stateIDs = evidence.states.map { $0.key.canonicalEncoding }
    if evidence.transitions.isEmpty, allowsImplicitStuttering, let state = stateIDs.first {
      return try? TemporalLassoWitnessV1(prefixStateIDs: [], cycleStateIDs: [state, state])
    }
    guard evidence.transitions.count == stateIDs.count,
          let loopStart = stateIDs.firstIndex(of: evidence.transitions.last?.target.key.canonicalEncoding ?? "") else {
      return nil
    }
    return try? TemporalLassoWitnessV1(
      prefixStateIDs: Array(stateIDs[..<loopStart]),
      cycleStateIDs: Array(stateIDs[loopStart...]) + [stateIDs[loopStart]])
  }

  private func traceIsBound(
    _ trace: TLCCounterexampleEvidenceV1,
    to graph: CanonicalRunV1,
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

  private func completedRun(from error: Error) -> TLCProcessRunV1? {
    switch error {
    case TLCProcessErrorV1.traceCaptureFailed(let completed, _),
      TLCProcessErrorV1.traceCaptureExecutionFailed(let completed, _),
      TLCProcessErrorV1.requiredReplayFailed(let completed, _),
      TLCProcessErrorV1.requiredReplayExecutionFailed(let completed, _):
      return completed
    default:
      return nil
    }
  }

  private func retainGraphEvents(from request: TLCProcessRequestV1, to directory: URL) throws -> Data {
    let data = try Data(contentsOf: request.graphEvents)
    try data.write(to: directory.appendingPathComponent("graph-events.jsonl"), options: .atomic)
    return data
  }

  private func clearTraceOutput(for request: TLCProcessRequestV1) throws {
    let originalTraceOutput = request.traceOutput.standardizedFileURL
    let traceOutput = resolvedURL(originalTraceOutput)
    let workingDirectory = resolvedURL(request.workingDirectory)
    let workingPath = workingDirectory.path.hasSuffix("/") ? workingDirectory.path : workingDirectory.path + "/"
    guard traceOutput.path.hasPrefix(workingPath),
          !protectedArtifacts(for: request).contains(traceOutput) else {
      throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid
    }
    guard FileManager.default.fileExists(atPath: originalTraceOutput.path) else { return }
    let values = try originalTraceOutput.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw TLCTemporalAdapterErrorV1.graphEvidenceInvalid
    }
    try FileManager.default.removeItem(at: traceOutput)
  }

  private func protectedArtifacts(for request: TLCProcessRequestV1) -> [URL] {
    [
      request.javaExecutable,
      request.jar,
      request.bridgeClasses,
      request.module,
      request.configuration,
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

  private func isTemporalViolation(_ result: TLCProcessResultV1) -> Bool {
    let output = result.stdout + "\n" + result.stderr
    return result.isViolation && (
      output.localizedCaseInsensitiveContains("temporal")
        || output.localizedCaseInsensitiveContains("liveness")
    )
  }

  private func retainedFailureDirectory(for input: TLCTemporalCaptureInputV1) -> URL {
    if FileManager.default.fileExists(atPath: input.outputDirectory.path) { return input.outputDirectory }
    return input.outputDirectory.deletingLastPathComponent()
      .appendingPathComponent("\(input.outputDirectory.lastPathComponent)-unavailable")
  }

  private func diagnosticCode(for error: Error) -> String {
    switch error {
    case TLCTemporalAdapterErrorV1.outputAlreadyExists: "output-already-exists"
    case TLCTemporalAdapterErrorV1.correlationMismatch: "foreign-run"
    case TLCTemporalAdapterErrorV1.provenanceMismatch: "toolchain-mismatch"
    case TLCTemporalAdapterErrorV1.sourceInputMismatch: "source-input-mismatch"
    case TLCTemporalAdapterErrorV1.manifestMismatch: "manifest-mismatch"
    case TLCTemporalAdapterErrorV1.toolchainMismatch: "toolchain-mismatch"
    default: "temporal-evidence-unavailable"
    }
  }

  private func evidence(named: String, in directory: URL, relativeTo root: String, object: Any) throws -> CoreEvidenceReferenceV1 {
    let url = directory.appendingPathComponent(named)
    try writeJSON(object, to: url)
    return try reference(url, relativeTo: root)
  }

  private func reference(_ url: URL, relativeTo root: String) throws -> CoreEvidenceReferenceV1 {
    try CoreEvidenceReferenceV1(path: "\(root)/\(url.lastPathComponent)", sha256: SHA256V1.hex(Data(contentsOf: url)))
  }

  private func copy(_ source: URL, as name: String, to directory: URL) throws {
    let destination = directory.appendingPathComponent(name)
    try FileManager.default.copyItem(at: source, to: destination)
  }
}

private func processJSON(_ result: TLCProcessResultV1) -> [String: Any] {
  ["status": result.status, "reportedExhaustiveCompletion": result.reportedExhaustiveCompletion, "isViolation": result.isViolation]
}

private func writeJSON(_ object: Any, to url: URL) throws {
  try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
}

private func writeText(_ text: String, to url: URL) throws {
  try Data(text.utf8).write(to: url, options: .atomic)
}
