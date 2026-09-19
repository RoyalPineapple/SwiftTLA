@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct NestedActorConcurrencyTests {
    @Test("Nested actor matches generated-machine execution")
    func nestedActorMatchesGeneratedMachineExecution() async throws {
        let actorLabel: NestedComposedCounter.Action = .advance
        var machine = try NestedComposedCounter.makeMachine()
        let actor = try NestedComposedCounter.Actor()

        let expectedBefore = machine.state
        #expect(actorLabel == .advance)
        #expect(expectedBefore.count == 0)

        let expected = try machine.send(.advance)
        let acted = try await actor.send(.advance)

        #expect(acted.before == expected.before)
        #expect(acted.after == expected.after)
        #expect((await actor.state).count == 1)
    }

    @Test("Nested actor commits overlapping executions without stale write-back")
    func nestedActorExecutesOverlappingTransitionsAtomically() async throws {
        let actor = try NestedComposedCounter.Actor()
        async let first = actor.send(.advance)
        async let second = actor.send(.advance)
        _ = try await (first, second)

        #expect((await actor.state).count == 2)
    }
}
