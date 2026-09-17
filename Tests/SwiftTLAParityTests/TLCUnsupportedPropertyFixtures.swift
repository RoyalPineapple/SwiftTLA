import Foundation
import UpstreamParity

struct TLCUnsupportedPropertyExecutor: TLCProcessExecuting {
  let unsupportedProperty: Bool

  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    if request.invocation == .finiteGraph {
      try graphStream(case: request.finiteGraphCase, runID: request.runID).write(to: request.graphEvents)
    }
    let configuration = request.bundle.cfg
    if configuration.contains("PROPERTY Progress"),
       unsupportedProperty || configuration.contains("INVARIANT Positive") {
      return .init(status: 255,
        stdout: "Error: Temporal formulas containing actions must be of forms <>[]A or []<>A.", stderr: "")
    }
    if configuration.contains("CHECK_DEADLOCK TRUE") {
      try numberedInitialStateTrace().write(to: request.traceOutput)
      return .init(status: 11, stdout: "Deadlock reached.", stderr: "")
    }
    return .init(status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
  }
}
