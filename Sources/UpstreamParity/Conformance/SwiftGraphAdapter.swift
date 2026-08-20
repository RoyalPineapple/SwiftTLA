import SwiftTLA

public enum SwiftGraphAdapterError: Error, Equatable, Sendable {
  case declaredCaseMismatch(expected: String, actual: String)
  case initialStateMissing(Int)
  case transitionStateMissing(Int)
  case traceStateMissing
  case invalidValueNormalization(binding: String)
}

public struct SwiftExplorationEvidence {
  public let caseID: String
  public let exploration: ModelExplorationResult

  public init(caseID: String, exploration: ModelExplorationResult) {
    self.caseID = caseID
    self.exploration = exploration
  }
}

public struct SwiftGraphAdapter: Sendable {
  public init() {}

  public func adapt(
    _ evidence: SwiftExplorationEvidence,
    for declaredCase: CoreConformanceCase,
    actionNames: [String: String] = [:]
  ) throws -> CanonicalRun {
    guard evidence.caseID == declaredCase.id else {
      throw SwiftGraphAdapterError.declaredCaseMismatch(
        expected: declaredCase.id,
        actual: evidence.caseID
      )
    }
    return try adapt(
      evidence.exploration,
      actionNames: actionNames,
      valueNormalizations: declaredCase.valueNormalizations
    )
  }

  public func adapt(
    _ exploration: ModelExplorationResult,
    actionNames: [String: String] = [:],
    valueNormalizations: [CoreConformanceValueNormalization] = []
  ) throws -> CanonicalRun {
    let normalizations = Dictionary(
      uniqueKeysWithValues: valueNormalizations.map { ($0.binding, $0) }
    )
    let states = Dictionary(
      uniqueKeysWithValues: try exploration.graph.states.map { identifier, bindings in
        (identifier, try canonicalState(bindings, normalizations: normalizations))
      })
    let initialStates = try exploration.initialStateIDs.map { identifier in
      guard let state = states[identifier] else {
        throw SwiftGraphAdapterError.initialStateMissing(identifier.id)
      }
      return state
    }
    let edges = try exploration.graph.transitions.flatMap { source, transitions in
      guard let sourceState = states[source] else {
        throw SwiftGraphAdapterError.transitionStateMissing(source.id)
      }
      return try transitions.map { transition in
        guard let targetState = states[transition.target] else {
          throw SwiftGraphAdapterError.transitionStateMissing(transition.target.id)
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
    return try CanonicalRun(
      graph: graph,
      observableActions: Set(edges.map(\.action)),
      outcome: try canonicalOutcome(
        exploration.result, states: states, normalizations: normalizations),
      traces: try canonicalTraces(
        exploration.result, states: states, normalizations: normalizations)
    )
  }

  private func canonicalState(
    _ bindings: [String: TLAValue],
    normalizations: [String: CoreConformanceValueNormalization]
  ) throws -> CanonicalState {
    var canonicalBindings: [String: CanonicalValue] = [:]
    for (binding, value) in bindings {
      let canonical = CanonicalValue(value)
      canonicalBindings[binding] =
        try normalizations[binding].map {
          try normalize(canonical, using: $0)
        } ?? canonical
    }
    return CanonicalState(bindings: canonicalBindings)
  }

  private func canonicalOutcome(
    _ result: CheckResult,
    states: [StateGraph.StateID: CanonicalState],
    normalizations: [String: CoreConformanceValueNormalization]
  ) throws -> CanonicalOutcome {
    switch result.underlyingOutcome {
    case .ok:
      return .exhaustiveSuccess
    case .invariantViolated(let invariant, _, _):
      return .invariantViolation(invariant)
    case .deadlocked(let state):
      let canonical = try canonicalState(state, normalizations: normalizations)
      guard states.values.contains(canonical) else {
        throw SwiftGraphAdapterError.traceStateMissing
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
    states: [StateGraph.StateID: CanonicalState],
    normalizations: [String: CoreConformanceValueNormalization]
  ) throws -> [CanonicalTrace] {
    guard case .invariantViolated(_, _, let trace) = result.underlyingOutcome else { return [] }
    return [
      CanonicalTrace(
        id: "swift-invariant-trace",
        steps: try trace.map { step in
          let canonical = try canonicalState(step.state, normalizations: normalizations)
          guard states.values.contains(canonical) else {
            throw SwiftGraphAdapterError.traceStateMissing
          }
          return CanonicalTraceStep(state: canonical.key, action: step.action)
        }
      )
    ]
  }

  private func normalize(
    _ value: CanonicalValue,
    using normalization: CoreConformanceValueNormalization
  ) throws -> CanonicalValue {
    var fields: [String: CanonicalValue] = [:]
    switch value {
    case .orderedFunction(let entries):
      for entry in entries {
        guard
          let field = normalization.functionKeys.first(where: {
            (try? TLCValueParser.parse($0.key)) == entry.key
          })?.value, fields[field] == nil
        else {
          throw SwiftGraphAdapterError.invalidValueNormalization(binding: normalization.binding)
        }
        fields[field] = entry.value
      }
    case .orderedRecord(let entries):
      for entry in entries {
        guard normalization.functionKeys.values.contains(entry.name), fields[entry.name] == nil
        else {
          throw SwiftGraphAdapterError.invalidValueNormalization(binding: normalization.binding)
        }
        fields[entry.name] = entry.value
      }
    default:
      throw SwiftGraphAdapterError.invalidValueNormalization(binding: normalization.binding)
    }
    guard fields.count == normalization.functionKeys.count else {
      throw SwiftGraphAdapterError.invalidValueNormalization(binding: normalization.binding)
    }
    return .record(fields)
  }
}
