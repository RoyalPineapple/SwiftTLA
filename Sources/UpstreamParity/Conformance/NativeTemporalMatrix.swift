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

package struct TemporalModelRun: Sendable {
  package let rendered: RenderedSpecification
  package let properties: [String: (graph: GraphRun, result: TemporalPropertyResult)]
}

package func temporalConformanceRun(
  fairness: TemporalFairnessMode, maximumStates: Int
) throws -> TemporalModelRun {
  switch fairness {
  case .none:
    try exportTemporalRun(UnfairTemporalMatrix.initialMachines(),
      compilation: UnfairTemporalMatrix.spec.compile(),
      maximumStates: maximumStates)
  case .weak:
    try exportTemporalRun(WeaklyFairTemporalMatrix.initialMachines(),
      compilation: WeaklyFairTemporalMatrix.spec.compile(),
      maximumStates: maximumStates)
  case .strong:
    try exportTemporalRun(StronglyFairTemporalMatrix.initialMachines(),
      compilation: StronglyFairTemporalMatrix.spec.compile(),
      maximumStates: maximumStates)
  }
}

private func exportTemporalRun<Machine: StateMachine>(
  _ initialMachines: [Machine], compilation: CompiledSpecification, maximumStates: Int
) throws -> TemporalModelRun {
  let native = try ReachabilityGraph(initialMachines: initialMachines, maximumStates: maximumStates)
  let declaredProperties = Set(compilation.description.temporalProperties)
  guard !declaredProperties.isEmpty, declaredProperties == Set(native.temporalResults.keys),
        native.safetyViolations.isEmpty else {
    throw EvidenceFormatError.invalidField(record: compilation.description.name, field: "native temporal checking")
  }
  let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
    ($0, try CanonicalState(native.formalProjection(of: $0)))
  })
  let canonical = try CanonicalGraph(native, states: states)
  let observableActions = Set(canonical.edges.map(\.action))
  let properties = try Dictionary(uniqueKeysWithValues: native.temporalResults.map { property, analysis in
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
      result = .violated(lasso)
      trace = lasso
    }
    // Property results are reported separately; the run owns and validates their trace.
    let graph = try GraphRun(isComplete: true, graph: canonical,
      observableActions: observableActions, outcome: .noViolation, trace: trace)
    return (property, (graph: graph, result: result))
  })
  return TemporalModelRun(rendered: try compilation.render(), properties: properties)
}
