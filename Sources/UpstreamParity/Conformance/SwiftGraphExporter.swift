import SwiftTLA

package enum SwiftGraphExporterError: Error, Equatable, Sendable {
  case finiteGraphCaseMismatch(expected: String, actual: String)
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
  case invalidUnderlyingOutcome
}

package struct SwiftExplorationEvidence {
  package let caseID: String
  package let exploration: ModelExplorationResult

  package init(
    caseID: String,
    exploration: ModelExplorationResult
  ) {
    self.caseID = caseID
    self.exploration = exploration
  }
}

package struct SwiftGraphExporter: Sendable {
  package init() {}

  package func export(
    _ evidence: SwiftExplorationEvidence,
    for finiteGraphCase: FiniteGraphCase,
    actionNames: [String: String] = [:]
  ) throws -> CompletedGraphRun {
    guard evidence.caseID == finiteGraphCase.id else {
      throw SwiftGraphExporterError.finiteGraphCaseMismatch(
        expected: finiteGraphCase.id,
        actual: evidence.caseID
      )
    }
    return try export(
      evidence.exploration,
      actionNames: actionNames
    )
  }

  package func export(
    _ exploration: ModelExplorationResult,
    actionNames: [String: String] = [:]
  ) throws -> CompletedGraphRun {
    let states = Dictionary(
      uniqueKeysWithValues: try exploration.graph.states.map { identifier, projection in
        (identifier, try canonicalState(projection))
      })
    let initialStates = try exploration.initialStateIDs.map { identifier in
      guard let state = states[identifier] else {
        throw SwiftGraphExporterError.initialStateMissing(identifier.id)
      }
      return state
    }
    let edges = try exploration.graph.transitions.flatMap { source, transitions in
      guard let sourceState = states[source] else {
        throw SwiftGraphExporterError.transitionStateMissing(source.id)
      }
      return try transitions.map { transition in
        guard let targetState = states[transition.target] else {
          throw SwiftGraphExporterError.transitionStateMissing(transition.target.id)
        }
        return CanonicalEdge(
          source: sourceState.key,
          action: actionNames[transition.action] ?? transition.action,
          target: targetState.key
        )
      }
    }
    let graph = try CanonicalGraph(
      initialStates: initialStates,
      states: Array(states.values),
      edges: edges
    )
    return try CompletedGraphRun(
      graph: graph,
      observableActions: Set(edges.map(\.action)),
      outcome: try canonicalOutcome(
        exploration.result, states: states),
      traces: try canonicalTraces(
        exploration.result, states: states)
    )
  }

  private func canonicalState(
    _ projection: TLAStateProjection
  ) throws -> CanonicalState {
    var canonicalBindings: [String: CanonicalValue] = [:]
    for entry in projection.entries {
      let binding = entry.token.description
      let value = entry.value
      canonicalBindings[binding] = try CanonicalValue(value)
    }
    return CanonicalState(bindings: canonicalBindings)
  }

  private func canonicalOutcome(
    _ result: CheckResult,
    states: [StateGraph.StateID: CanonicalState]
  ) throws -> CanonicalOutcome {
    switch result.underlyingOutcome {
    case .ok:
      return .exhaustiveSuccess
    case .invariantViolated(let invariant, _, _):
      return .invariantViolation(invariant)
    case .deadlocked(let state):
      let canonical = try canonicalState(state)
      guard states.values.contains(canonical) else {
        throw SwiftGraphExporterError.traceStateMissing
      }
      return .deadlock(canonical.key)
    case .depthExceeded:
      return .incomplete(reason: result.description)
    case .livenessViolated(let message):
      return .invariantViolation(message)
    case .error(let message):
      return .executionError(message)
    case .refinementViolated(let refinement, _):
      return .invariantViolation(refinement)
    case .refinementUnproven:
      return .incomplete(reason: result.description)
    case .bounded:
      throw SwiftGraphExporterError.invalidUnderlyingOutcome
    }
  }

  private func canonicalTraces(
    _ result: CheckResult,
    states: [StateGraph.StateID: CanonicalState]
  ) throws -> [CanonicalTrace] {
    guard case .invariantViolated(_, _, let trace) = result.underlyingOutcome else { return [] }
    return [
      CanonicalTrace(
        id: "swift-invariant-trace",
        steps: try trace.map { step in
          let canonical = try canonicalState(step.state)
          guard states.values.contains(canonical) else {
            throw SwiftGraphExporterError.traceStateMissing
          }
          return CanonicalTraceStep(state: canonical.key, action: step.action)
        }
      )
    ]
  }

}
