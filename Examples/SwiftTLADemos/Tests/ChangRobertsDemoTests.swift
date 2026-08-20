import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ChangRobertsDemoTests {
    @Test("Chang–Roberts exposes typed actor deliveries and typed message records")
    func exposesTypedMessages() throws {
        let builderSpec = ChangRoberts.spec
        #expect(try builderSpec.compile().renderedTLAModuleBundle().tla == try ChangRoberts.spec.compile().renderedTLAModuleBundle().tla)
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
        _ = try await actor.apply(.deliver(process: .six))

        let state = await actor.state
        let forwarded = try #require(state.messages.elements.first {
            $0[ChangRoberts.MessageSchema.candidate] == 12
        })
        #expect(forwarded[ChangRoberts.MessageSchema.from] == .six)
        #expect(forwarded[ChangRoberts.MessageSchema.to] == .seven)
    }
}
