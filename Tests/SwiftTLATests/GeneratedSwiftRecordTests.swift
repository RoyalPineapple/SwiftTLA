import Testing
import SwiftTLA

struct GeneratedSwiftRecordTests {
    @Test("explicit imported record calls share the checked record boundary")
    func validatesImportedRecordCalls() {
        typealias Packet = GeneratedSwiftRecord.Packet
        let calls: [Expr<Packet>] = [
            FormalCall(as: Packet.self, "read"),
            FormalCall(as: Packet.self, "read", 1),
            FormalCall(as: Packet.self, "read", 1, 2),
            ModuleCall(as: Packet.self, "CC", "read", 1, 2)
        ]
        for call in calls {
            guard case .assertView(.operatorApplication, let shape) = call.stateExpr else {
                Issue.record("Expected the imported result to validate its record shape")
                continue
            }
            #expect(shape == Packet.formalValueShape)
        }
    }

    @Test("ordinary Swift records execute through generated typed transitions")
    func executesRecordTransition() throws {
        var machine = try GeneratedSwiftRecord.makeMachine()
        let different = GeneratedSwiftRecord.Packet(count: 9, ready: false)
        #expect(machine.state.packet == different)
        #expect(machine.state.packet.tlaValue != different.tlaValue)
        #expect(machine.state.packet.count == 0 && !machine.state.packet.ready)
        #expect(try machine.violatedInvariants(checking: [.Bounded], atLevel: 1).isEmpty)
        let transition = try machine.send(.advance)
        #expect(transition.before.packet.count == 0 && !transition.before.packet.ready)
        #expect(transition.after.packet.count == 1 && transition.after.packet.ready)
        #expect(transition.before.previousCount == -1)
        #expect(transition.after.previousCount == 0)
        #expect(try machine.violatedInvariants(checking: [.Bounded], atLevel: 2).isEmpty)
        #expect(machine.state.packet.count == transition.after.packet.count)
        #expect(machine.state.packet.ready == transition.after.packet.ready)
        #expect(machine.state.previousCount == transition.after.previousCount)
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
    func validatesFormalConversion() throws {
        typealias Packet = GeneratedSwiftRecord.Packet
        let packet = Packet(count: 3, ready: true)
        #expect(packet.tlaValue == .record(["count": .int(3), "ready": .bool(true)]))
        let decoded = try #require(Packet(formalValue: .record(["count": .int(3), "ready": .bool(true)])))
        #expect(decoded.count == 3 && decoded.ready)
        #expect(Packet.defaultValue.count == 0 && !Packet.defaultValue.ready)
        #expect(Packet(formalValue: .record(["count": .int(3)])) == nil)
        #expect(Packet(formalValue: .record(["count": .bool(true), "ready": .bool(true)])) == nil)
        #expect(Packet(formalValue: .record(["count": .int(3), "ready": .bool(true), "extra": .int(0)])) == nil)
        #expect(Packet(formalValue: .record(TLARecord([
            .init("count", .int(3)), .init("count", .int(3)), .init("ready", .bool(true))
        ]))) == nil)
        #expect(Packet(formalValue: .int(3)) == nil)
    }
}
