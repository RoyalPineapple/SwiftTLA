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

}

@Suite("Live adapters")
struct LiveMachineAdapterTests {
    @Test("Actor uses the model-owned live runtime")
    func actorUsesModelOwnedRuntime() async throws {
        let live = try AdapterCounter.makeLive()
        let actor = AdapterCounter.Actor(live: live)

        guard case .committed = try await actor.send(.advance) else {
            Issue.record("Expected actor action to commit")
            return
        }
        let actorIdentity = await actor.identity
        #expect(actorIdentity == live.identity)
        guard case .snapshot(let current) = try await live.current() else {
            Issue.record("Expected runtime snapshot")
            return
        }
        #expect(current.position == .init(value: 1))
    }
}
