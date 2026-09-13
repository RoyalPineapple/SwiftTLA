import Foundation

package struct RetainedFileLocation: Equatable, Sendable {
  package let role: String
  package let location: String

  package init(role: String, location: String) {
    self.role = role
    self.location = location
  }
}

package struct CapturedToolOutput: Equatable, Sendable {
  package let stream: String
  package let content: String

  package init(stream: String, content: String) {
    self.stream = stream
    self.content = content
  }
}

package struct CheckFailureReport: Equatable, Sendable {
  package let whatFailed: String
  package let whereItFailed: String
  package let expected: String
  package let actual: String
  package let nextSafeAction: String
  package let evidence: [RetainedFileLocation]
  package let toolOutput: [CapturedToolOutput]

  package init(
    whatFailed: String,
    whereItFailed: String,
    expected: String,
    actual: String,
    nextSafeAction: String,
    evidence: [RetainedFileLocation] = [],
    toolOutput: [CapturedToolOutput] = []
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

extension GraphDifference {
  package var failureReport: CheckFailureReport {
    switch self {
    case .observableNames(
      let tlcVariables,
      let swiftVariables,
      let tlcActions,
      let swiftActions
    ):
      return .init(
        whatFailed: "The observable names differ.",
        whereItFailed: "canonical variables or actions",
        expected: "TLC variables \(tlcVariables.sorted()); actions \(tlcActions.sorted()).",
        actual: "SwiftTLA variables \(swiftVariables.sorted()); actions \(swiftActions.sorted()).",
        nextSafeAction: "Make the compiled Swift and rendered TLC declarations use the same names."
      )
    case .initialStates(let tlc, let swift):
      return setDifferenceReport(
        what: "The initial-state sets differ.",
        where: "canonical initial states",
        expected: tlc,
        actual: swift,
        next: "Inspect the first differing state in tlc-graph.jsonl and swift-graph.jsonl, then compare the Init predicates."
      )
    case .states(let tlc, let swift):
      return setDifferenceReport(
        what: "The reachable-state sets differ.",
        where: "canonical state space",
        expected: tlc,
        actual: swift,
        next: "Inspect the first differing state in tlc-graph.jsonl and swift-graph.jsonl, then compare the action guards and assignments that can reach it."
      )
    case .edges(let tlc, let swift):
      return edgeDifferenceReport(expected: tlc, actual: swift)
    case .completion(let tlc, let swift):
      return .init(
        whatFailed: "Exploration is incomplete.", whereItFailed: "finite graph completion",
        expected: "Complete TLC and Swift graphs.",
        actual: "TLC complete: \(tlc); Swift complete: \(swift).",
        nextSafeAction: "Complete both explorations before comparing their property outcomes.")
    case .outcome(let tlc, let swift):
      return .init(
        whatFailed: tlc == swift ? "The verification outcome is inconclusive." : "The verification outcomes differ.",
        whereItFailed: "finite conformance outcome",
        expected: "TLC outcome: \(describe(tlc))",
        actual: "SwiftTLA outcome: \(describe(swift))",
        nextSafeAction: "Inspect tlc-graph.jsonl and swift-graph.jsonl outcomes and their retained traces before changing the model."
      )
    }
  }
}

extension GraphComparison {
  package var failureReports: [CheckFailureReport] {
    differences.map(\.failureReport)
  }
}

extension TLCProcessError {
  package func failureReport(for request: TLCProcessRequest) -> CheckFailureReport {
    let evidence = [
      RetainedFileLocation(role: "TLA+ module", location: request.moduleFileName),
      RetainedFileLocation(role: "TLC configuration", location: request.configurationFileName),
      RetainedFileLocation(role: "TLC graph event output", location: request.graphEvents.path)
    ]
    switch self {
    case .timedOut(let stdout, let stderr):
      return .init(
        whatFailed: "TLC did not finish before the configured time limit.",
        whereItFailed: "TLC invocation for case \(request.caseID)",
        expected: "TLC completes within \(request.timeout) seconds and writes a complete graph event stream.",
        actual: "The process exceeded \(request.timeout) seconds and was terminated.",
        nextSafeAction: "Inspect the retained stdout and stderr, then reduce the declared finite bounds or raise the case timeout deliberately.",
        evidence: evidence,
        toolOutput: [
          .init(stream: "stdout", content: redactingSecrets(in: stdout)),
          .init(stream: "stderr", content: redactingSecrets(in: stderr))
        ]
      )
    case .failedToStart(let message):
      return .init(
        whatFailed: "TLC could not start.",
        whereItFailed: "TLC invocation for case \(request.caseID)",
        expected: "The configured Java executable and TLC class path launch TLC.",
        actual: redactingSecrets(in: message),
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
      case .invalidDeclaredClosure(let failure):
        return .init(
          whatFailed: "The declared TLC module closure is invalid.",
          whereItFailed: "module bundle rooted at \(request.bundle.root.name)",
          expected: "One complete dependency graph rooted at \(request.bundle.root.name).",
          actual: failure.description,
          nextSafeAction: "Correct the declared module files or dependency edges, then rerun TLC.",
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

    }
  }
}

private func setDifferenceReport(
  what: String,
  where location: String,
  expected: Set<CanonicalStateKey>,
  actual: Set<CanonicalStateKey>,
  next: String
) -> CheckFailureReport {
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
  expected: Set<CanonicalEdge>, actual: Set<CanonicalEdge>
) -> CheckFailureReport {
  let witness = expected.symmetricDifference(actual).sorted().first
  guard let witness else {
    return .init(
      whatFailed: "The labeled transition relations differ.", whereItFailed: "canonical transition relation",
      expected: "TLC and SwiftTLA permit the same labeled transitions.",
      actual: "The transition sets differ, but no stable witness was available.",
      nextSafeAction: "Inspect the retained edges in tlc-graph.jsonl and swift-graph.jsonl."
    )
  }
  return .init(
    whatFailed: "The labeled transition relations differ.",
    whereItFailed: "action \(witness.action) from \(witness.source.canonicalEncoding) to \(witness.target.canonicalEncoding)",
    expected: expected.contains(witness) ? "TLC permits this transition." : "TLC does not permit this transition.",
    actual: actual.contains(witness) ? "SwiftTLA permits this transition." : "SwiftTLA does not permit this transition.",
    nextSafeAction: "Compare the \(witness.action) guard and update at the named source state in tlc-graph.jsonl and swift-graph.jsonl."
  )
}

private func describe(_ value: GraphRunOutcome) -> String {
  switch value {
  case .noViolation: "no violation found"
  case .invariantViolation(let message): "invariant violation: \(message)"
  case .temporalViolation(let property, let reason): "temporal violation: \(property) (\(reason.rawValue))"
  case .refinementViolation(let name): "refinement violation: \(name)"
  case .deadlock(let state): "deadlock at \(state.canonicalEncoding)"
  case .incomplete(let reason): "incomplete: \(reason)"
  case .executionError(let reason): "execution error: \(reason)"
  }
}
