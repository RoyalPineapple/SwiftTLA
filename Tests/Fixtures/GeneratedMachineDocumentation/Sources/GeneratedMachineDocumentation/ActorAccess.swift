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
    let observation = await actor.machineObservation()
    let evidence = try await actor.execute(.init(name: "advance"))

    assert(observation.state["value"] == .int(0))
    assert(evidence.after["value"] == .int(1))
}
