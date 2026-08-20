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
    let owner = try TLALiveMachineOwner.create(for: CounterHost.self)
    let actor = try await CounterHost.Actor(handle: owner.handle)
    let result = await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())

    guard case .committed(let commit) = result else { return }
    assert(commit.after.position.value == 1)
}
