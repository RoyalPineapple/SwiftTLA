import Foundation

/// A retained input or output that explains a conformance decision.
///
/// `location` identifies the recorded module, configuration, graph, or log.
public struct ConformanceEvidenceLocation: Equatable, Sendable {
  public let role: String
  public let location: String

  public init(role: String, location: String) {
    self.role = role
    self.location = location
  }
}

/// Captured tool output retained with a failure report.
public struct ConformanceToolOutput: Equatable, Sendable {
  public let stream: String
  public let content: String

  public init(stream: String, content: String) {
    self.stream = stream
    self.content = content
  }
}

/// A diagnostic that answers the next useful investigation question.
///
/// The fields let a UI present the diagnostic and retained evidence directly.
public struct ConformanceFailureReport: Equatable, Sendable {
  public let whatFailed: String
  public let whereItFailed: String
  public let expected: String
  public let actual: String
  public let nextSafeAction: String
  public let evidence: [ConformanceEvidenceLocation]
  public let toolOutput: [ConformanceToolOutput]

  public init(
    whatFailed: String,
    whereItFailed: String,
    expected: String,
    actual: String,
    nextSafeAction: String,
    evidence: [ConformanceEvidenceLocation] = [],
    toolOutput: [ConformanceToolOutput] = []
  ) {
    self.whatFailed = whatFailed
    self.whereItFailed = whereItFailed
    self.expected = expected
    self.actual = actual
    self.nextSafeAction = nextSafeAction
    self.evidence = evidence
    self.toolOutput = toolOutput
  }
}

extension ConformanceDifference {
  /// A concrete explanation of this exact graph difference.
  ///
  /// In core conformance, `expected` is TLC and `actual` is SwiftTLA.
  /// `tlc-run.json` and `swift-run.json` contain the complete graph records.
  public var failureReport: ConformanceFailureReport {
    switch self {
    case .mapping(let messages):
      return .init(
        whatFailed: "The declared observable-name mapping is not a total bijection.",
        whereItFailed: "observable variable or action mapping",
        expected: "Every TLC observable name maps to exactly one SwiftTLA name, and vice versa.",
        actual: messages.joined(separator: "; "),
        nextSafeAction: "Correct the declared mapping, then rerun the finite TLC comparison."
      )
    case .initialStates(let expected, let actual):
      return setDifferenceReport(
        what: "The initial-state sets differ.",
        where: "canonical initial states",
        expected: expected,
        actual: actual,
        next: "Inspect the first differing state in tlc-run.json and swift-run.json, then compare the Init predicates."
      )
    case .states(let expected, let actual):
      return setDifferenceReport(
        what: "The reachable-state sets differ.",
        where: "canonical state space",
        expected: expected,
        actual: actual,
        next: "Inspect the first differing state in tlc-run.json and swift-run.json, then compare the action guards and assignments that can reach it."
      )
    case .edges(let expected, let actual):
      return edgeDifferenceReport(expected: expected, actual: actual)
    case .observations(let expected, let actual):
      return observationDifferenceReport(expected: expected, actual: actual)
    case .outcome(let expected, let actual):
      return .init(
        whatFailed: "The verification outcomes differ.",
        whereItFailed: "finite conformance outcome",
        expected: "TLC outcome: \(describe(expected))",
        actual: "SwiftTLA outcome: \(describe(actual))",
        nextSafeAction: "Inspect tlc-run.json and swift-run.json outcomes and their retained traces before changing the model."
      )
    case .errors(let expected, let actual):
      return .init(
        whatFailed: "The retained verification diagnostics differ.",
        whereItFailed: "canonical diagnostic list",
        expected: describe(expected),
        actual: describe(actual),
        nextSafeAction: "Inspect the named diagnostic and its source input before changing the model."
      )
    case .traces(let expected, let actual):
      return .init(
        whatFailed: "The retained counterexample traces differ.",
        whereItFailed: "canonical trace evidence",
        expected: describe(expected),
        actual: describe(actual),
        nextSafeAction: "Inspect the first differing trace step in tlc-run.json and swift-run.json before changing the model."
      )
    }
  }
}

extension ExactFiniteTLCComparison {
  /// One actionable report per detected difference, in comparison order.
  public var failureReports: [ConformanceFailureReport] {
    differences.map(\.failureReport)
  }
}

extension TLCProcessError {
  /// A structured tool failure with source inputs and any captured output.
  public func failureReport(for request: TLCProcessRequest) -> ConformanceFailureReport {
    let evidence = [
      ConformanceEvidenceLocation(role: "TLA+ module", location: request.moduleFileName),
      ConformanceEvidenceLocation(role: "TLC configuration", location: request.configurationFileName),
      ConformanceEvidenceLocation(role: "TLC graph event output", location: request.graphEvents.path)
    ]
    switch self {
    case .timedOut(let stdout, let stderr):
      return .init(
        whatFailed: "TLC did not finish before the configured time limit.",
        whereItFailed: "TLC primary invocation for case \(request.caseID)",
        expected: "TLC completes within \(request.timeout) seconds and writes a complete graph event stream.",
        actual: "The process exceeded \(request.timeout) seconds and was terminated.",
        nextSafeAction: "Inspect the retained stdout and stderr, then reduce the declared finite bounds or raise the case timeout deliberately.",
        evidence: evidence,
        toolOutput: [.init(stream: "stdout", content: sanitized(stdout)), .init(stream: "stderr", content: sanitized(stderr))]
      )
    case .failedToStart(let message):
      return .init(
        whatFailed: "TLC could not start.",
        whereItFailed: "TLC primary invocation for case \(request.caseID)",
        expected: "The configured Java executable and TLC class path launch TLC.",
        actual: sanitized(message),
        nextSafeAction: "Verify the Java executable, TLC JAR, bridge classes, and working directory in the retained invocation snapshot.",
        evidence: evidence
      )
    case .invalidModuleBundle(let error):
      switch error {
      case .unreadableModule(let path, let reason):
        return .init(
          whatFailed: "The emitted TLC module could not be read.",
          whereItFailed: "module bundle source \(path)",
          expected: "The emitted .tla source is readable as UTF-8 before TLC starts.",
          actual: reason,
          nextSafeAction: "Check the emitted module file permissions and encoding, then write a fresh bundle before retrying.",
          evidence: evidence
        )
      case .missingImportedModule(let module, let importedBy, let line, let expectedFile):
        return .init(
          whatFailed: "The emitted module bundle is missing an imported formal module.",
          whereItFailed: "\(importedBy):\(line), which imports \(module)",
          expected: "\(module).tla exists beside the root module at \(expectedFile).",
          actual: "The emitted bundle has no \(module).tla file.",
          nextSafeAction: "Emit \(module).tla with its transitive imports beside the root module, then rerun TLC.",
          evidence: evidence + [.init(role: "missing imported module", location: expectedFile)]
        )
      }
    case .requiredReplayFailed(let completed, let failed):
      return processFailureReport(
        what: "TLC replay did not reproduce the required trace.", phase: "replay", request: request,
        expected: "The replay exits with the same violation status as the captured primary run.",
        actual: "Primary status \(completed.primary.status); replay status \(failed.status).",
        outputs: failed
      )
    case .traceCaptureFailed(let completed, let failed):
      return processFailureReport(
        what: "TLC did not capture the required trace.", phase: "trace capture", request: request,
        expected: "The trace-capture invocation exits with the primary violation status \(completed.primary.status).",
        actual: "Trace-capture status \(failed.status).", outputs: failed
      )
    case .requiredReplayExecutionFailed(let completed, let error):
      return executionFailureReport(
        what: "TLC replay could not execute.", phase: "replay", request: request,
        expected: "The replay launches after primary status \(completed.primary.status).", error: error
      )
    case .traceCaptureExecutionFailed(let completed, let error):
      return executionFailureReport(
        what: "TLC trace capture could not execute.", phase: "trace capture", request: request,
        expected: "The trace capture launches after primary status \(completed.primary.status).", error: error
      )
    }
  }
}

private func setDifferenceReport(
  what: String,
  where location: String,
  expected: Set<CanonicalStateKey>,
  actual: Set<CanonicalStateKey>,
  next: String
) -> ConformanceFailureReport {
  let onlyExpected = expected.subtracting(actual).sorted().first
  let onlyActual = actual.subtracting(expected).sorted().first
  return .init(
    whatFailed: what,
    whereItFailed: location,
    expected: onlyExpected.map { "TLC includes \($0.canonicalEncoding)." } ?? "TLC has no additional state at the first difference.",
    actual: onlyActual.map { "SwiftTLA includes \($0.canonicalEncoding)." } ?? "SwiftTLA has no additional state at the first difference.",
    nextSafeAction: next
  )
}

private func edgeDifferenceReport(
  expected: [CanonicalEdge: Int], actual: [CanonicalEdge: Int]
) -> ConformanceFailureReport {
  let witness = Set(expected.keys).union(actual.keys).sorted().first { expected[$0, default: 0] != actual[$0, default: 0] }
  guard let witness else {
    return .init(
      whatFailed: "The labeled transition multisets differ.", whereItFailed: "canonical transition relation",
      expected: "TLC and SwiftTLA retain the same transition occurrences.",
      actual: "The occurrence counts differ, but no stable witness was available.",
      nextSafeAction: "Inspect the retained edges in tlc-run.json and swift-run.json."
    )
  }
  return .init(
    whatFailed: "The labeled transition multisets differ.",
    whereItFailed: "action \(witness.action) from \(witness.source.canonicalEncoding) to \(witness.target.canonicalEncoding)",
    expected: "TLC permits this transition \(expected[witness, default: 0]) time(s).",
    actual: "SwiftTLA permits this transition \(actual[witness, default: 0]) time(s).",
    nextSafeAction: "Compare the \(witness.action) guard and update at the named source state in tlc-run.json and swift-run.json."
  )
}

private func observationDifferenceReport(
  expected: [CanonicalStateKey: CanonicalStateObservation],
  actual: [CanonicalStateKey: CanonicalStateObservation]
) -> ConformanceFailureReport {
  let witness = Set(expected.keys).union(actual.keys).sorted().first { expected[$0] != actual[$0] }
  let expectedObservation = witness.flatMap { expected[$0] }
  let actualObservation = witness.flatMap { actual[$0] }
  return .init(
    whatFailed: "The enabled-action observation differs.",
    whereItFailed: witness.map { "canonical state \($0.canonicalEncoding)" } ?? "canonical state observations",
    expected: describe(expectedObservation),
    actual: describe(actualObservation),
    nextSafeAction: "Compare the enabled action guards at the named state in tlc-run.json and swift-run.json."
  )
}

private func processFailureReport(
  what: String, phase: String, request: TLCProcessRequest, expected: String, actual: String,
  outputs: TLCProcessResult
) -> ConformanceFailureReport {
  .init(
    whatFailed: what, whereItFailed: "TLC \(phase) invocation for case \(request.caseID)",
    expected: expected, actual: actual,
    nextSafeAction: "Inspect the retained TLC \(phase) stdout and stderr, then correct the trace configuration or the emitted module bundle.",
    evidence: toolEvidence(for: request),
    toolOutput: [.init(stream: "stdout", content: sanitized(outputs.stdout)), .init(stream: "stderr", content: sanitized(outputs.stderr))]
  )
}

private func executionFailureReport(
  what: String, phase: String, request: TLCProcessRequest, expected: String,
  error: TLCProcessExecutionFailure
) -> ConformanceFailureReport {
  .init(
    whatFailed: what, whereItFailed: "TLC \(phase) invocation for case \(request.caseID)",
    expected: expected, actual: sanitized(error.message),
    nextSafeAction: "Inspect the retained invocation snapshot and TLC output before retrying.",
    evidence: toolEvidence(for: request),
    toolOutput: [
      error.partialStdout.map { .init(stream: "stdout", content: sanitized($0)) },
      error.partialStderr.map { .init(stream: "stderr", content: sanitized($0)) }
    ].compactMap { $0 }
  )
}

private func toolEvidence(for request: TLCProcessRequest) -> [ConformanceEvidenceLocation] {
  [
    .init(role: "TLA+ module", location: request.moduleFileName),
    .init(role: "TLC configuration", location: request.configurationFileName),
    .init(role: "TLC graph event output", location: request.graphEvents.path)
  ]
}

private func describe(_ value: CanonicalOutcome) -> String {
  switch value {
  case .exhaustiveSuccess: "exhaustive success"
  case .invariantViolation(let message): "invariant violation: \(message)"
  case .deadlock(let state): "deadlock at \(state.canonicalEncoding)"
  case .incomplete(let reason): "incomplete: \(reason)"
  case .executionError(let reason): "execution error: \(reason)"
  }
}

private func describe(_ observation: CanonicalStateObservation?) -> String {
  guard let observation else { return "no observation retained" }
  return "enabled actions \(observation.enabledActions.sorted()); terminal \(observation.isTerminal)."
}

private func describe(_ diagnostics: [CanonicalDiagnostic]) -> String {
  diagnostics.isEmpty ? "no diagnostics" : diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "; ")
}

private func describe(_ traces: [CanonicalTrace]) -> String {
  guard let trace = traces.first else { return "no traces" }
  let first = trace.steps.first
  return first.map { "trace \(trace.id) begins at \($0.state.canonicalEncoding) via \($0.action)" }
    ?? "trace \(trace.id) has no steps"
}
