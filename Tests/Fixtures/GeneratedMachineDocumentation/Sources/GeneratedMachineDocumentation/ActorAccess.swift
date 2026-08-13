// Example ID: generated-machine-actor

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterHost {
    static var spec: TLASpec {
        TLASpec("CounterHost") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

    @TLAActor
    actor Actor {}
}

func runActorAccess() async throws {
    let actor = CounterHost.Actor()
    let state = await actor.state
    let result = try await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())

    assert(state.value == 0)
    assert(result.action == CounterHost.Actor.ActionLabel.advance)
    assert(result.after.value == 1)
}
