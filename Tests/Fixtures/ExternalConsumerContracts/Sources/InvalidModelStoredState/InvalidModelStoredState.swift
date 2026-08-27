import SwiftTLA
import SwiftTLAMacros

final class MutableReferenceState {}

@TLAModel
struct InvalidModelStoredState {
  let reference = MutableReferenceState()

  static var spec: TLASpec {
    TLASpec("InvalidModelStoredState") {
      let count = Var<Int>("count")
      Variable(count, 0)
    }
  }
}
