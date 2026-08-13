import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidModel {
  static var spec: TLASpec {
    TLASpec("InvalidModel") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...2)
      Action("breakBounds") { counter.becomes(2) }
      Invariant("withinBounds") { counter <= 1 }
    }
  }
}
