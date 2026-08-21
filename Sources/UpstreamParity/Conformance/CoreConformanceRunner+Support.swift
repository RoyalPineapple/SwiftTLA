import Foundation

struct Correlations {
  let swift: CoreConformanceCorrelation
  let tlc: CoreConformanceCorrelation
  let runner: CoreConformanceCorrelation
  init(caseID: String, runID: UUID) {
    swift = CoreConformanceCorrelation(caseID: caseID, runID: runID, engine: .swift)
    tlc = CoreConformanceCorrelation(caseID: caseID, runID: runID, engine: .tlc)
    runner = CoreConformanceCorrelation(caseID: caseID, runID: runID, engine: .runner)
  }
  subscript(engine: CoreConformanceEngine) -> CoreConformanceCorrelation {
    switch engine {
    case .swift: swift
    case .tlc: tlc
    case .runner: runner
    }
  }
  var json: [String: [String: String]] {
    [
      "swift": [
        "caseID": swift.caseID, "runID": swift.runID.uuidString.lowercased(),
        "engine": swift.engine.rawValue
      ],
      "tlc": [
        "caseID": tlc.caseID, "runID": tlc.runID.uuidString.lowercased(),
        "engine": tlc.engine.rawValue
      ],
      "runner": [
        "caseID": runner.caseID, "runID": runner.runID.uuidString.lowercased(),
        "engine": runner.engine.rawValue
      ]
    ]
  }
}
enum RunnerError: Error {
  case outputAlreadyExists
  case tlcCaseMismatch
  case stagingDirectoryUnavailable
}
func sanitized(_ value: String) -> String {
  let URLSanitized = value.replacing(#/(https?:\/\/)[^\/@\s]+@/#) {
    "\($0.output.1)<redacted>@"
  }
  return URLSanitized.replacing(
    #/(?im)\b([A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)|TOKEN|SECRET|PASSWORD|API_KEY)\s*[:=]\s*\S+/#
  ) {
    "\($0.output.1)=<redacted>"
  }
}
