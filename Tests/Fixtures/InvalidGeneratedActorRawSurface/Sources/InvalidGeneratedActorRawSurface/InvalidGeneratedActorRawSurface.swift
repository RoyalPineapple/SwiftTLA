import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedActorSurface {
  static var spec: TLASpec {
    TLASpec("GeneratedActorSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }
}

func rejectRawState(_ machine: GeneratedActorSurface.Actor) async {
  _ = await machine.tlaSnapshot()
  _ = GeneratedActorSurface.Actor.TransitionEvidence.self
}
