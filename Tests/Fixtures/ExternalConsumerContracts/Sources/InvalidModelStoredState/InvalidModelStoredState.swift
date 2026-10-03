import SwiftTLA
import SwiftTLAMacros

final class MutableReferenceState {}

@TLAModel
struct InvalidModelStoredState {
  let reference = MutableReferenceState()

  static var spec: TLASpec {
    #spec("InvalidModelStoredState") { scope in
      let count = scope.sharedVar(initial: 0)
    }
  }
}
