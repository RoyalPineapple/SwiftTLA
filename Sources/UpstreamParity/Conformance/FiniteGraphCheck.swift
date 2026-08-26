import Foundation
import SwiftTLA

package enum FiniteGraphExitCode: Int32, Equatable, Sendable {
  case exact = 0
  case semanticDifference = 1
  case failure = 2
}

package enum FiniteGraphPhase: String, Equatable, Sendable {
  case preflight
  case swiftExport = "swift-export"
  case tlcExecution = "tlc-execution"
  case tlcParsing = "tlc-parsing"
  case comparison
  case publication
}

package struct FiniteGraphDiagnostic: Equatable, Sendable {
  package let code: String
  package let message: String
  package let report: ConformanceFailureReport
  package let phase: FiniteGraphPhase
}

package struct FiniteGraphCheckOutput: Sendable {
  package let exitCode: FiniteGraphExitCode
  package let evidenceDirectory: URL?
  package let comparison: GraphComparison?
  package let diagnostic: FiniteGraphDiagnostic?
}

package struct FiniteGraphCheck: Sendable {
  private let swiftExporter: SwiftGraphExporter
  private let tlcProcess: TLCProcessAdapter

  package init(
    swiftExporter: SwiftGraphExporter = SwiftGraphExporter(),
    tlcProcess: TLCProcessAdapter = TLCProcessAdapter()
  ) {
    self.swiftExporter = swiftExporter
    self.tlcProcess = tlcProcess
  }

  package func run(
    `case` finiteGraphCase: FiniteGraphCase,
    swiftExploration: () throws -> SwiftExplorationEvidence,
    tlcRequest: TLCProcessRequest,
    replay: TLCReplayPolicy,
    outputDirectory: URL
  ) -> FiniteGraphCheckOutput {
    guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
      let failure = diagnostic(
        phase: .preflight,
        code: "output-exists",
        error: FiniteGraphCheckError.outputAlreadyExists,
        request: tlcRequest
      )
      return .init(exitCode: .failure, evidenceDirectory: nil, comparison: nil, diagnostic: failure)
    }

    var phase: FiniteGraphPhase = .preflight
    var staging: URL?
    do {
      let directory = try createStagingDirectory(
        beside: outputDirectory,
        caseID: finiteGraphCase.id,
        runID: tlcRequest.runID
      )
      staging = directory
      try tlcProcess.retain(request: tlcRequest, in: directory)
      guard finiteGraphCase == tlcRequest.expectedCase else { throw FiniteGraphCheckError.tlcCaseMismatch }

      phase = .swiftExport
      let actionNames = Dictionary(uniqueKeysWithValues: finiteGraphCase.renderedActions.map {
        ($0.sourceInvocationName, $0.renderedName)
      })
      let swiftRun = try swiftExporter.export(swiftExploration(), for: finiteGraphCase, actionNames: actionNames)
      try CanonicalGraphRecords.write(
        swiftRun,
        to: directory.appendingPathComponent("swift-graph.jsonl")
      )

      phase = .tlcExecution
      let tlcCapture = try tlcProcess.capture(
        tlcRequest,
        replay: replay,
        retainingIn: directory
      )

      phase = .tlcParsing
      let tlcRun = tlcCapture.graph
      try CanonicalGraphRecords.write(
        tlcRun,
        to: directory.appendingPathComponent("tlc-graph.jsonl")
      )

      phase = .comparison
      let comparison = compareFiniteGraphs(expected: tlcRun, actual: swiftRun)
      try writeComparison(
        comparison,
        caseID: finiteGraphCase.id,
        swiftRun: swiftRun,
        tlcRun: tlcRun,
        to: directory
      )

      phase = .publication
      try publish(staging: directory, to: outputDirectory)
      return .init(
        exitCode: comparison.isConformant ? .exact : .semanticDifference,
        evidenceDirectory: outputDirectory,
        comparison: comparison,
        diagnostic: nil
      )
    } catch {
      let failurePhase: FiniteGraphPhase = error is TLCGraphEventError ? .tlcParsing : phase
      let failure = diagnostic(phase: failurePhase, error: error, request: tlcRequest)
      guard let staging else {
        return .init(
          exitCode: .failure,
          evidenceDirectory: nil,
          comparison: nil,
          diagnostic: failure
        )
      }
      do {
        try writeDiagnostic(failure, to: staging)
        return .init(
          exitCode: .failure,
          evidenceDirectory: try publishFailure(staging: staging, to: outputDirectory),
          comparison: nil,
          diagnostic: failure
        )
      } catch {
        return .init(
          exitCode: .failure,
          evidenceDirectory: nil,
          comparison: nil,
          diagnostic: diagnostic(
            phase: .publication,
            code: "evidence-retention-failed",
            error: error,
            request: tlcRequest
          )
        )
      }
    }
  }

  private func writeComparison(
    _ comparison: GraphComparison,
    caseID: String,
    swiftRun: CompletedGraphRun,
    tlcRun: CompletedGraphRun,
    to directory: URL
  ) throws {
    try ConformanceEvidence.writeJSON(
      [
        "caseID": caseID,
        "result": comparison.isConformant ? "exact" : "difference",
        "swiftComplete": swiftRun.isPassEligible,
        "tlcComplete": tlcRun.isPassEligible,
        "swift": graphSummary(swiftRun.graph),
        "tlc": graphSummary(tlcRun.graph),
        "differences": graphDifferencesJSON(comparison)
      ],
      to: directory.appendingPathComponent("comparison.json")
    )
  }

  private func graphSummary(_ graph: CanonicalGraph) -> [String: Int] {
    [
      "initialStates": graph.initialStateKeys.count,
      "states": graph.states.count,
      "edges": graph.edgeOccurrences.values.reduce(0, +)
    ]
  }

  private func writeDiagnostic(_ diagnostic: FiniteGraphDiagnostic, to directory: URL) throws {
    try ConformanceEvidence.writeJSON(
      [
        "code": diagnostic.code,
        "message": diagnostic.message,
        "phase": diagnostic.phase.rawValue,
        "report": failureReportJSON(diagnostic.report)
      ],
      to: directory.appendingPathComponent("diagnostic.json")
    )
  }

  private func diagnostic(
    phase: FiniteGraphPhase,
    code: String? = nil,
    error: Error,
    request: TLCProcessRequest
  ) -> FiniteGraphDiagnostic {
    let report: ConformanceFailureReport
    if let processError = error as? TLCProcessError {
      report = processError.failureReport(for: request)
    } else {
      report = .init(
        whatFailed: "Finite graph comparison could not complete \(phase.rawValue).",
        whereItFailed: "\(phase.rawValue) for case \(request.caseID)",
        expected: expectedWork(for: phase),
        actual: redactingSecrets(in: String(describing: error)),
        nextSafeAction: nextSafeAction(for: phase),
        evidence: [
          .init(role: "TLA+ module", location: request.moduleFileName),
          .init(role: "TLC configuration", location: request.configurationFileName),
          .init(role: "TLC graph event output", location: request.graphEvents.path)
        ]
      )
    }
    return .init(
      code: code ?? "\(phase.rawValue)-failed",
      message: redactingSecrets(in: String(describing: error)),
      report: report,
      phase: phase
    )
  }

  private func expectedWork(for phase: FiniteGraphPhase) -> String {
    switch phase {
    case .preflight: "A fresh output location and a launch binding that matches the declared case."
    case .swiftExport: "Swift exploration produces a complete canonical graph for the declared case."
    case .tlcExecution: "TLC launches and writes a complete graph event stream for the declared case."
    case .tlcParsing: "The TLC graph event stream is complete and belongs to this run."
    case .comparison: "The complete canonical TLC and SwiftTLA graphs compare exactly."
    case .publication: "The retained graphs, comparison, and TLC output publish atomically."
    }
  }

  private func nextSafeAction(for phase: FiniteGraphPhase) -> String {
    switch phase {
    case .preflight: "Choose a fresh output directory or inspect the existing retained files."
    case .swiftExport: "Inspect swift-graph.jsonl and the declared Swift model."
    case .tlcExecution: "Inspect the retained TLC invocation, stdout, and stderr."
    case .tlcParsing: "Inspect graph-events.jsonl and the TLC module and configuration."
    case .comparison: "Inspect comparison.json, tlc-graph.jsonl, and swift-graph.jsonl."
    case .publication: "Inspect the staging and destination paths."
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
    throw FiniteGraphCheckError.stagingDirectoryUnavailable
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
      throw FiniteGraphCheckError.stagingDirectoryUnavailable
    }
  }

}

private enum FiniteGraphCheckError: Error {
  case outputAlreadyExists
  case tlcCaseMismatch
  case stagingDirectoryUnavailable
}

private func failureReportJSON(_ report: ConformanceFailureReport) -> [String: Any] {
  [
    "whatFailed": report.whatFailed,
    "whereItFailed": report.whereItFailed,
    "expected": report.expected,
    "actual": report.actual,
    "nextSafeAction": report.nextSafeAction,
    "evidence": report.evidence.map { ["role": $0.role, "location": $0.location] },
    "toolOutput": report.toolOutput.map { ["stream": $0.stream, "content": $0.content] }
  ]
}
