import SwiftTLA
import SwiftTLAMacros

@TLAObservable
final class ValidObservable {
  static var spec: TLASpec {
    TLASpec("ValidObservable") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...1)
      Action("increment") { counter < 1 && counter.becomes(counter + 1) }
      Invariant("withinBounds") { counter >= 0 && counter <= 1 }
    }
  }
}
