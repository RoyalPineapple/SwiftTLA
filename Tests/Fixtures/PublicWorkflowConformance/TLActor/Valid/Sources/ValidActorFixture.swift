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
    let live = try ValidActorHost.makeLive()
    let actor = ValidActorHost.Actor(live: live)
    _ = try await actor.apply(.increment)
  }
}
