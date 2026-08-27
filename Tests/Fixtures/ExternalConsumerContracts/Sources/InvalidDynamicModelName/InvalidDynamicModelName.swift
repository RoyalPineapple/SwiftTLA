import SwiftTLA
import SwiftTLAMacros

let dynamicName = "DynamicModelName"

@TLAModel
struct InvalidDynamicModelName {
  static var spec: TLASpec {
    TLASpec(dynamicName) {
      let count = Var<Int>("count")
      Variable(count, 0)
    }
  }
}
