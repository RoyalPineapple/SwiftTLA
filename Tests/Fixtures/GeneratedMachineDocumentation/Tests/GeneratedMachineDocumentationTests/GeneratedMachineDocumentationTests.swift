import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA

struct GeneratedMachineDocumentationTests {
    @Test("bounded model preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() async throws {
        var machine = BoundedCounter()
        let initial = await machine.machineObservation()
        let evidence = try machine.apply(.advance)
        let beforeFailure = machine.tlaSnapshot()

        #expect(initial.state["value"] == .int(0))
        #expect(initial.availableInvocations == [.init(name: "advance")])
        #expect(evidence.before["value"] == .int(0))
        #expect(evidence.after["value"] == .int(1))
        #expect(throws: GeneratedMachineError.self) {
            try machine.apply(.advance)
        }
        #expect(machine.tlaSnapshot() == beforeFailure)
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

        #expect(await actor.machineObservation().state["value"] == .int(0))
        _ = try await actor.execute(.init(name: "advance"))
        _ = try await observable.execute(.init(name: "advance"))

        #expect(await actor.machineObservation().state["value"] == .int(1))
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
