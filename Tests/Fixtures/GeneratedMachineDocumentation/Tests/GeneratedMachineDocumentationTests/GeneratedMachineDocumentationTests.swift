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
        let isEnabled = try machine.isEnabled(.advance)
        #expect(isEnabled == false)
        #expect(result.after.value == 1)
        #expect(throws: GeneratedMachineError.self) {
            try machine.send(.advance)
        }
        #expect(machine.state == beforeFailure)
    }

    @Test("generated actor owns the generated machine")
    func generatedActorExposesDocumentedBehavior() async throws {
        let actor = try CounterHost.Actor()

        let transition = try await actor.send(.advance)
        let state = await actor.state
        #expect(state == transition.after)
    }
}
