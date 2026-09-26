import Foundation
import UpstreamParity

struct TLCConditionalPropertyExecutor: TLCProcessExecuting {
  let unavailableBranch: Bool
  let violatedBranch: Bool

  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    if request.bundle.cfg.contains("PROPERTY Conditional") {
      return .init(status: 255, stdout: "Unsupported temporal formula", stderr: "")
    }
    if unavailableBranch, request.bundle.tla.contains("__SwiftTLAObligationProperty == <>") {
      return .init(status: 255, stdout: "Unsupported obligation", stderr: "")
    }
    if violatedBranch, request.bundle.tla.contains("__SwiftTLAObligationProperty == []") {
      try numberedInitialStateTrace().write(to: request.traceOutput)
      return .init(status: 12, stdout: "Error: Invariant is violated.", stderr: "")
    }
    return .init(status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
  }
}
