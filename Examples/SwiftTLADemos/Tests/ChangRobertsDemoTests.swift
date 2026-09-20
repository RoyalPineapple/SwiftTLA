import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ChangRobertsDemoTests {
    @Test("message state preserves the authored Swift record and validates formal fields")
    func preservesMessageRecord() throws {
        let machine = try ChangRoberts.makeMachine()
        let messages: Set<ChangRoberts.Message> = machine.state.messages
        let message = ChangRoberts.Message(candidate: 12, from: .five, to: .six)
        #expect(messages.contains(message))
        #expect(ChangRoberts.Message(formalValue: message.tlaValue) == message)
        #expect(ChangRoberts.Message(formalValue: .record([
            "candidate": .int(12), "from": .string("five")
        ])) == nil)
        #expect(ChangRoberts.Message(formalValue: .record([
            "candidate": .int(12), "from": .string("five"), "to": .string("foreign")
        ])) == nil)
        #expect(ChangRoberts.Message(formalValue: .record([
            "candidate": .int(12), "from": .string("five"), "to": .string("six"), "extra": .int(0)
        ])) == nil)
    }

    @Test("generated deliveries drop smaller identifiers and elect the largest after a full ring")
    func electsLargestIdentifier() throws {
        var machine = try ChangRoberts.makeMachine()
        let dropped = ChangRoberts.Message(candidate: 2, from: .two, to: .three)
        _ = try machine.send(.deliver(process: .three))
        #expect(!machine.state.messages.contains(dropped))
        #expect(machine.state.messages.count == 11)

        let route: [ChangRoberts.Node] = [.six, .seven, .eight, .nine, .ten, .eleven, .twelve,
                                         .one, .two, .three, .four, .five]
        for node in route {
            let next = try #require(machine.state.next[node])
            let successors = try machine.successors(for: .deliver(process: node))
            machine = try #require(successors.first { successor in
                if node == .five { return successor.state.leader == 12 }
                return successor.state.messages.contains(.init(candidate: 12, from: node, to: next))
            })
        }
        #expect(machine.state.leader == 12)
        for node in ChangRoberts.Node.allCases {
            #expect(try machine.successors(for: .deliver(process: node)).isEmpty)
        }
    }

    @Test("Chang–Roberts exposes typed machine deliveries and typed message records")
    func exposesTypedMessages() throws {
        var machine = try ChangRoberts.makeMachine()

        #expect(machine.state.leader == 0)
        #expect(machine.state.messages.count == 12)
        #expect(try machine.isEnabled(.deliver(process: .six)))

        _ = try machine.send(.deliver(process: .six))

        let forwarded = try #require(machine.state.messages.first {
            $0.candidate == 12 &&
                $0.from == .six
        })
        #expect(forwarded.to == .seven)
        #expect(machine.state.leader == 0)
    }

    @Test("Chang–Roberts actor serializes a typed delivery")
    func actorExecutesTypedDelivery() async throws {
        let actor = try ChangRoberts.Actor()
        _ = try await actor.send(.deliver(process: .six))

        let state = await actor.state
        let forwarded = try #require(state.messages.first {
            $0.candidate == 12
        })
        #expect(forwarded.from == .six)
        #expect(forwarded.to == .seven)
    }
}
