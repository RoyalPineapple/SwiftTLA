import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidObservedModelState {
  var count = 0 {
    didSet {}
  }

  static var spec: TLASpec {
    #spec("InvalidObservedModelState") { scope in
      let state = scope.sharedVar(initial: 0)
    }
  }
}
