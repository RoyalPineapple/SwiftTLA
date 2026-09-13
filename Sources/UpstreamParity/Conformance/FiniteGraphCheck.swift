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
  package let report: CheckFailureReport
  package let phase: FiniteGraphPhase
}

package struct FiniteGraphCheckOutput: Sendable {
  package let exitCode: FiniteGraphExitCode
  package let evidenceDirectory: URL?
  package let comparison: GraphComparison?
  package let diagnostic: FiniteGraphDiagnostic?
}

package struct FiniteGraphCheck: Sendable {
  private let tlcProcess: TLCProcessAdapter

  package init(
    tlcProcess: TLCProcessAdapter = TLCProcessAdapter()
  ) {
    self.tlcProcess = tlcProcess
  }

  package func run(
    nativeRun: () throws -> NativeModelRun,
    tlcRequest: TLCProcessRequest,
    outputDirectory: URL
  ) -> FiniteGraphCheckOutput {
    let finiteGraphCase = tlcRequest.finiteGraphCase
    guard case .disabled = finiteGraphCase.exploration.symmetryReduction else {
      let failure = diagnostic(
        phase: .preflight,
        code: "symmetry-reduction-enabled",
        error: FiniteGraphCheckError.symmetryReductionEnabled,
        request: tlcRequest
      )
      return .init(
        exitCode: .failure,
        evidenceDirectory: nil,
        comparison: nil,
        diagnostic: failure
      )
    }
    guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
      let failure = diagnostic(
        phase: .preflight,
        code: "output-exists",
        error: FiniteGraphCheckError.outputAlreadyExists,
        request: tlcRequest
      )
      return .init(exitCode: .failure, evidenceDirectory: nil, comparison: nil, diagnostic: failure)
    }

    let started = ContinuousClock.now
    var phase: FiniteGraphPhase = .preflight
    func enter(_ next: FiniteGraphPhase) {
      phase = next
      let elapsed = started.duration(to: .now)
      FileHandle.standardError.write(Data("finite-graph \(finiteGraphCase.id): \(next.rawValue) at \(elapsed)\n".utf8))
    }
    var staging: URL?
    do {
      let directory = try createStagingDirectory(
        beside: outputDirectory,
        caseID: finiteGraphCase.id,
        runID: tlcRequest.runID
      )
      staging = directory

      enter(.swiftExport)
      let native = try nativeRun()
      let swiftRun = native.graph
      try RetainedFiles.writeCanonical(native.checks, to: directory.appendingPathComponent("native-checks.json"))
      try GraphRunRecords.write(
        swiftRun,
        to: directory.appendingPathComponent("swift-graph.jsonl")
      )

      enter(.tlcExecution)
      try validateReference(tlcRequest)
      let tlcCapture = try tlcProcess.capture(tlcRequest, retainingIn: directory)

      enter(.tlcParsing)
      let tlcRun = tlcCapture.graph
      try GraphRunRecords.write(
        tlcRun,
        to: directory.appendingPathComponent("tlc-graph.jsonl")
      )

      enter(.comparison)
      let comparison = compareFiniteGraphs(tlc: tlcRun, swift: swiftRun)
      guard tlcRun.isComparable, swiftRun.isComparable else { throw TLCPropertyCheckError.incompleteGraph }
      let generatedDirectory = directory.appendingPathComponent("generated")
      let generatedWork = tlcRequest.workingDirectory.appendingPathComponent(UUID().uuidString)
      try RetainedFiles.createDirectory(generatedWork, beneath: tlcRequest.workingDirectory)
      defer { try? FileManager.default.removeItem(at: generatedWork) }
      let generatedRequest = try tlcRequest.selecting(
        bundle: native.rendered.tlaBundle(checking: [], checkDeadlock: false),
        work: generatedWork, runID: UUID(), invocation: .finiteGraph)
      let generated = try tlcProcess.capture(generatedRequest, retainingIn: generatedDirectory)
      try GraphRunRecords.write(generated.graph, to: generatedDirectory.appendingPathComponent("tlc-graph.jsonl"))
      guard generated.graph.isComparable else { throw TLCPropertyCheckError.incompleteGraph }
      let results = try TLCPropertyCheck(processAdapter: tlcProcess).captureAll(
        native, completeGraph: .success(generated), in: directory)
      guard let generatedComparison = results.graphComparison else { throw TLCPropertyCheckError.incompleteGraph }
      let checks = Dictionary(uniqueKeysWithValues: results.checks.map {
        ($0.check.artifactPath, (try? $0.result.get().status) ?? .unavailable)
      })
      let exitCode: FiniteGraphExitCode
      if checks.values.contains(.unavailable) {
        exitCode = .failure
      } else if comparison.matches && generatedComparison.matches && checks.values.allSatisfy({ $0 == .exact }) {
        exitCode = .exact
      } else {
        exitCode = .semanticDifference
      }
      try writeComparison(
        comparison, generatedComparison: generatedComparison, checks: checks, exitCode: exitCode,
        caseID: finiteGraphCase.id,
        swiftRun: swiftRun,
        tlcRun: tlcRun,
        to: directory
      )

      enter(.publication)
      try publish(staging: directory, to: outputDirectory)
      return .init(
        exitCode: exitCode,
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
        try publish(staging: staging, to: outputDirectory)
        return .init(
          exitCode: .failure,
          evidenceDirectory: outputDirectory,
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

  private func validateReference(_ request: TLCProcessRequest) throws {
    try request.validateDeclaredBundle()
    guard SHA256.hex(Data(request.bundle.tla.utf8)) == request.finiteGraphCase.moduleSHA256 else {
      throw FiniteGraphCaseError.moduleDigestMismatch
    }
    guard SHA256.hex(Data(request.bundle.cfg.utf8)) == request.finiteGraphCase.cfgSHA256 else {
      throw FiniteGraphCaseError.cfgDigestMismatch
    }
  }

  private func writeComparison(
    _ comparison: GraphComparison,
    generatedComparison: GraphComparison,
    checks: [String: PropertyComparisonStatus],
    exitCode: FiniteGraphExitCode,
    caseID: String,
    swiftRun: GraphRun,
    tlcRun: GraphRun,
    to directory: URL
  ) throws {
    try RetainedFiles.writeJSON(
      [
        "caseID": caseID,
        "result": exitCode == .exact ? "exact" : (exitCode == .failure ? "unavailable" : "difference"),
        "checks": checks.mapValues(\.rawValue),
        "swiftComplete": swiftRun.isComplete,
        "tlcComplete": tlcRun.isComplete,
        "swift": graphSummary(swiftRun.graph),
        "tlc": graphSummary(tlcRun.graph),
        "differences": graphDifferencesJSON(comparison),
        "generatedDifferences": graphDifferencesJSON(generatedComparison)
      ],
      to: directory.appendingPathComponent("comparison.json")
    )
  }

  private func graphSummary(_ graph: CanonicalGraph) -> [String: Int] {
    [
      "initialStates": graph.initialStateKeys.count,
      "states": graph.states.count,
      "edges": graph.edges.count
    ]
  }

  private func writeDiagnostic(_ diagnostic: FiniteGraphDiagnostic, to directory: URL) throws {
    try RetainedFiles.writeJSON(
      [
        "code": diagnostic.code,
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
    let report: CheckFailureReport
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
    try RetainedFiles.createDirectory(parent, beneath: parent)
    let path = parent.appendingPathComponent(
      ".\(caseID).\(runID.uuidString.lowercased()).\(UUID().uuidString.lowercased()).staging"
    )
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
    return path
  }

  private func publish(staging: URL, to outputDirectory: URL) throws {
    try FileManager.default.moveItem(at: staging, to: outputDirectory)
  }

}

private enum FiniteGraphCheckError: Error {
  case outputAlreadyExists
  case symmetryReductionEnabled
}

private func failureReportJSON(_ report: CheckFailureReport) -> [String: Any] {
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
