import SwiftTLA
import SwiftTLAMacros

@TLAObservable
final class StandaloneObservableSurface {
  static var spec: TLASpec {
    TLASpec("StandaloneObservableSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }
}

@MainActor
func rejectRawState(_ machine: StandaloneObservableSurface) {
  let _: [String: TLAValue] = machine.tlaSnapshot()
  _ = StandaloneObservableSurface.TransitionEvidence.self
}
