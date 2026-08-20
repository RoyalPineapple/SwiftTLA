import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA

struct GeneratedMachineDocumentationTests {
    @Test("bounded model preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() async throws {
        var machine = try BoundedCounter.makeMachine()
        let initial = await machine.machineObservation()
        let result = try machine.apply(.advance)
        let beforeFailure = machine.state

        #expect(initial.projection != nil)
        #expect(initial.availableInvocations == [.init(name: "advance", arguments: [.string("only")])])
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
        let actorOwner = try CounterHost.makeLiveOwner()
        let actor = try CounterHost.Actor(handle: actorOwner.handle)
        let observableOwner = try CounterScreenModel.makeLiveOwner()
        let observable = try await CounterScreenModel.Observable(handle: observableOwner.handle)

        #expect(actor.identity == actorOwner.handle.identity)
        #expect(observable.identity == observableOwner.handle.identity)
        #expect(actor.identity != observable.identity)

        let result = try await actor._advance()
        guard case .committed(let commit) = result else {
            Issue.record("Expected the live actor request to commit")
            return
        }
        #expect(commit.after.position.value == 1)
        #expect(observable.status == .attaching || observable.status == .current(.init(value: 0)))
    }
}
