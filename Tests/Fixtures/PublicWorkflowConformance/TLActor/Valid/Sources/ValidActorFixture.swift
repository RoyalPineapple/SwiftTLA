import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ValidActorHost {
  static var spec: TLASpec {
    TLASpec("ValidActor") {
      let counter = Var("counter", 0)
      Variable(counter, in: 0...1)
      Action("increment") { counter < 1 && counter.becomes(counter + 1) }
      Invariant("withinBounds") { counter >= 0 && counter <= 1 }
    }
  }

  @TLAActor
  actor Actor {}
}

@main
struct ValidActorFixture {
  static func main() async throws {
    try await ValidActorHost.verifyTransitions()
    try await ValidActorHost.verifyInvariants()
  }
}
