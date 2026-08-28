import SwiftTLA

package enum SwiftGraphExporterError: Error, Equatable, Sendable {
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
}

package struct SwiftGraphExporter: Sendable {
  package init() {}

  package func export(
    _ exploration: ModelExplorationResult,
    for finiteGraphCase: FiniteGraphCase
  ) throws -> CompletedGraphRun {
    let renderedActionNames = Dictionary(uniqueKeysWithValues: finiteGraphCase.renderedActions.map {
      ($0.sourceInvocationName, $0.renderedName)
    })
    return try export(
      exploration,
      renderedActionNames: renderedActionNames
    )
  }

  package func export(
    _ exploration: ModelExplorationResult
  ) throws -> CompletedGraphRun {
    try export(exploration, renderedActionNames: [:])
  }

  private func export(
    _ exploration: ModelExplorationResult,
    renderedActionNames: [String: String]
  ) throws -> CompletedGraphRun {
    let states = try canonicalStates(exploration)
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
          action: renderedActionNames[transition.action] ?? transition.action,
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
      trace: try canonicalTrace(
        exploration.result, states: states)
    )
  }

  package func canonicalStates(
    _ exploration: ModelExplorationResult
  ) throws -> [StateGraph.StateID: CanonicalState] {
    try Dictionary(
      uniqueKeysWithValues: exploration.graph.states.map { identifier, projection in
        (identifier, try canonicalState(projection))
      })
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
    _ result: ModelCheckOutcome,
    states: [StateGraph.StateID: CanonicalState]
  ) throws -> GraphRunOutcome {
    switch result {
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
    case .noInitialStates:
      return .executionError("the compiled initial-state relation is empty")
    case .assumptionViolated:
      return .executionError("the compiled assumption evaluated to false")
    case .livenessViolated(let property, let reason, _):
      return .invariantViolation("\(property): \(reason.rawValue)")
    case .livenessUnavailable:
      return .incomplete(reason: result.description)
    case .refinementViolated(let refinement, _):
      return .invariantViolation(refinement)
    case .refinementUnproven:
      return .incomplete(reason: result.description)
    }
  }

  private func canonicalTrace(
    _ result: ModelCheckOutcome,
    states: [StateGraph.StateID: CanonicalState]
  ) throws -> GraphTrace? {
    guard case .invariantViolated(_, _, let trace) = result else { return nil }
    return GraphTrace(
      id: "swift-invariant-trace",
      steps: try trace.map { step in
        let canonical = try canonicalState(step.state)
        guard states.values.contains(canonical) else {
          throw SwiftGraphExporterError.traceStateMissing
        }
        return GraphTraceStep(state: canonical.key, action: step.action)
      }
    )
  }

}
