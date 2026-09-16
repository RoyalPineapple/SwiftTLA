import Testing
import SwiftTLA

struct GeneratedSwiftRecordTests {
    @Test("ordinary Swift records execute through generated typed transitions")
    func executesRecordTransition() throws {
        var machine = try GeneratedSwiftRecord.makeMachine()
        #expect(machine.state.packet == .init(count: 0, ready: false))
        let transition = try machine.send(.advance)
        #expect(transition.before.packet == .init(count: 0, ready: false))
        #expect(transition.after.packet == .init(count: 1, ready: true))
        #expect(machine.state == transition.after)
    }

    @Test("generated record conversion validates every key and value")
    func validatesFormalConversion() {
        typealias Packet = GeneratedSwiftRecord.Packet
        let packet = Packet(count: 3, ready: true)
        #expect(Packet(formalValue: packet.tlaValue) == packet)
        #expect(Packet.defaultValue == .init(count: 0, ready: false))
        #expect(Packet(formalValue: .record(["count": .int(3)])) == nil)
        #expect(Packet(formalValue: .record(["count": .bool(true), "ready": .bool(true)])) == nil)
        #expect(Packet(formalValue: .record(["count": .int(3), "ready": .bool(true), "extra": .int(0)])) == nil)
        #expect(Packet(formalValue: .record(TLARecord([
            .init("count", .int(3)), .init("count", .int(3)), .init("ready", .bool(true))
        ]))) == nil)
        #expect(Packet(formalValue: .int(3)) == nil)
    }
}
