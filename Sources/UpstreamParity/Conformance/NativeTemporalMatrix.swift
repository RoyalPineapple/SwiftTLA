import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct UnfairTemporalMatrix {
  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar("x", initial: 0)
      let a = SwiftTLA.Action("A") { x.becomes(2).when(x == 0) }
      a
      SwiftTLA.Action("B") { x.becomes(1).when(x == 0) }
      SwiftTLA.Action("C") { x.becomes(0).when(x == 1) }
      SwiftTLA.Action("Stay") { x.becomes(2).when(x == 2) }

      Always("AlwaysP", x == 2)
      Eventually("EventuallyP", x == 2)
      AlwaysEventually("AlwaysEventuallyP", x == 2)
      EventuallyAlways("EventuallyAlwaysP", x == 2)
      LeadsTo("LeadsToPQ", x == 2, x == 1)
      LeadsTo("LeavesZero", x == 0, x != 0)
    }
  }
}

@TLAModel
private struct WeaklyFairTemporalMatrix {
  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar("x", initial: 0)
      let a = SwiftTLA.Action("A") { x.becomes(2).when(x == 0) }
      a
      SwiftTLA.Action("B") { x.becomes(1).when(x == 0) }
      SwiftTLA.Action("C") { x.becomes(0).when(x == 1) }
      SwiftTLA.Action("Stay") { x.becomes(2).when(x == 2) }
      WeakFairness(a)
      Always("AlwaysP", x == 2)
      Eventually("EventuallyP", x == 2)
      AlwaysEventually("AlwaysEventuallyP", x == 2)
      EventuallyAlways("EventuallyAlwaysP", x == 2)
      LeadsTo("LeadsToPQ", x == 2, x == 1)
      LeadsTo("LeavesZero", x == 0, x != 0)
    }
  }
}

@TLAModel
private struct StronglyFairTemporalMatrix {
  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar("x", initial: 0)
      let a = SwiftTLA.Action("A") { x.becomes(2).when(x == 0) }
      a
      SwiftTLA.Action("B") { x.becomes(1).when(x == 0) }
      SwiftTLA.Action("C") { x.becomes(0).when(x == 1) }
      SwiftTLA.Action("Stay") { x.becomes(2).when(x == 2) }
      StrongFairness(a)
      Always("AlwaysP", x == 2)
      Eventually("EventuallyP", x == 2)
      AlwaysEventually("AlwaysEventuallyP", x == 2)
      EventuallyAlways("EventuallyAlwaysP", x == 2)
      LeadsTo("LeadsToPQ", x == 2, x == 1)
      LeadsTo("LeavesZero", x == 0, x != 0)
    }
  }
}

package func temporalConformanceRun(
  configuration: TemporalCaseConfiguration, maximumStates: Int
) throws -> (graph: CompletedGraphRun, result: TemporalPropertyResult) {
  switch configuration.fairness {
  case .none:
    try exportTemporalRun(UnfairTemporalMatrix.initialMachines(), configuration: configuration, maximumStates: maximumStates)
  case .weak:
    try exportTemporalRun(WeaklyFairTemporalMatrix.initialMachines(), configuration: configuration, maximumStates: maximumStates)
  case .strong:
    try exportTemporalRun(StronglyFairTemporalMatrix.initialMachines(), configuration: configuration, maximumStates: maximumStates)
  }
}

private func exportTemporalRun<Machine: StateMachine>(
  _ initialMachines: [Machine], configuration: TemporalCaseConfiguration, maximumStates: Int
) throws -> (graph: CompletedGraphRun, result: TemporalPropertyResult) {
  let native = try ReachabilityGraph(initialMachines: initialMachines, maximumStates: maximumStates)
  let property = configuration.property.renderedName
  guard native.safetyViolations.isEmpty, let analysis = native.temporalResults[property] else {
    throw EvidenceFormatError.invalidField(record: property, field: "native temporal checking")
  }
  let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
    ($0, try CanonicalState(native.formalProjection(of: $0)))
  })
  let canonical = try CanonicalGraph(native, states: states)
  // This is the complete topology used by the separately reported property result.
  let graph = try CompletedGraphRun(graph: canonical,
    observableActions: Set(canonical.edgeOccurrences.keys.map(\.action)), outcome: .exhaustiveSuccess)
  let result: TemporalPropertyResult
  switch analysis.status {
  case .satisfied: result = .satisfied
  case .unavailable: result = .unavailable
  case .violated:
    guard let witness = analysis.witness else {
      throw EvidenceFormatError.invalidField(record: property, field: "native temporal witness")
    }
    func state(_ snapshot: Machine.Snapshot) throws -> CanonicalState {
      guard let state = states[snapshot] else { throw CanonicalGraphError.missingNativeSnapshot }
      return state
    }
    func edges(_ snapshots: [Machine.Snapshot], _ actions: [Machine.Action?]) throws -> [CanonicalEdge] {
      guard snapshots.count == actions.count + 1 else {
        throw EvidenceFormatError.invalidField(record: property, field: "native temporal path")
      }
      return try actions.enumerated().map { index, action in
        CanonicalEdge(source: try state(snapshots[index]).key,
          action: try action.map { try native.formalCall(for: $0).description } ?? "[stutter]",
          target: try state(snapshots[index + 1]).key)
      }
    }
    let prefix = try witness.prefix.map(state)
    let cycle = try witness.cycle.map(state)
    guard prefix.last == cycle.first,
      graph.containsTemporalTrace(states: prefix + cycle.dropFirst(),
        edges: try edges(witness.prefix, witness.prefixActions) + edges(witness.cycle, witness.cycleActions),
        implicitStutterActions: ["[stutter]"]) else {
      throw EvidenceFormatError.invalidField(record: property, field: "native temporal transitions")
    }
    result = .violated(try TemporalLassoWitness(
      prefixStateIDs: prefix.map { $0.key.canonicalEncoding },
      cycleStateIDs: cycle.map { $0.key.canonicalEncoding }))
  }
  return (graph, result)
}
