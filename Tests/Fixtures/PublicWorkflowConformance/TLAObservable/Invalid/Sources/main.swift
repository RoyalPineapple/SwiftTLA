import Observation
import SwiftTLA
import SwiftTLAMacros

@Observable
@TLAObservable
final class InvalidObservable {
  static var spec: TLASpec {
    TLASpec("InvalidObservable") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...2)
      Action("breakBounds") { counter.becomes(2) }
      Invariant("withinBounds") { counter <= 1 }
    }
  }
}
