import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ChangRobertsDemoTests {
    @Test("Chang–Roberts exposes typed actor deliveries and typed message records")
    func exposesTypedMessages() throws {
        let builderSpec = ChangRoberts.spec
        let builderTree = ParsedSpecModel(
            variables: builderSpec.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: builderSpec.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: builderSpec.invariants.map { ($0.name, $0.body) }
        )
        #expect(
            _tlaAlphaEquivalent(builderTree, ChangRoberts._parserTree),
            Comment(rawValue: _tlaFidelityDiagnostic(ChangRoberts._parserTree, builderTree))
        )
        var machine = ChangRoberts()

        #expect(machine.state.leader == 0)
        #expect(machine.state.messages.elements.count == 12)
        #expect(try machine.availableActions().contains(.deliver(process: .six)))

        _ = try machine.apply(.deliver(process: .six))

        let forwarded = try #require(machine.state.messages.elements.first {
            $0[ChangRoberts.MessageSchema.candidate] == 12 &&
                $0[ChangRoberts.MessageSchema.from] == .six
        })
        #expect(forwarded[ChangRoberts.MessageSchema.to] == .seven)
        #expect(machine.state.leader == 0)
    }

    @Test("Chang–Roberts actor serializes a formal delivery")
    func actorExecutesTypedDelivery() async throws {
        let actor = ChangRoberts.Actor()
        _ = try await actor.execute(
            ChangRoberts.Actor.ActionLabel.deliver(process: .six).toInvocation()
        )

        let state = await actor.state
        let forwarded = try #require(state.messages.elements.first {
            $0[ChangRoberts.MessageSchema.candidate] == 12
        })
        #expect(forwarded[ChangRoberts.MessageSchema.from] == .six)
        #expect(forwarded[ChangRoberts.MessageSchema.to] == .seven)
    }
}
