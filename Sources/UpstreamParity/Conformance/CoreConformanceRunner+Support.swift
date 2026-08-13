import Foundation

struct Correlations {
  let swift: CoreConformanceCorrelationV1
  let tlc: CoreConformanceCorrelationV1
  let runner: CoreConformanceCorrelationV1
  init(caseID: String, runID: UUID) {
    swift = CoreConformanceCorrelationV1(caseID: caseID, runID: runID, engine: .swift)
    tlc = CoreConformanceCorrelationV1(caseID: caseID, runID: runID, engine: .tlc)
    runner = CoreConformanceCorrelationV1(caseID: caseID, runID: runID, engine: .runner)
  }
  subscript(engine: CoreConformanceEngineV1) -> CoreConformanceCorrelationV1 {
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
enum TLCInvocationPhaseV1: String, Hashable {
  case primary
  case trace
  case replay
  var stdoutLog: String {
    switch self {
    case .primary: "tlc.stdout.log"
    case .trace, .replay: "tlc.\(rawValue).stdout.log"
    }
  }
  var stderrLog: String {
    switch self {
    case .primary: "tlc.stderr.log"
    case .trace, .replay: "tlc.\(rawValue).stderr.log"
    }
  }
}
enum RunnerError: Error {
  case outputAlreadyExists
  case tlcCaseMismatch
  case tlcRunMismatch(expected: UUID, actual: UUID)
  case stagingDirectoryUnavailable
}
func sanitized(_ value: String) -> String {
  let credentialURL = try! NSRegularExpression(
    pattern: #"(https?://)[^/@\s]+@"#, options: [.caseInsensitive])
  let secretAssignment = try! NSRegularExpression(
    pattern:
      #"(?im)\b([A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)|TOKEN|SECRET|PASSWORD|API_KEY)\s*[:=]\s*\S+"#
  )
  let range = NSRange(value.startIndex..., in: value)
  let URLSanitized = credentialURL.stringByReplacingMatches(
    in: value, options: [], range: range, withTemplate: "$1<redacted>@"
  )
  let sanitizedRange = NSRange(URLSanitized.startIndex..., in: URLSanitized)
  return secretAssignment.stringByReplacingMatches(
    in: URLSanitized, options: [], range: sanitizedRange, withTemplate: "$1=<redacted>"
  )
}
