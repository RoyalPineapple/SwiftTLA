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
        #expect(transition.before.previousCount == -1)
        #expect(transition.after.previousCount == 0)
        #expect(machine.state == transition.after)
    }

    @Test("record expression fields retain their Swift field types")
    func readsTypedFields() {
        let record = Expr<GeneratedSwiftRecord.Packet>(.variable("packet"))
        let count: Expr<Int> = record.count
        let ready: Expr<Bool> = record.ready
        #expect(count.stateExpr == .recordAccess(.variable("packet"), "count"))
        #expect(ready.stateExpr == .recordAccess(.variable("packet"), "ready"))
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
