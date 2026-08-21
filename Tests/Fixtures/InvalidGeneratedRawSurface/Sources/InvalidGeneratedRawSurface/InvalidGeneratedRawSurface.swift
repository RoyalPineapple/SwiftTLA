import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidGeneratedRawSurface {
  static var spec: TLASpec {
    TLASpec("InvalidGeneratedRawSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }
}

let machine = InvalidGeneratedRawSurface()
let rawState = machine.tlaSnapshot()
let transitionEvidence = InvalidGeneratedRawSurface.TransitionEvidence.self
_ = (rawState, transitionEvidence)
