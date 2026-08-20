import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct AdapterCounter {
    static var spec: TLASpec {
        TLASpec("AdapterCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 1) }
        }
    }

    @TLAActor
    actor Actor {}

    @TLAObservable
    final class Observable {}
}

@Suite("Live adapters")
struct LiveMachineAdapterTests {
    @Test("Actor and observable use the model-owned live runtime")
    @MainActor
    func adaptersShareOneRuntime() async throws {
        let live = try AdapterCounter.makeLive()
        let actor = AdapterCounter.Actor(live: live)
        let observable = try await AdapterCounter.Observable(live: live)

        guard case .committed = try await actor.apply(.advance) else {
            Issue.record("Expected actor action to commit")
            return
        }

        for _ in 0..<20 where observable.current?.position != .init(value: 1) {
            await Task.yield()
        }
        #expect(actor.identity == live.identity)
        #expect(observable.identity == live.identity)
        #expect(observable.state == .init(count: 1))
    }

    @Test("Cancelling an observable leaves its model runtime active")
    @MainActor
    func observableCancellationIsSubscriptionOnly() async throws {
        let live = try AdapterCounter.makeLive()
        let observable = try await AdapterCounter.Observable(live: live)
        let actor = AdapterCounter.Actor(live: live)
        await observable.cancelObservation()
        _ = try await actor.apply(.advance)

        guard case .snapshot(let current) = try await live.current() else {
            Issue.record("Expected runtime snapshot")
            return
        }
        #expect(current.position == .init(value: 1))
    }
}
