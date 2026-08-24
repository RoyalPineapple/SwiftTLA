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

    @TLAActor
    actor Actor {}
}

func runActorAccess() async throws {
    let live = try CounterHost.makeLive()
    let actor = CounterHost.Actor(live: live)
    let result = try await actor.send(.advance)

    guard case .committed(let commit) = result else { return }
    assert(commit.after.position.value == 1)
}
