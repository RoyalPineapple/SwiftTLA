import SwiftTLA
import SwiftTLAMacros

@TLAActor
actor StandaloneActorSurface {
  static var spec: TLASpec {
    TLASpec("StandaloneActorSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }
}

func rejectRawState(_ machine: StandaloneActorSurface) async {
  let _: [String: TLAValue] = await machine.tlaSnapshot()
  _ = StandaloneActorSurface.TransitionEvidence.self
}
