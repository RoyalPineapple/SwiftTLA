import Observation
import SwiftTLA
import SwiftTLAMacros

@Observable
@TLAObservable
final class ValidObservable {
  static var spec: TLASpec {
    TLASpec("ValidObservable") {
      let counter = Var("counter", 0)
      Action("increment") { counter < 1 && counter.becomes(counter + 1) }
      Invariant("withinBounds") { counter >= 0 && counter <= 1 }
    }
  }
}
