import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct ActorCounter {
    static var spec: TLASpec {
        TLASpec("ActorCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 1) }
        }
    }
}

@Suite("Generated actor")
struct GeneratedActorTests {
    @Test("A model creates and executes its typed actor")
    func typedActionCommitsTypedState() async throws {
        let actor = try ActorCounter.Actor()
        let transition = try await actor.send(.advance)
        #expect(transition.before == .init(count: 0))
        #expect(transition.after == .init(count: 1))
        #expect(await actor.state == transition.after)
    }

    @Test("A disabled typed action leaves the actor state unchanged")
    func typedRejectionPreservesState() async throws {
        let actor = try ActorCounter.Actor()
        _ = try await actor.send(.advance)

        await #expect(throws: GeneratedMachineError.self) {
            try await actor.send(.advance)
        }
        #expect(await actor.state == .init(count: 1))
    }

    @Test("A typed initial state is preserved")
    func typedInitialStateIsPreserved() async throws {
        let actor = try ActorCounter.Actor(.init(count: 1))

        #expect(await actor.state == .init(count: 1))
        #expect(try await actor.isEnabled(.advance) == false)
    }
}
