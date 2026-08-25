// Example ID: generated-machine-actor

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterHost {
    enum Process: String, FiniteTLAValueDomain {
        case only

        static var defaultValue: Self { .only }
        static let finiteValues: [Process] = [.only]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterHost") {
            Algorithm("CounterHost", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            })
        }
    }

}

func runActorAccess() async throws {
    let actor = try CounterHost.Actor()
    let transition = try await actor.send(.advance)
    let seeded = try CounterHost.Actor(.init(value: 0))

    let actorState = await actor.state
    let seededState = await seeded.state
    assert(actorState == transition.after)
    assert(seededState.value == 0)
}
