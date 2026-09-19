import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct UnfairTemporalMatrix {
  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar(initial: 0)
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
      let x = scope.sharedVar(initial: 0)
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
      let x = scope.sharedVar(initial: 0)
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
  fairness: TemporalFairnessMode, maximumStates: Int
) throws -> NativeModelRun {
  switch fairness {
  case .none:
    try exportTemporalRun(UnfairTemporalMatrix.initialMachines(),
      rendered: UnfairTemporalMatrix.render(),
      maximumStates: maximumStates)
  case .weak:
    try exportTemporalRun(WeaklyFairTemporalMatrix.initialMachines(),
      rendered: WeaklyFairTemporalMatrix.render(),
      maximumStates: maximumStates)
  case .strong:
    try exportTemporalRun(StronglyFairTemporalMatrix.initialMachines(),
      rendered: StronglyFairTemporalMatrix.render(),
      maximumStates: maximumStates)
  }
}

private func exportTemporalRun<Machine: StateMachine>(
  _ initialMachines: [Machine], rendered: RenderedSpecification, maximumStates: Int
) throws -> NativeModelRun {
  try NativeModelRun(ReachabilityGraph(initialMachines: initialMachines, maximumStates: maximumStates),
    rendered: rendered)
}
