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
) throws -> (graph: GraphRun, result: TemporalPropertyResult, rendered: RenderedSpecification) {
  switch configuration.fairness {
  case .none:
    try exportTemporalRun(UnfairTemporalMatrix.initialMachines(),
      rendered: UnfairTemporalMatrix.spec.compile().render(),
      configuration: configuration, maximumStates: maximumStates)
  case .weak:
    try exportTemporalRun(WeaklyFairTemporalMatrix.initialMachines(),
      rendered: WeaklyFairTemporalMatrix.spec.compile().render(),
      configuration: configuration, maximumStates: maximumStates)
  case .strong:
    try exportTemporalRun(StronglyFairTemporalMatrix.initialMachines(),
      rendered: StronglyFairTemporalMatrix.spec.compile().render(),
      configuration: configuration, maximumStates: maximumStates)
  }
}

private func exportTemporalRun<Machine: StateMachine>(
  _ initialMachines: [Machine], rendered: RenderedSpecification,
  configuration: TemporalCaseConfiguration, maximumStates: Int
) throws -> (graph: GraphRun, result: TemporalPropertyResult, rendered: RenderedSpecification) {
  let native = try ReachabilityGraph(initialMachines: initialMachines, maximumStates: maximumStates)
  let property = configuration.property.renderedName
  guard native.safetyViolations.isEmpty, let analysis = native.temporalResults[property] else {
    throw EvidenceFormatError.invalidField(record: property, field: "native temporal checking")
  }
  let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
    ($0, try CanonicalState(native.formalProjection(of: $0)))
  })
  let canonical = try CanonicalGraph(native, states: states)
  var trace: GraphTrace?
  let result: TemporalPropertyResult
  switch analysis.status {
  case .satisfied: result = .satisfied
  case .unavailable: result = .unavailable
  case .violated:
    guard let witness = analysis.witness else {
      throw EvidenceFormatError.invalidField(record: property, field: "native temporal witness")
    }
    let lasso = try GraphTrace(id: "native-lasso", witness: witness, stateKey: { snapshot in
      guard let state = states[snapshot] else { throw CanonicalGraphError.missingNativeSnapshot }
      return state.key
    }, actionName: { try native.formalCall(for: $0).description })
    let cycleStart = witness.prefix.count - 1
    let stateIDs = lasso.steps.map { $0.state.canonicalEncoding }
    result = .violated(try TemporalLassoWitness(
      prefixStateIDs: Array(stateIDs[...cycleStart]),
      cycleStateIDs: Array(stateIDs[cycleStart...])))
    trace = lasso
  }
  // Property results are reported separately; the run owns and validates their trace.
  let graph = try GraphRun(isComplete: true, graph: canonical,
    observableActions: Set(canonical.edges.map(\.action)), outcome: .noViolation, trace: trace)
  return (graph, result, rendered)
}
