import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA

struct GeneratedMachineDocumentationTests {
    @Test("bounded model preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() async throws {
        var machine = try BoundedCounter.makeMachine()
        let initial = try await machine.machineObservation()
        let result = try machine.apply(.advance)
        let beforeFailure = machine.state

        #expect(initial.state.value == 0)
        #expect(initial.availableActions == [.advance])
        #expect(result.before.value == 0)
        #expect(result.after.value == 1)
        #expect(throws: GeneratedMachineError.self) {
            try machine.apply(.advance)
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

        let result = try await actor.apply(.advance)
        guard case .committed(let commit) = result else {
            Issue.record("Expected the live actor request to commit")
            return
        }
        #expect(commit.after.position.value == 1)
        #expect(observable.status == .attaching || observable.status == .current(.init(value: 0)))
    }
}
