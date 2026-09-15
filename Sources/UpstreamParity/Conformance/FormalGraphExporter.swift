import SwiftTLA

package enum FormalGraphExportError: Error, Equatable, Sendable {
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
}

package struct FormalGraphExporter: Sendable {
  package init() {}

  package func export(
    _ exploration: FiniteExploration,
    for finiteGraphCase: FiniteGraphCase
  ) throws -> GraphRun {
    let renderedActionNames = Dictionary(uniqueKeysWithValues: finiteGraphCase.renderedActions.map {
      ($0.sourceInvocationName, $0.renderedName)
    })
    return try export(
      exploration,
      renderedActionNames: renderedActionNames
    )
  }

  package func export(
    _ exploration: FiniteExploration
  ) throws -> GraphRun {
    try export(exploration, renderedActionNames: [:])
  }

  private func export(
    _ exploration: FiniteExploration,
    renderedActionNames: [String: String]
  ) throws -> GraphRun {
    let states = try canonicalStates(exploration)
    let initialStates = try exploration.initialStateIDs.map { identifier in
      guard let state = states[identifier] else {
        throw FormalGraphExportError.initialStateMissing(identifier.id)
      }
      return state
    }
    let edges = try exploration.graph.transitions.flatMap { source, transitions in
      guard let sourceState = states[source] else {
        throw FormalGraphExportError.transitionStateMissing(source.id)
      }
      return try transitions.map { transition in
        guard let targetState = states[transition.target] else {
          throw FormalGraphExportError.transitionStateMissing(transition.target.id)
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
    return try GraphRun(
      isComplete: exploration.isComplete,
      graph: graph,
      observableActions: Set(edges.map(\.action)),
      outcome: try canonicalOutcome(
        exploration.outcome, states: states),
      trace: try canonicalTrace(
        exploration.outcome, renderedActionNames: renderedActionNames)
    )
  }

  package func canonicalStates(
    _ exploration: FiniteExploration
  ) throws -> [StateGraph.StateID: CanonicalState] {
    try Dictionary(
      uniqueKeysWithValues: exploration.graph.states.map { identifier, projection in
        (identifier, try CanonicalState(projection))
      })
  }

  private func canonicalOutcome(
    _ outcome: ModelCheckOutcome,
    states: [StateGraph.StateID: CanonicalState]
  ) throws -> GraphRunOutcome {
    switch outcome {
    case .ok:
      return .noViolation
    case .invariantViolated(let invariant, _, _):
      return .invariantViolation(invariant)
    case .deadlocked(let state):
      let canonical = try CanonicalState(state)
      guard states.values.contains(canonical) else {
        throw FormalGraphExportError.traceStateMissing
      }
      return .deadlock(canonical.key)
    case .depthExceeded:
      return .incomplete(reason: outcome.description)
    case .noInitialStates:
      return .executionError("the compiled initial-state relation is empty")
    case .assumptionViolated:
      return .executionError("the compiled assumption evaluated to false")
    case .refinementViolated(let refinement, _):
      return .refinementViolation(refinement)
    case .refinementUnproven:
      return .incomplete(reason: outcome.description)
    }
  }

  private func canonicalTrace(
    _ outcome: ModelCheckOutcome,
    renderedActionNames: [String: String]
  ) throws -> GraphTrace? {
    switch outcome {
    case .invariantViolated(_, _, let trace):
      return GraphTrace(
        id: "swift-invariant-trace",
        steps: try trace.enumerated().map { index, step in
          let canonical = try CanonicalState(step.state)
          return GraphTraceStep(state: canonical.key,
            action: index == 0 ? nil : renderedActionNames[step.action] ?? step.action)
        })
    default:
      return nil
    }
  }
}
