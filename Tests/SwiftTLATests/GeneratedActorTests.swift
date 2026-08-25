import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct ActorCounter {
    private enum Process: String, FiniteTLAValueDomain {
        case only

        static var defaultValue: Self { .only }
        static let finiteValues: [Self] = [.only]
        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("ActorCounter") {
            Algorithm("ActorCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(count < 1)
                        Assign(count, to: count + 1)
                        Stop()
                    }
                }
            })
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
