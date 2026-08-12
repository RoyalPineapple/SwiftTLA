import SwiftTLA
import SwiftTLAMacros

@TLAActor
actor InvalidActor {
  static var spec: TLASpec {
    TLASpec("InvalidActor") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...2)
      Action("breakBounds") { counter.becomes(2) }
      Invariant("withinBounds") { counter <= 1 }
    }
  }
}
