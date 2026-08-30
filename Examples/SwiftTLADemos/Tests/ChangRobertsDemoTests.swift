import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ChangRobertsDemoTests {
    @Test("Chang–Roberts exposes typed machine deliveries and typed message records")
    func exposesTypedMessages() throws {
        var machine = try ChangRoberts.makeMachine()

        #expect(machine.state.leader == 0)
        #expect(machine.state.messages.elements.count == 12)
        #expect(try machine.isEnabled(.deliver(process: .six)))

        _ = try machine.send(.deliver(process: .six))

        let forwarded = try #require(machine.state.messages.elements.first {
            $0.value(for: ChangRoberts.MessageSchema.candidate) == 12 &&
                $0.value(for: ChangRoberts.MessageSchema.from) == .six
        })
        #expect(forwarded.value(for: ChangRoberts.MessageSchema.to) == .seven)
        #expect(machine.state.leader == 0)
    }

    @Test("Chang–Roberts actor serializes a typed delivery")
    func actorExecutesTypedDelivery() async throws {
        let actor = try ChangRoberts.Actor()
        _ = try await actor.send(.deliver(process: .six))

        let state = await actor.state
        let forwarded = try #require(state.messages.elements.first {
            $0.value(for: ChangRoberts.MessageSchema.candidate) == 12
        })
        #expect(forwarded.value(for: ChangRoberts.MessageSchema.from) == .six)
        #expect(forwarded.value(for: ChangRoberts.MessageSchema.to) == .seven)
    }
}
