import SwiftTLA

package enum SwiftGraphExporterError: Error, Equatable, Sendable {
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
}

package struct SwiftGraphExporter: Sendable {
  package init() {}

  package func export<Machine: StateMachine>(
    _ native: ReachabilityGraph<Machine>, for finiteGraphCase: FiniteGraphCase? = nil
  ) throws -> CompletedGraphRun {
    let renderedNames = Dictionary(uniqueKeysWithValues: (finiteGraphCase?.renderedActions ?? []).map {
      ($0.sourceInvocationName, $0.renderedName)
    })
    func actionName(_ action: Machine.Action) throws -> String {
      let invocation = try native.formalCall(for: action).description
      return renderedNames[invocation] ?? invocation
    }
    let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
      ($0, try CanonicalState(native.formalProjection(of: $0)))
    })
    let graph = try CanonicalGraph(native, states: states, renderedActionNames: renderedNames)
    let outcome: GraphRunOutcome
    var trace: GraphTrace?
    if let failure = native.safetyViolations.sorted(by: { states[$0.key]!.key < states[$1.key]!.key }).first,
       let violation = failure.value.first {
      outcome = switch violation {
      case .invariant(let name): .invariantViolation(name)
      case .deadlock: .deadlock(states[failure.key]!.key)
      }
      trace = GraphTrace(id: "native-safety-trace", steps: try native.trace(to: failure.key).map {
        GraphTraceStep(state: states[$0.state]!.key,
          action: try $0.action.map(actionName) ?? "Init")
      })
    } else if let failure = native.refinementFailures.sorted(by: { $0.key < $1.key }).first {
      outcome = .refinementViolation(failure.key)
      let steps: [(action: Machine.Action?, state: Machine.Snapshot)]?
      switch failure.value {
      case .initialState(let state): steps = try native.trace(to: state)
      case .fairness: steps = nil
      case .transition(let source, let action, let target):
        steps = try native.trace(to: source) + [(action, target)]
      }
      if let steps {
        trace = GraphTrace(id: "native-refinement-trace", steps: try steps.map {
          GraphTraceStep(state: states[$0.state]!.key, action: try $0.action.map(actionName) ?? "Init")
        })
      }
    } else if let failure = native.temporalResults.sorted(by: { $0.key < $1.key }).first(where: { $0.value.status != .satisfied }) {
      outcome = failure.value.status == .violated
        ? .temporalViolation(property: failure.key, reason: failure.value.reason)
        : .incomplete(reason: "\(failure.key): \(failure.value.reason.rawValue)")
    } else {
      outcome = .exhaustiveSuccess
    }
    return try CompletedGraphRun(graph: graph, observableActions: Set(graph.edges.map(\.action)),
      outcome: outcome, trace: trace)
  }

  package func export(
    _ exploration: FiniteExploration,
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
    _ exploration: FiniteExploration
  ) throws -> CompletedGraphRun {
    try export(exploration, renderedActionNames: [:])
  }

  private func export(
    _ exploration: FiniteExploration,
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
      return .exhaustiveSuccess
    case .invariantViolated(let invariant, _, _):
      return .invariantViolation(invariant)
    case .deadlocked(let state):
      let canonical = try CanonicalState(state)
      guard states.values.contains(canonical) else {
        throw SwiftGraphExporterError.traceStateMissing
      }
      return .deadlock(canonical.key)
    case .depthExceeded:
      return .incomplete(reason: outcome.description)
    case .noInitialStates:
      return .executionError("the compiled initial-state relation is empty")
    case .assumptionViolated:
      return .executionError("the compiled assumption evaluated to false")
    case .livenessViolated(let property, let reason, _):
      return .temporalViolation(property: property, reason: reason)
    case .livenessUnavailable:
      return .incomplete(reason: outcome.description)
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
    guard case .invariantViolated(_, _, let trace) = outcome else { return nil }
    return GraphTrace(
      id: "swift-invariant-trace",
      steps: try trace.map { step in
        let canonical = try CanonicalState(step.state)
        return GraphTraceStep(state: canonical.key, action: renderedActionNames[step.action] ?? step.action)
      }
    )
  }

}
