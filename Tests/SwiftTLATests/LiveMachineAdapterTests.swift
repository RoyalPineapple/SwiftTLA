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

@TLAModel
private struct OtherAdapterCounter {
    static var spec: TLASpec {
        TLASpec("OtherAdapterCounter") {
            let level = Var<Int>("level")
            Variable(level, 0)
            Action("raise") { level.becomes(level + 1) }
        }
    }

    @TLAActor
    actor Actor {}
}

@Suite("Live adapters")
struct LiveMachineAdapterTests {
    @Test("Actor and observable use the model-owned live runtime")
    @MainActor
    func adaptersShareOneRuntime() async throws {
        let owner = try AdapterCounter.makeLiveOwner()
        let actor = try AdapterCounter.Actor(handle: owner.handle)
        let observable = try await AdapterCounter.Observable(handle: owner.handle)

        guard case .committed = try await actor.apply(.advance) else {
            Issue.record("Expected actor action to commit")
            return
        }

        for _ in 0..<20 where observable.current?.position != .init(value: 1) {
            await Task.yield()
        }
        #expect(actor.identity == owner.identity)
        #expect(observable.identity == owner.identity)
        #expect(observable.state == .init(count: 1))
    }

    @Test("Adapters reject a handle from another model")
    func incompatibleHandleFails() throws {
        let owner = try OtherAdapterCounter.makeLiveOwner()
        #expect(throws: GeneratedMachineError.self) {
            try AdapterCounter.Actor(handle: owner.handle)
        }
    }

    @Test("Cancelling an observable leaves its model runtime active")
    @MainActor
    func observableCancellationIsSubscriptionOnly() async throws {
        let owner = try AdapterCounter.makeLiveOwner()
        let observable = try await AdapterCounter.Observable(handle: owner.handle)
        let actor = try AdapterCounter.Actor(handle: owner.handle)
        await observable.cancelObservation()
        _ = try await actor.apply(.advance)

        guard case .snapshot(let current) = await owner.handle.current() else {
            Issue.record("Expected runtime snapshot")
            return
        }
        #expect(current.position == .init(value: 1))
    }
}
