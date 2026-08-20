import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct AdapterBindingCounter {
    static var spec: TLASpec {
        TLASpec("AdapterBindingCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 2) }
        }
    }

    @TLAActor
    actor Actor {}

    @TLAObservable
    final class Observable {}
}

@TLAModel
private struct AdapterBindingForeign {
    static var spec: TLASpec {
        TLASpec("AdapterBindingForeign") {
            let level = Var<Int>("level")
            Variable(level, 0)
            Action("raise") { level.becomes(level + 1) }
        }
    }
}

@Suite("Live machine adapter binding")
struct LiveMachineAdapterBindingTests {
    @Test("Actor and observable bind an existing compatible runtime")
    @MainActor
    func adaptersShareOneRuntime() async throws {
        let owner = try TLALiveMachineOwner.create(for: AdapterBindingCounter.self)
        let actor = try await AdapterBindingCounter.Actor(handle: owner.handle)
        let observable = try await AdapterBindingCounter.Observable(handle: owner.handle)

        #expect(actor.identity == owner.identity)
        #expect(observable.identity == owner.identity)

        guard case .committed = await actor._advance() else {
            Issue.record("Expected actor action to commit")
            return
        }

        for _ in 0..<20 where observable.current?.position != .init(value: 1) {
            await Task.yield()
        }
        #expect(observable.current?.identity == owner.identity)
        #expect(observable.current?.position == .init(value: 1))
        #expect(observable.state == .init(count: 1))
        guard case .snapshot(let current) = await owner.handle.current() else {
            Issue.record("Expected runtime snapshot")
            return
        }
        #expect(current.position == .init(value: 1))
        #expect(try AdapterBindingCounter.State(projection: current.state) == observable.state)
    }

    @Test("Binding rejects an incompatible schema without constructing a substitute runtime")
    func incompatibleBindingFails() async throws {
        let owner = try TLALiveMachineOwner.create(for: AdapterBindingForeign.self)
        do {
            _ = try await AdapterBindingCounter.Actor(handle: owner.handle)
            Issue.record("Expected incompatible actor binding to fail")
        } catch is GeneratedLiveMachineDiagnostic {}
        do {
            _ = try await TLALiveMachineAdapterBinding(handle: owner.handle, for: AdapterBindingCounter.self)
            Issue.record("Expected incompatible binding to fail")
        } catch is GeneratedLiveMachineDiagnostic {}
        guard case .snapshot(let current) = await owner.handle.current() else {
            Issue.record("Expected foreign runtime to remain active")
            return
        }
        #expect(current.position == .init(value: 0))
    }

    @Test("Binding rejects an ended runtime without creating a replacement")
    func endedBindingFails() async throws {
        let owner = try TLALiveMachineOwner.create(for: AdapterBindingCounter.self)
        await owner.end()

        do {
            _ = try await AdapterBindingCounter.Actor(handle: owner.handle)
            Issue.record("Expected ended actor binding to fail")
        } catch let error as TLALiveMachineAdapterBindingError {
            #expect(error == .runtimeUnavailable(.endedByOwner))
        }
        do {
            _ = try await TLALiveMachineAdapterBinding(handle: owner.handle, for: AdapterBindingCounter.self)
            Issue.record("Expected ended binding to fail")
        } catch let error as TLALiveMachineAdapterBindingError {
            #expect(error == .runtimeUnavailable(.endedByOwner))
        }
    }

    @Test("Cancelling an observable does not end its runtime")
    @MainActor
    func observableCancellationIsSubscriptionOnly() async throws {
        let owner = try TLALiveMachineOwner.create(for: AdapterBindingCounter.self)
        let observable = try await AdapterBindingCounter.Observable(handle: owner.handle)
        await observable.cancelObservation()
        _ = await owner.handle.execute(.init(name: "advance"))
        guard case .snapshot(let current) = await owner.handle.current() else {
            Issue.record("Expected runtime to remain active")
            return
        }
        #expect(current.position == .init(value: 1))
    }

    @Test("Concurrent actor submissions serialize at the shared live runtime")
    func concurrentActorSubmissionsCommitOnlyOnce() async throws {
        let owner = try TLALiveMachineOwner.create(for: AdapterBindingCounter.self)
        let actor = try await AdapterBindingCounter.Actor(handle: owner.handle)

        async let first = actor._advance()
        async let second = actor._advance()
        let outcomes = await [first, second]

        let committedCount = outcomes.reduce(into: 0) { count, outcome in
            if case .committed = outcome { count += 1 }
        }
        let rejectedCount = outcomes.reduce(into: 0) { count, outcome in
            if case .rejected = outcome { count += 1 }
        }
        #expect(committedCount == 1)
        #expect(rejectedCount == 1)

        guard case .snapshot(let current) = await owner.handle.current() else {
            Issue.record("Expected shared runtime to remain available")
            return
        }
        #expect(current.position == .init(value: 1))
        #expect(try AdapterBindingCounter.State(projection: current.state) == .init(count: 1))
    }
}
