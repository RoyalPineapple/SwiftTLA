import SwiftTLA
import SwiftTLAMacros

let dynamicName = "DynamicModelName"

@TLAModel
struct InvalidDynamicModelName {
  static var spec: TLASpec {
    #spec(dynamicName) { scope in
      let count = scope.sharedVar(initial: 0)
    }
  }
}
