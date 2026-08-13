import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA

struct GeneratedMachineDocumentationTests {
    @Test("bounded model preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() async throws {
        var machine = BoundedCounter()
        let initial = await machine.machineObservation()
        let result = try machine.apply(.advance)
        let beforeFailure = machine.state

        #expect(initial.projection != nil)
        #expect(initial.availableInvocations == [.init(name: "advance")])
        #expect(result.before.value == 0)
        #expect(result.after.value == 1)
        #expect(throws: GeneratedMachineError.self) {
            try machine.apply(.advance)
        }
        #expect(machine.state == beforeFailure)
    }

    @Test("nested adapters retain canonical isolation and callback semantics")
    @MainActor
    func nestedAdaptersExposeDocumentedBehavior() async throws {
        let actor = CounterHost.Actor()
        let observable = CounterScreenModel.Observable()
        let recorder = CallbackRecorder()

        observable.onAdvance = { before, after in
            await recorder.record(before: before, after: after)
        }

        #expect(await actor.state.value == 0)
        _ = try await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())
        _ = try await observable.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation())

        #expect(await actor.state.value == 1)
        #expect(await recorder.transitions == [.init(before: 0, after: 1)])
    }
}

private actor CallbackRecorder {
    struct Transition: Equatable, Sendable {
        let before: Int
        let after: Int
    }

    private(set) var transitions: [Transition] = []

    func record(before: CounterScreenModel.State, after: CounterScreenModel.State) {
        transitions.append(.init(before: before.value, after: after.value))
    }
}
