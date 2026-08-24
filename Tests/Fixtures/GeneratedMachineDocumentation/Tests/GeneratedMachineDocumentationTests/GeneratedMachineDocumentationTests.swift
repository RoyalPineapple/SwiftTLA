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

    @Test("nested actor binds the supplied live runtime")
    func nestedActorExposesDocumentedBehavior() async throws {
        let actorLive = try CounterHost.makeLive()
        let actor = CounterHost.Actor(live: actorLive)

        let actorIdentity = await actor.identity
        #expect(actorIdentity == actorLive.identity)

        let result = try await actor.send(.advance)
        guard case .committed(let commit) = result else {
            Issue.record("Expected the live actor request to commit")
            return
        }
        #expect(commit.after.position.value == 1)
    }
}
