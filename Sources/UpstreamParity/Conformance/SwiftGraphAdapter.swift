import SwiftTLA

public enum SwiftGraphAdapterErrorV1: Error, Equatable, Sendable {
  case declaredCaseMismatch(expected: String, actual: String)
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
}

public struct SwiftExplorationEvidenceV1 {
  public let caseID: String
  public let exploration: ModelExplorationResult

  public init(caseID: String, exploration: ModelExplorationResult) {
    self.caseID = caseID
    self.exploration = exploration
  }
}

public struct SwiftGraphAdapterV1: Sendable {
  public init() {}

  public func adapt(
    _ evidence: SwiftExplorationEvidenceV1,
    for declaredCase: CoreConformanceCaseV1
  ) throws -> CanonicalRunV1 {
    guard evidence.caseID == declaredCase.id else {
      throw SwiftGraphAdapterErrorV1.declaredCaseMismatch(
        expected: declaredCase.id,
        actual: evidence.caseID
      )
    }
    return try adapt(evidence.exploration)
  }

  public func adapt(_ exploration: ModelExplorationResult) throws -> CanonicalRunV1 {
    let states = Dictionary(
      uniqueKeysWithValues: exploration.graph.states.map { identifier, bindings in
        (identifier, CanonicalStateV1(bindings: bindings.mapValues(CanonicalValueV1.init)))
      })
    let initialStates = try exploration.initialStateIDs.map { identifier in
      guard let state = states[identifier] else {
        throw SwiftGraphAdapterErrorV1.initialStateMissing(identifier.id)
      }
      return state
    }
    let edges = try exploration.graph.transitions.flatMap { source, transitions in
      guard let sourceState = states[source] else {
        throw SwiftGraphAdapterErrorV1.transitionStateMissing(source.id)
      }
      return try transitions.map { transition in
        guard let targetState = states[transition.target] else {
          throw SwiftGraphAdapterErrorV1.transitionStateMissing(transition.target.id)
        }
        return CanonicalEdgeV1(
          source: sourceState.key,
          action: transition.action,
          target: targetState.key
        )
      }
    }
    let graph = try CanonicalGraphV1(
      initialStates: initialStates,
      states: Array(states.values),
      edges: edges
    )
    return try CanonicalRunV1(
      graph: graph,
      observableActions: Set(edges.map(\.action)),
      outcome: try canonicalOutcome(exploration.result, states: states),
      traces: try canonicalTraces(exploration.result, states: states)
    )
  }

  private func canonicalOutcome(
    _ result: CheckResult,
    states: [StateGraph.StateID: CanonicalStateV1]
  ) throws -> CanonicalOutcomeV1 {
    switch result.underlyingOutcome {
    case .ok:
      return .exhaustiveSuccess
    case .invariantViolated(let invariant, _, _):
      return .invariantViolation(invariant)
    case .deadlocked(let state):
      let canonical = CanonicalStateV1(bindings: state.mapValues(CanonicalValueV1.init))
      guard states.values.contains(canonical) else {
        throw SwiftGraphAdapterErrorV1.traceStateMissing
      }
      return .deadlock(canonical.key)
    case .depthExceeded:
      return .incomplete(reason: result.description)
    case .livenessViolated(let message):
      return .invariantViolation(message)
    case .error(let message):
      return .executionError(message)
    case .bounded:
      preconditionFailure("underlyingOutcome must unwrap bounded results")
    }
  }

  private func canonicalTraces(
    _ result: CheckResult,
    states: [StateGraph.StateID: CanonicalStateV1]
  ) throws -> [CanonicalTraceV1] {
    guard case .invariantViolated(_, _, let trace) = result.underlyingOutcome else { return [] }
    return [
      CanonicalTraceV1(
        id: "swift-invariant-trace",
        steps: try trace.map { step in
          let canonical = CanonicalStateV1(bindings: step.state.mapValues(CanonicalValueV1.init))
          guard states.values.contains(canonical) else {
            throw SwiftGraphAdapterErrorV1.traceStateMissing
          }
          return CanonicalTraceStepV1(state: canonical.key, action: step.action)
        }
      )
    ]
  }
}
