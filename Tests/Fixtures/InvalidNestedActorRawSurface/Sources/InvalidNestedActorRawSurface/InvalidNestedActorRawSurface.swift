import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NestedActorSurface {
  static var spec: TLASpec {
    TLASpec("NestedActorSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }

  @TLAActor actor Actor {}
}

func rejectRawState(_ machine: NestedActorSurface.Actor) async {
  let _: [String: TLAValue] = await machine.tlaSnapshot()
  _ = NestedActorSurface.Actor.TransitionEvidence.self
}
