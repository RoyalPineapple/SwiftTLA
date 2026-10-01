import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidObservedModelState {
  var count = 0 {
    didSet {}
  }

  static var spec: TLASpec {
    #spec("InvalidObservedModelState") {
      let state = Var<Int>("state")
      Variable(state, 0)
    }
  }
}
