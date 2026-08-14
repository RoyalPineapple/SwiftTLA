// Example ID: generated-machine-actor

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterHost {
    enum Process: String, FiniteDomainKey {
        case only

        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.actor.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterHost") {
            Algorithm("CounterHost") {
                let value = SharedVar(initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }

    @TLAActor
    actor Actor {}
}

func runActorAccess() async throws {
    let actor = CounterHost.Actor()
    let state = await actor.state
    let result = try await actor.execute(CounterHost.Actor.ActionLabel.advance(process: .only).toInvocation())

    assert(state.value == 0)
    assert(result.action == CounterHost.Actor.ActionLabel.advance(process: .only))
    assert(result.after.value == 1)
}
