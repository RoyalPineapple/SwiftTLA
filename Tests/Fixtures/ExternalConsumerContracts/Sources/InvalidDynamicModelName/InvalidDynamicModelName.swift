import SwiftTLA
import SwiftTLAMacros

let dynamicName = "DynamicModelName"

@TLAModel
struct InvalidDynamicModelName {
  static var spec: TLASpec {
    #spec(dynamicName) {
      let count = Var<Int>("count")
      Variable(count, 0)
    }
  }
}
