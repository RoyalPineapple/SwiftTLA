import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA

struct GeneratedMachineDocumentationTests {
    @Test("bounded model preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() throws {
        var machine = try BoundedCounter.makeMachine()
        let result = try machine.send(.advance)
        let beforeFailure = machine.state

        #expect(result.before.value == 0)
        #expect(try machine.isEnabled(.advance) == false)
        #expect(result.after.value == 1)
        #expect(throws: GeneratedMachineError.self) {
            try machine.send(.advance)
        }
        #expect(machine.state == beforeFailure)
    }

    @Test("nested adapters bind the supplied live runtime")
    @MainActor
    func nestedAdaptersExposeDocumentedBehavior() async throws {
        let actorLive = try CounterHost.makeLive()
        let actor = CounterHost.Actor(live: actorLive)
        let observableLive = try CounterScreenModel.makeLive()
        let observable = try await CounterScreenModel.Observable(live: observableLive)

        let actorIdentity = await actor.identity
        #expect(actorIdentity == actorLive.identity)
        #expect(observable.identity == observableLive.identity)
        #expect(actorIdentity != observable.identity)

        let result = try await actor.send(.advance)
        guard case .committed(let commit) = result else {
            Issue.record("Expected the live actor request to commit")
            return
        }
        #expect(commit.after.position.value == 1)
        #expect(observable.status == .attaching || observable.status == .current(.init(value: 0)))
    }
}
