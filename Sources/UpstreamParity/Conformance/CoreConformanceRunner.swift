import Foundation
import SwiftTLA
public enum CoreConformanceExitCode: Int32, Equatable, Sendable {
  case exact = 0
  case semanticDifference = 1
  case failure = 2
}
public enum CoreConformanceEngine: String, Equatable, Sendable {
  case swift
  case tlc
  case runner
}
public enum CoreConformancePhase: String, Equatable, Sendable {
  case preflight
  case swiftAdaptation = "swift-adaptation"
  case tlcExecution = "tlc-execution"
  case tlcParsing = "tlc-parsing"
  case comparison
  case publication
  fileprivate var engine: CoreConformanceEngine {
    switch self {
    case .swiftAdaptation: .swift
    case .tlcExecution, .tlcParsing: .tlc
    case .preflight, .comparison, .publication: .runner
    }
  }
}
public struct CoreConformanceCorrelation: Equatable, Sendable {
  public let caseID: String
  public let runID: UUID
  public let engine: CoreConformanceEngine
  public init(caseID: String, runID: UUID, engine: CoreConformanceEngine) {
    self.caseID = caseID
    self.runID = runID
    self.engine = engine
  }
}
public struct CoreConformanceDiagnostic: Equatable, Sendable {
  public let code: String
  public let message: String
  public let report: ConformanceFailureReport
  public let correlation: CoreConformanceCorrelation
  public let phase: CoreConformancePhase
  public init(
    code: String,
    message: String,
    report: ConformanceFailureReport,
    correlation: CoreConformanceCorrelation,
    phase: CoreConformancePhase
  ) {
    self.code = code
    self.message = message
    self.report = report
    self.correlation = correlation
    self.phase = phase
  }
}
public struct CoreConformanceRunResult: Sendable {
  public let exitCode: CoreConformanceExitCode
  public let correlation: CoreConformanceCorrelation
  public let evidenceDirectory: URL?
  public let comparison: ExactFiniteTLCComparison?
  public let diagnostic: CoreConformanceDiagnostic?
  public init(
    exitCode: CoreConformanceExitCode,
    correlation: CoreConformanceCorrelation,
    evidenceDirectory: URL?,
    comparison: ExactFiniteTLCComparison?,
    diagnostic: CoreConformanceDiagnostic?
  ) {
    self.exitCode = exitCode
    self.correlation = correlation
    self.evidenceDirectory = evidenceDirectory
    self.comparison = comparison
    self.diagnostic = diagnostic
  }
}
public struct CoreConformanceRunner: Sendable {
  private let swiftAdapter: SwiftGraphAdapter
  private let tlcAdapter: TLCProcessAdapter
  public init(
    swiftAdapter: SwiftGraphAdapter = SwiftGraphAdapter(),
    tlcAdapter: TLCProcessAdapter = TLCProcessAdapter()
  ) {
    self.swiftAdapter = swiftAdapter
    self.tlcAdapter = tlcAdapter
  }
  public func run(
    `case` declaredCase: CoreConformanceCase,
    swiftExploration: () throws -> SwiftExplorationEvidence,
    tlcRequest: TLCProcessRequest,
    replay: TLCReplayPolicy,
    outputDirectory: URL,
    swiftActionNames: [String: String] = [:]
  ) -> CoreConformanceRunResult {
    let correlations = Correlations(
      caseID: declaredCase.id,
      runID: tlcRequest.runID
    )
    guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
      let preflightDiagnostic = diagnostic(
        phase: .preflight,
        code: "output-exists",
        error: RunnerError.outputAlreadyExists,
        request: tlcRequest,
        correlations: correlations
      )
      let evidenceDirectory: URL?
      let reportedDiagnostic: CoreConformanceDiagnostic
      do {
        evidenceDirectory = try retainPreflightFailure(
          diagnostic: preflightDiagnostic,
          declaredCase: declaredCase,
          request: tlcRequest,
          correlations: correlations,
          beside: outputDirectory
        )
        reportedDiagnostic = preflightDiagnostic
      } catch {
        evidenceDirectory = nil
        reportedDiagnostic = diagnostic(
          phase: .preflight,
          code: "preflight-evidence-retention-failed",
          error: error,
          request: tlcRequest,
          correlations: correlations
        )
      }
      return CoreConformanceRunResult(
        exitCode: .failure,
        correlation: correlations.runner,
        evidenceDirectory: evidenceDirectory,
        comparison: nil,
        diagnostic: reportedDiagnostic
      )
    }
    var phase: CoreConformancePhase = .preflight
    var staging: URL?
    do {
      let createdStaging = try createStagingDirectory(
        beside: outputDirectory,
        caseID: declaredCase.id,
        runID: tlcRequest.runID
      )
      staging = createdStaging
      try retainInvocationSnapshot(
        declaredCase: declaredCase,
        request: tlcRequest,
        correlations: correlations,
        in: createdStaging
      )
      guard declaredCase == tlcRequest.expectedCase else {
        throw RunnerError.tlcCaseMismatch
      }
      phase = .swiftAdaptation
      let swiftRun = try swiftAdapter.adapt(
        try swiftExploration(), for: declaredCase, actionNames: swiftActionNames)
      try writeCanonicalRun(
        swiftRun, named: "swift.json", correlation: correlations.swift, to: createdStaging)
      phase = .tlcExecution
      let tlcProcessRun = try tlcAdapter.run(tlcRequest, replay: replay)
      try retainProcessRun(
        tlcProcessRun, request: tlcRequest, correlation: correlations.tlc, in: createdStaging)
      phase = .tlcParsing
      let graphEvents = try Data(contentsOf: tlcRequest.graphEvents)
      let parser = TLCGraphEventParser(expectedCase: declaredCase)
      let stream = try parser.parse(graphEvents)
      guard stream.runID == tlcRequest.runID else {
        throw RunnerError.tlcRunMismatch(expected: tlcRequest.runID, actual: stream.runID)
      }
      let tlcRun = try parser.parseCanonicalRun(graphEvents, result: tlcProcessRun.primary)
      try writeCanonicalRun(
        tlcRun, named: "tlc.json", correlation: correlations.tlc, to: createdStaging)
      phase = .comparison
      let comparison = exactFiniteTLCGraph(expected: tlcRun, actual: swiftRun)
      let exitCode: CoreConformanceExitCode =
        comparison.isConformant ? .exact : .semanticDifference
      try writeComparison(comparison, correlation: correlations.runner, to: createdStaging)
      try writeRun(
        exitCode: exitCode, correlation: correlations.runner, diagnostic: nil, to: createdStaging)
      phase = .publication
      try publish(staging: createdStaging, to: outputDirectory)
      return CoreConformanceRunResult(
        exitCode: exitCode,
        correlation: correlations.runner,
        evidenceDirectory: outputDirectory,
        comparison: comparison,
        diagnostic: nil
      )
    } catch {
      let failureDiagnostic = diagnostic(
        phase: phase, error: error, request: tlcRequest, correlations: correlations)
      guard let staging else {
        return CoreConformanceRunResult(
          exitCode: .failure,
          correlation: correlations.runner,
          evidenceDirectory: nil,
          comparison: nil,
          diagnostic: failureDiagnostic
        )
      }
      if phase == .publication {
        do {
          try writeDiagnostic(failureDiagnostic, to: staging)
          try writeRun(
            exitCode: .failure,
            correlation: correlations.runner,
            diagnostic: failureDiagnostic,
            to: staging
          )
          let evidenceDirectory = try publishFailure(staging: staging, to: outputDirectory)
          return CoreConformanceRunResult(
            exitCode: .failure,
            correlation: correlations.runner,
            evidenceDirectory: evidenceDirectory,
            comparison: nil,
            diagnostic: failureDiagnostic
          )
        } catch {
          let retentionDiagnostic = diagnostic(
            phase: .publication,
            code: "evidence-retention-failed",
            error: error,
            request: tlcRequest,
            correlations: correlations
          )
          return CoreConformanceRunResult(
            exitCode: .failure,
            correlation: correlations.runner,
            evidenceDirectory: nil,
            comparison: nil,
            diagnostic: retentionDiagnostic
          )
        }
      }
      do {
        try retainFailure(error, request: tlcRequest, in: staging)
        try writeDiagnostic(failureDiagnostic, to: staging)
        try writeRun(
          exitCode: .failure,
          correlation: correlations.runner,
          diagnostic: failureDiagnostic,
          to: staging
        )
        let evidenceDirectory = try publishFailure(staging: staging, to: outputDirectory)
        return CoreConformanceRunResult(
          exitCode: .failure,
          correlation: correlations.runner,
          evidenceDirectory: evidenceDirectory,
          comparison: nil,
          diagnostic: failureDiagnostic
        )
      } catch {
        let retentionDiagnostic = diagnostic(
          phase: .publication,
          code: "evidence-retention-failed",
          error: error,
          request: tlcRequest,
          correlations: correlations
        )
        return CoreConformanceRunResult(
          exitCode: .failure,
          correlation: correlations.runner,
          evidenceDirectory: nil,
          comparison: nil,
          diagnostic: retentionDiagnostic
        )
      }
    }
  }
  private func createStagingDirectory(beside output: URL, caseID: String, runID: UUID) throws -> URL {
    let parent = output.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    for _ in 0..<16 {
      let path = parent.appendingPathComponent(
        ".\(caseID).\(runID.uuidString.lowercased()).\(UUID().uuidString.lowercased()).staging"
      )
      do {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        return path
      } catch CocoaError.fileWriteFileExists {
        continue
      }
    }
    throw RunnerError.stagingDirectoryUnavailable
  }
  private func publish(staging: URL, to outputDirectory: URL) throws {
    try FileManager.default.moveItem(at: staging, to: outputDirectory)
  }
  private func publishFailure(staging: URL, to outputDirectory: URL) throws -> URL {
    do {
      try publish(staging: staging, to: outputDirectory)
      return outputDirectory
    } catch {
      guard FileManager.default.fileExists(atPath: outputDirectory.path) else { throw error }
      let parent = outputDirectory.deletingLastPathComponent()
      for _ in 0..<16 {
        let sibling = parent.appendingPathComponent(
          ".\(outputDirectory.lastPathComponent).\(UUID().uuidString.lowercased()).failure"
        )
        do {
          try publish(staging: staging, to: sibling)
          return sibling
        } catch CocoaError.fileWriteFileExists {
          continue
        }
      }
      throw RunnerError.stagingDirectoryUnavailable
    }
  }
  private func retainPreflightFailure(
    diagnostic: CoreConformanceDiagnostic,
    declaredCase: CoreConformanceCase,
    request: TLCProcessRequest,
    correlations: Correlations,
    beside outputDirectory: URL
  ) throws -> URL {
    let failureDirectory = outputDirectory.deletingLastPathComponent().appendingPathComponent(
      ".\(outputDirectory.lastPathComponent).\(request.runID.uuidString.lowercased()).\(UUID().uuidString.lowercased()).failure"
    )
    let staging = try createStagingDirectory(
      beside: failureDirectory,
      caseID: declaredCase.id,
      runID: request.runID
    )
    do {
      try retainInvocationSnapshot(
        declaredCase: declaredCase,
        request: request,
        correlations: correlations,
        in: staging
      )
      try retainRawArtifacts(from: request, in: staging)
      try writeDiagnostic(diagnostic, to: staging)
      try writeRun(
        exitCode: .failure,
        correlation: correlations.runner,
        diagnostic: diagnostic,
        to: staging
      )
      try publish(staging: staging, to: failureDirectory)
      return failureDirectory
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw error
    }
  }
  private func retainInvocationSnapshot(
    declaredCase: CoreConformanceCase,
    request: TLCProcessRequest,
    correlations: Correlations,
    in directory: URL
  ) throws {
    try writeJSON(caseJSON(declaredCase), to: directory.appendingPathComponent("case.json"))
    try writeJSON(
      toolchainJSON(for: request), to: directory.appendingPathComponent("toolchain.json"))
    try writeJSON(
      ["arguments": request.arguments], to: directory.appendingPathComponent("arguments.json"))
    try writeJSON(correlations.json, to: directory.appendingPathComponent("correlations.json"))
  }
  private func retainProcessRun(
    _ run: TLCProcessRun,
    request: TLCProcessRequest,
    correlation: CoreConformanceCorrelation,
    in directory: URL
  ) throws {
    try retainProcessResult(run.primary, phase: .primary, in: directory)
    if let trace = run.trace {
      try retainProcessResult(trace, phase: .trace, in: directory)
    }
    if let replay = run.replay {
      try retainProcessResult(replay, phase: .replay, in: directory)
    }
    try writeProcessSnapshot(
      primary: run.primary,
      trace: run.trace,
      replay: run.replay,
      errors: [:],
      correlation: correlation,
      to: directory
    )
    try retainRawArtifacts(from: request, in: directory)
  }
  private func retainFailure(_ error: Error, request: TLCProcessRequest, in directory: URL) throws {
    let correlation = CoreConformanceCorrelation(
      caseID: request.caseID, runID: request.runID, engine: .tlc)
    switch error {
    case TLCProcessError.traceCaptureFailed(let completed, let failed):
      try retainProcessResult(completed.primary, phase: .primary, in: directory)
      try retainProcessResult(failed, phase: .trace, in: directory)
      try writeProcessSnapshot(
        primary: completed.primary, trace: failed, replay: nil, errors: [:], correlation: correlation,
        to: directory)
    case TLCProcessError.requiredReplayFailed(let completed, let failed):
      try retainProcessResult(completed.primary, phase: .primary, in: directory)
      if let trace = completed.trace { try retainProcessResult(trace, phase: .trace, in: directory) }
      try retainProcessResult(failed, phase: .replay, in: directory)
      try writeProcessSnapshot(
        primary: completed.primary, trace: completed.trace, replay: failed, errors: [:],
        correlation: correlation, to: directory)
    case TLCProcessError.traceCaptureExecutionFailed(let completed, let error):
      try retainProcessResult(completed.primary, phase: .primary, in: directory)
      try retainExecutionFailure(error, phase: .trace, in: directory)
      try writeProcessSnapshot(
        primary: completed.primary, trace: nil, replay: nil, errors: [.trace: error],
        correlation: correlation, to: directory)
    case TLCProcessError.requiredReplayExecutionFailed(let completed, let error):
      try retainProcessResult(completed.primary, phase: .primary, in: directory)
      if let trace = completed.trace { try retainProcessResult(trace, phase: .trace, in: directory) }
      try retainExecutionFailure(error, phase: .replay, in: directory)
      try writeProcessSnapshot(
        primary: completed.primary, trace: completed.trace, replay: nil, errors: [.replay: error],
        correlation: correlation, to: directory)
    default:
      let failure = TLCProcessExecutionFailure(error)
      try retainExecutionFailure(failure, phase: .primary, in: directory)
      try writeProcessSnapshot(
        primary: nil, trace: nil, replay: nil, errors: [.primary: failure], correlation: correlation,
        to: directory)
    }
    try retainRawArtifacts(from: request, in: directory)
  }
  private func retainProcessResult(
    _ result: TLCProcessResult,
    phase: TLCInvocationPhase,
    in directory: URL
  ) throws {
    let logs = try logsDirectory(in: directory)
    try writeText(sanitized(result.stdout), to: logs.appendingPathComponent(phase.stdoutLog))
    try writeText(sanitized(result.stderr), to: logs.appendingPathComponent(phase.stderrLog))
  }
}

extension CoreConformanceRunner {
  private func retainExecutionFailure(
    _ failure: TLCProcessExecutionFailure,
    phase: TLCInvocationPhase,
    in directory: URL
  ) throws {
    let logs = try logsDirectory(in: directory)
    if let stdout = failure.partialStdout, let stderr = failure.partialStderr {
      try writeText(sanitized(stdout), to: logs.appendingPathComponent(phase.stdoutLog))
      try writeText(sanitized(stderr), to: logs.appendingPathComponent(phase.stderrLog))
    } else {
      try writeText(
        sanitized(failure.message),
        to: logs.appendingPathComponent("tlc.\(phase.rawValue).failure.log")
      )
    }
  }
  private func writeProcessSnapshot(
    primary: TLCProcessResult?,
    trace: TLCProcessResult?,
    replay: TLCProcessResult?,
    errors: [TLCInvocationPhase: TLCProcessExecutionFailure],
    correlation: CoreConformanceCorrelation,
    to directory: URL
  ) throws {
    let phases: [(TLCInvocationPhase, TLCProcessResult?)] = [
      (.primary, primary), (.trace, trace), (.replay, replay)
    ]
    let attempts = phases.compactMap { phase, result -> String? in
      result != nil || errors[phase] != nil ? phase.rawValue : nil
    }
    var snapshot: [String: Any] = [
      "correlation": correlationJSON(correlation),
      "attempted": attempts
    ]
    for (phase, result) in phases {
      if let result {
        snapshot[phase.rawValue] = processJSON(result)
      } else if let error = errors[phase] {
        snapshot[phase.rawValue] = ["executionError": sanitized(error.message)]
      } else {
        snapshot[phase.rawValue] = NSNull()
      }
    }
    try writeJSON(snapshot, to: directory.appendingPathComponent("tlc-process.json"))
  }
  private func retainRawArtifacts(from request: TLCProcessRequest, in directory: URL) throws {
    let artifacts = [
      (request.graphEvents, "graph-events.jsonl"),
      (graphEvents(for: request.graphEvents, phase: .trace), "graph-events.trace.jsonl"),
      (graphEvents(for: request.graphEvents, phase: .replay), "graph-events.replay.jsonl"),
      (request.traceOutput, "counterexample.json"),
      (request.replayInput, "replay.json")
    ]
    var availability: [String: Bool] = [:]
    for (source, name) in artifacts {
      let destination = directory.appendingPathComponent(name)
      let exists = FileManager.default.fileExists(atPath: source.path)
      availability[name] = exists
      if exists {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
      }
    }
    try writeJSON(availability, to: directory.appendingPathComponent("raw-artifacts.json"))
  }
  private func logsDirectory(in directory: URL) throws -> URL {
    let logs = directory.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    return logs
  }
  private func graphEvents(for primary: URL, phase: TLCInvocationPhase) -> URL {
    primary.deletingPathExtension().appendingPathExtension("\(phase.rawValue).jsonl")
  }
  private func writeCanonicalRun(
    _ run: CanonicalRun,
    named name: String,
    correlation: CoreConformanceCorrelation,
    to directory: URL
  ) throws {
    let edges = run.graph.edgeOccurrences.keys.sorted().map { edge in
      ["edge": edge.canonicalEncoding, "count": run.graph.edgeOccurrences[edge] ?? 0]
        as [String: Any]
    }
    try writeJSON(
      [
        "schema": run.schema.rawValue,
        "correlation": correlationJSON(correlation),
        "initialStates": run.graph.initialStateKeys.sorted().map(\.canonicalEncoding),
        "states": run.graph.states.keys.sorted().map(\.canonicalEncoding),
        "edges": edges,
        "observations": observationsJSON(run.graph.observations),
        "observableActions": run.observableActions.sorted(),
        "outcome": outcomeJSON(run.outcome),
        "errors": run.errors.map { ["code": $0.code, "message": $0.message] },
        "traces": run.traces.map(traceJSON)
      ], to: directory.appendingPathComponent(name))
  }
  private func writeComparison(
    _ comparison: ExactFiniteTLCComparison,
    correlation: CoreConformanceCorrelation,
    to directory: URL
  ) throws {
    try writeJSON(
      [
        "correlation": correlationJSON(correlation),
        "conformant": comparison.isConformant,
        "differences": comparison.differences.map(differenceJSON)
      ], to: directory.appendingPathComponent("comparison.json"))
    if !comparison.isConformant {
      try writeJSON(
        ["reports": comparison.failureReports.map(failureReportJSON)],
        to: directory.appendingPathComponent("comparison-diagnostics.json"))
    }
  }
  private func writeDiagnostic(_ diagnostic: CoreConformanceDiagnostic, to directory: URL) throws {
    try writeJSON(
      [
        "code": diagnostic.code,
        "message": diagnostic.message,
        "phase": diagnostic.phase.rawValue,
        "correlation": correlationJSON(diagnostic.correlation),
        "report": failureReportJSON(diagnostic.report)
      ], to: directory.appendingPathComponent("diagnostic.json"))
  }
  private func writeRun(
    exitCode: CoreConformanceExitCode,
    correlation: CoreConformanceCorrelation,
    diagnostic: CoreConformanceDiagnostic?,
    to directory: URL
  ) throws {
    var object: [String: Any] = [
      "exitCode": exitCode.rawValue,
      "correlation": correlationJSON(correlation)
    ]
    if let diagnostic {
      object["diagnostic"] = [
        "code": diagnostic.code,
        "phase": diagnostic.phase.rawValue,
        "message": diagnostic.message
      ]
    }
    try writeJSON(object, to: directory.appendingPathComponent("run.json"))
  }
  private func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }
  private func writeText(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url, options: .atomic)
  }
  private func diagnostic(
    phase: CoreConformancePhase,
    code: String? = nil,
    error: Error,
    request: TLCProcessRequest,
    correlations: Correlations
  ) -> CoreConformanceDiagnostic {
    let report: ConformanceFailureReport
    if let processError = error as? TLCProcessError {
      report = processError.failureReport(for: request)
    } else {
      report = .init(
        whatFailed: "Core conformance could not complete \(phase.rawValue).",
        whereItFailed: "\(phase.rawValue) for case \(request.caseID)",
        expected: expectedWork(for: phase),
        actual: sanitized(String(describing: error)),
        systemChange: "No successful conformance claim was published; retained evidence records the completed work.",
        nextSafeAction: nextSafeAction(for: phase),
        evidence: [
          .init(role: "TLA+ module", location: request.moduleFileName),
          .init(role: "TLC configuration", location: request.configurationFileName),
          .init(role: "TLC graph event output", location: request.graphEvents.path)
        ]
      )
    }
    return CoreConformanceDiagnostic(
      code: code ?? "\(phase.rawValue)-failed",
      message: sanitized(String(describing: error)),
      report: report,
      correlation: correlations[phase.engine],
      phase: phase
    )
  }
  private func caseJSON(_ declaredCase: CoreConformanceCase) -> [String: Any] {
    var snapshot: [String: Any] = [
      "id": declaredCase.id,
      "moduleSHA256": declaredCase.moduleSHA256,
      "cfgSHA256": declaredCase.cfgSHA256,
      "arguments": declaredCase.arguments,
      "argumentsSHA256": declaredCase.argumentsSHA256,
      "workers": declaredCase.workers,
      "fingerprintPolynomial": declaredCase.fingerprintPolynomial,
      "deadlock": declaredCase.deadlock,
      "operatingSystem": declaredCase.operatingSystem,
      "architecture": declaredCase.architecture,
      "environment": declaredCase.environment,
      "pin": pinJSON(declaredCase.pin),
      "invocationMappings": declaredCase.invocationMappings.map { mapping in
        [
          "wrapper": mapping.wrapper,
          "action": mapping.action,
          "arguments": mapping.arguments,
          "indices": mapping.indices
        ]
      },
      "valueNormalizations": declaredCase.valueNormalizations.map { normalization in
        [
          "binding": normalization.binding,
          "functionKeys": normalization.functionKeys
        ]
      }
    ]
    if let governance = declaredCase.governance {
      snapshot["governance"] = [
        "role": governance.role.rawValue,
        "finiteBounds": [
          "summary": governance.finiteBounds.summary,
          "limits": governance.finiteBounds.limits
        ],
        "semanticCitations": governance.semanticCitations,
        "expectedRegressionOutcome": governance.expectedRegressionOutcome.rawValue
      ]
    }
    return snapshot
  }
  private func toolchainJSON(for request: TLCProcessRequest) -> [String: Any] {
    var result: [String: Any] = ["declaredPin": pinJSON(request.expectedCase.pin)]
    if let referencePin = request.referencePin {
      result["referencePin"] = pinJSON(referencePin)
    }
    if let artifacts = request.referenceArtifacts {
      result["referenceArtifacts"] = [
        "jar": artifacts.jar.path,
        "javaArchive": artifacts.javaArchive.path,
        "bridgeSource": artifacts.bridgeSource.path,
        "bridgeBinary": artifacts.bridgeBinary.path,
        "jarManifest": artifacts.jarManifest,
        "runtime": [
          "version": artifacts.runtime.version,
          "vendor": artifacts.runtime.vendor,
          "architecture": artifacts.runtime.architecture,
          "properties": artifacts.runtime.properties
        ]
      ]
    }
    return result
  }
  private func pinJSON(_ pin: TLCReferencePin) -> [String: String] {
    [
      "tag": pin.tag,
      "commit": pin.commit,
      "jarSHA256": pin.jarSHA256,
      "javaDistribution": pin.javaDistribution,
      "javaVersion": pin.javaVersion,
      "javaArchiveSHA256": pin.javaArchiveSHA256,
      "bridgeClass": pin.bridgeClass,
      "bridgeSourceSHA256": pin.bridgeSourceSHA256,
      "bridgeBinarySHA256": pin.bridgeBinarySHA256
    ]
  }
  private func processJSON(_ result: TLCProcessResult) -> [String: Any] {
    [
      "status": result.status, "isViolation": result.isViolation,
      "reportedExhaustiveCompletion": result.reportedExhaustiveCompletion
    ]
  }
  private func outcomeJSON(_ outcome: CanonicalOutcome) -> [String: String] {
    switch outcome {
    case .exhaustiveSuccess: ["kind": "exhaustiveSuccess"]
    case .invariantViolation(let value): ["kind": "invariantViolation", "message": value]
    case .deadlock(let state): ["kind": "deadlock", "state": state.canonicalEncoding]
    case .incomplete(let reason): ["kind": "incomplete", "message": reason]
    case .executionError(let reason): ["kind": "executionError", "message": reason]
    }
  }
  private func traceJSON(_ trace: CanonicalTrace) -> [String: Any] {
    [
      "id": trace.id,
      "steps": trace.steps.map { ["state": $0.state.canonicalEncoding, "action": $0.action] }
    ]
  }
  private func differenceJSON(_ difference: ConformanceDifference) -> [String: Any] {
    switch difference {
    case .mapping(let messages):
      ["category": difference.category.rawValue, "expected": [], "actual": [], "details": messages]
    case .initialStates(let expected, let actual), .states(let expected, let actual):
      [
        "category": difference.category.rawValue,
        "expected": expected.sorted().map(\.canonicalEncoding),
        "actual": actual.sorted().map(\.canonicalEncoding)
      ]
    case .edges(let expected, let actual):
      [
        "category": difference.category.rawValue,
        "expected": edgeOccurrencesJSON(expected),
        "actual": edgeOccurrencesJSON(actual)
      ]
    case .observations(let expected, let actual):
      [
        "category": difference.category.rawValue,
        "expected": observationsJSON(expected),
        "actual": observationsJSON(actual)
      ]
    case .outcome(let expected, let actual):
      [
        "category": difference.category.rawValue, "expected": outcomeJSON(expected),
        "actual": outcomeJSON(actual)
      ]
    case .errors(let expected, let actual):
      [
        "category": difference.category.rawValue,
        "expected": expected.map { ["code": $0.code, "message": $0.message] },
        "actual": actual.map { ["code": $0.code, "message": $0.message] }
      ]
    case .traces(let expected, let actual):
      [
        "category": difference.category.rawValue, "expected": expected.map(traceJSON),
        "actual": actual.map(traceJSON)
      ]
    }
  }
  private func failureReportJSON(_ report: ConformanceFailureReport) -> [String: Any] {
    [
      "whatFailed": report.whatFailed,
      "whereItFailed": report.whereItFailed,
      "expected": report.expected,
      "actual": report.actual,
      "systemChange": report.systemChange,
      "nextSafeAction": report.nextSafeAction,
      "evidence": report.evidence.map { ["role": $0.role, "location": $0.location] },
      "toolOutput": report.toolOutput.map { ["stream": $0.stream, "content": $0.content] }
    ]
  }
  private func expectedWork(for phase: CoreConformancePhase) -> String {
    switch phase {
    case .preflight: "A fresh output location and a launch binding that matches the declared case."
    case .swiftAdaptation: "Swift exploration adapts to complete canonical graph evidence for the declared case."
    case .tlcExecution: "TLC launches and writes a complete graph event stream for the declared case."
    case .tlcParsing: "The retained TLC graph event stream has the declared run ID and valid canonical events."
    case .comparison: "The canonical TLC and SwiftTLA runs compare exactly."
    case .publication: "The complete retained evidence is published atomically to the requested output directory."
    }
  }
  private func nextSafeAction(for phase: CoreConformancePhase) -> String {
    switch phase {
    case .preflight: "Choose a fresh output directory or inspect the existing retained evidence; do not overwrite it."
    case .swiftAdaptation: "Inspect swift.json and the declared Swift model before changing the formal source."
    case .tlcExecution: "Inspect the retained TLC invocation, stdout, and stderr before retrying."
    case .tlcParsing: "Inspect graph-events.jsonl and the TLC module/configuration before rerunning."
    case .comparison: "Inspect comparison-diagnostics.json, tlc.json, and swift.json before changing a guard or update."
    case .publication: "Inspect the staging and destination paths; preserve the failure evidence before retrying publication."
    }
  }
  private func edgeOccurrencesJSON(_ occurrences: [CanonicalEdge: Int]) -> [[String: Any]] {
    occurrences.keys.sorted().map { edge in
      ["edge": edge.canonicalEncoding, "count": occurrences[edge] ?? 0]
    }
  }
  private func observationsJSON(_ observations: [CanonicalStateKey: CanonicalStateObservation])
    -> [[String: Any]] {
    observations.keys.sorted().map { state in
      let observation = observations[state]!
      return [
        "state": state.canonicalEncoding,
        "enabledActions": observation.enabledActions.sorted(),
        "isTerminal": observation.isTerminal
      ]
    }
  }
  private func correlationJSON(_ correlation: CoreConformanceCorrelation) -> [String: String] {
    [
      "caseID": correlation.caseID,
      "runID": correlation.runID.uuidString.lowercased(),
      "engine": correlation.engine.rawValue
    ]
  }
}
