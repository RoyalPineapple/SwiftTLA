import Foundation
import UpstreamParity

struct TLCTautologyExecutor: TLCProcessExecuting {
  static let tautology = TLCProcessResult(status: 77,
    stdout: "Error: Temporal formula is a tautology (its negation is unsatisfiable).", stderr: "")
  let failingSafety: Bool

  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    if request.invocation == .finiteGraph {
      try graphStream(case: request.finiteGraphCase, runID: request.runID).write(to: request.graphEvents)
    }
    if request.bundle.cfg.contains("PROPERTY Progress") { return Self.tautology }
    if failingSafety && request.bundle.cfg.contains("INVARIANT Positive") {
      try numberedInitialStateTrace().write(to: request.traceOutput)
      return .init(status: 12, stdout: "Error: Invariant Positive is violated.", stderr: "")
    }
    if request.bundle.cfg.contains("CHECK_DEADLOCK TRUE") {
      try numberedInitialStateTrace().write(to: request.traceOutput)
      return .init(status: 11, stdout: "Error: Deadlock reached.", stderr: "")
    }
    return .init(status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
  }
}
