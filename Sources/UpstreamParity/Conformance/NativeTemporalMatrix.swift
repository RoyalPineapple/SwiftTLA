import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct UnfairTemporalMatrix {
  enum Step: String, CaseIterable { case A, B, C, Stay }

  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar(initial: 0)
      let a = Do(Step.A, when: x == 0) { Assign(x, to: 2) }
      a
      Do(Step.B, when: x == 0) { Assign(x, to: 1) }
      Do(Step.C, when: x == 1) { Assign(x, to: 0) }
      Do(Step.Stay, when: x == 2) { Assign(x, to: 2) }

      let AlwaysP = Always()
      let EventuallyP = Eventually()
      let AlwaysEventuallyP = AlwaysEventually()
      let EventuallyAlwaysP = EventuallyAlways()
      let LeadsToPQ = LeadsTo()
      let LeavesZero = LeadsTo()
      AlwaysP(x == 2)
      EventuallyP(x == 2)
      AlwaysEventuallyP(x == 2)
      EventuallyAlwaysP(x == 2)
      LeadsToPQ(x == 2, x == 1)
      LeavesZero(x == 0, x != 0)
    }
  }
}

@TLAModel
private struct WeaklyFairTemporalMatrix {
  enum Step: String, CaseIterable { case A, B, C, Stay }

  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar(initial: 0)
      let a = Do(Step.A, when: x == 0) { Assign(x, to: 2) }
      a
      Do(Step.B, when: x == 0) { Assign(x, to: 1) }
      Do(Step.C, when: x == 1) { Assign(x, to: 0) }
      Do(Step.Stay, when: x == 2) { Assign(x, to: 2) }
      WeakFairness(a)
      let AlwaysP = Always()
      let EventuallyP = Eventually()
      let AlwaysEventuallyP = AlwaysEventually()
      let EventuallyAlwaysP = EventuallyAlways()
      let LeadsToPQ = LeadsTo()
      let LeavesZero = LeadsTo()
      AlwaysP(x == 2)
      EventuallyP(x == 2)
      AlwaysEventuallyP(x == 2)
      EventuallyAlwaysP(x == 2)
      LeadsToPQ(x == 2, x == 1)
      LeavesZero(x == 0, x != 0)
    }
  }
}

@TLAModel
private struct StronglyFairTemporalMatrix {
  enum Step: String, CaseIterable { case A, B, C, Stay }

  static var spec: TLASpec {
    #spec("TemporalMatrix") { scope in
      let x = scope.sharedVar(initial: 0)
      let a = Do(Step.A, when: x == 0) { Assign(x, to: 2) }
      a
      Do(Step.B, when: x == 0) { Assign(x, to: 1) }
      Do(Step.C, when: x == 1) { Assign(x, to: 0) }
      Do(Step.Stay, when: x == 2) { Assign(x, to: 2) }
      StrongFairness(a)
      let AlwaysP = Always()
      let EventuallyP = Eventually()
      let AlwaysEventuallyP = AlwaysEventually()
      let EventuallyAlwaysP = EventuallyAlways()
      let LeadsToPQ = LeadsTo()
      let LeavesZero = LeadsTo()
      AlwaysP(x == 2)
      EventuallyP(x == 2)
      AlwaysEventuallyP(x == 2)
      EventuallyAlwaysP(x == 2)
      LeadsToPQ(x == 2, x == 1)
      LeavesZero(x == 0, x != 0)
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
