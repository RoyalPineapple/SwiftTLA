import Foundation
import SwiftTLA
public enum CoreConformanceExitCode: Int32, Equatable, Sendable {
  case exact = 0
  case semanticDifference = 1
  case failure = 2
}
public enum CoreConformanceEngine: String, Codable, Equatable, Sendable {
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
package struct CoreConformanceRunner: Sendable {
  private let swiftAdapter: SwiftGraphAdapter
  private let tlcAdapter: TLCProcessAdapter
  package init(
    swiftAdapter: SwiftGraphAdapter = SwiftGraphAdapter(),
    tlcAdapter: TLCProcessAdapter = TLCProcessAdapter()
  ) {
    self.swiftAdapter = swiftAdapter
    self.tlcAdapter = tlcAdapter
  }
  package func run(
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
      try tlcAdapter.retain(request: tlcRequest, in: createdStaging)
      guard declaredCase == tlcRequest.expectedCase else {
        throw RunnerError.tlcCaseMismatch
      }
      phase = .swiftAdaptation
      let swiftEvidence = try swiftExploration()
      let swiftRun = try swiftAdapter.adapt(
        swiftEvidence, for: declaredCase, actionNames: swiftActionNames)
      try CanonicalConformanceEvidence.writeSwiftRun(
        swiftRun,
        correlation: correlations.swift,
        to: createdStaging
      )
      phase = .tlcExecution
      let tlcCapture = try tlcAdapter.capture(
        tlcRequest,
        replay: replay,
        retainingIn: createdStaging
      )
      phase = .tlcParsing
      let tlcRun = tlcCapture.graph
      try CanonicalConformanceEvidence.writeTLCRun(
        tlcRun,
        correlation: correlations.tlc,
        to: createdStaging
      )
      phase = .comparison
      let comparison = try CanonicalConformanceEvidence.write(
        correlations: correlations,
        to: createdStaging
      )
      let exitCode: CoreConformanceExitCode =
        comparison.isConformant ? .exact : .semanticDifference
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
      let failurePhase: CoreConformancePhase = error is TLCGraphEventError ? .tlcParsing : phase
      let failureDiagnostic = diagnostic(
        phase: failurePhase, error: error, request: tlcRequest, correlations: correlations)
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
    try ConformanceEvidence.createDirectory(parent, beneath: parent)
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
      try tlcAdapter.retain(request: request, in: staging)
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
}

extension CoreConformanceRunner {
  private func writeDiagnostic(_ diagnostic: CoreConformanceDiagnostic, to directory: URL) throws {
    try ConformanceEvidence.writeJSON(
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
    try ConformanceEvidence.writeJSON(object, to: directory.appendingPathComponent("run.json"))
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
    case .swiftAdaptation: "Inspect swift-run.json and the declared Swift model before changing the formal source."
    case .tlcExecution: "Inspect the retained TLC invocation, stdout, and stderr before retrying."
    case .tlcParsing: "Inspect graph-events.jsonl and the TLC module/configuration before rerunning."
    case .comparison: "Inspect the exact graph differences, tlc-run.json, and swift-run.json."
    case .publication: "Inspect the staging and destination paths; preserve the failure evidence before retrying publication."
    }
  }
}
