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

        try machine.send(.advance)
        let actedBefore = await actor.state
        try await actor.send(.advance)
        let actedAfter = await actor.state

        #expect(actedBefore == expectedBefore)
        #expect(actedAfter == machine.state)
        #expect((await actor.state).count == 1)
    }

    @Test("Nested actor commits overlapping executions without stale write-back")
    func nestedActorExecutesOverlappingTransitionsAtomically() async throws {
        let actor = try NestedComposedCounter.Actor()
        async let first: Void = actor.send(.advance)
        async let second: Void = actor.send(.advance)
        _ = try await (first, second)

        #expect((await actor.state).count == 2)
    }
}
