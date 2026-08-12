import SwiftTLA
import SwiftTLAMacros

@TLAActor
actor ValidActor {
  static var spec: TLASpec {
    TLASpec("ValidActor") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...1)
      Action("increment") { counter < 1 && counter.becomes(counter + 1) }
      Invariant("withinBounds") { counter >= 0 && counter <= 1 }
    }
  }
}

@main
struct ValidActorFixture {
  static func main() async throws {
    try await ValidActor.verifyTransitions()
    try await ValidActor.verifyInvariants()
  }
}
