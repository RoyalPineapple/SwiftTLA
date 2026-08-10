import SwiftTLA
import SwiftTLAMacros

@TLAValidated
struct InvalidValidatedModel {
  static var spec: TLASpec {
    TLASpec("InvalidValidatedModel") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0..<5)
      Action("inc") { counter < 10 && counter.becomes(counter + 1) }
      Invariant("counterBounded") { counter <= 3 }
    }
  }
}
