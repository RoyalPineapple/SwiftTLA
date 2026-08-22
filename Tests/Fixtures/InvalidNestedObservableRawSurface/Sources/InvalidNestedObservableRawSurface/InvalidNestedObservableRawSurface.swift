import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NestedObservableSurface {
  static var spec: TLASpec {
    TLASpec("NestedObservableSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }

  @TLAObservable final class Observable {}
}

@MainActor
func rejectRawState(_ machine: NestedObservableSurface.Observable) {
  _ = machine.tlaSnapshot()
  _ = NestedObservableSurface.Observable.TransitionEvidence.self
}
