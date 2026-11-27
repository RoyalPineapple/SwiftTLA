import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RecordActionParameterModel {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.ready == rhs.ready }
        func hash(into hasher: inout Hasher) { hasher.combine(ready) }
    }

    enum Step: String, CaseIterable { case construct, update }

    static var spec: TLASpec {
        #spec("RecordActionParameterModel") { scope in
            let packet = scope.sharedVar(initiallyIn: SetExpr<Packet>.literal(Packet(count: 0, ready: false), Packet(count: 0, ready: false)).filtering { value in value.count == 0 })
            SwiftTLA.Action("conflicting") {
                packet.becomes(Packet(count: 1, ready: false))
                packet.becomes(Packet(count: 2, ready: false))
            }
            SwiftTLA.Action("matching") {
                packet.becomes(Packet(count: 1, ready: false))
                packet.becomes(Packet(count: 1, ready: false))
            }
            Do(Step.construct, over: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false), Packet(count: 1, ready: false)).filtering { value in value.count > 0 }.mapping { value in value.expr }) { input in
                Assign(packet, to: Packet.expression(count: input.count, ready: false))
            }
            Do(Step.update, over: SetExpr<Packet>.literal(Packet(count: 1, ready: false)).union(SetExpr<Packet>.literal(Packet(count: 2, ready: false)))) { input in
                Assign(packet.count, to: input.count)
            }
        }
    }
}

@TLAModel
struct BoundedPacketActionModel {
    enum Symbol: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static let finiteValues = allCases
        static var defaultValue: Self { .first }
        var tlaValue: TLAValue { .constant(rawValue) }
    }
    struct Packet: Hashable, Sendable {
        let elements: [Symbol]
    }
    enum Step: String, CaseIterable { case write, reset }

    static var spec: TLASpec {
        #spec("BoundedPacketActions") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...2)
            let size = scope.sharedVar(initial: 0)
            let lengths = IntRange(1, through: limit)
            let packets = Sequences(of: Set<Symbol>([.first, .second]), lengths: lengths).mapping { elements in
                Packet.expression(elements: elements)
            }
            Do(Step.write, over: packets) { packet in size.set(packet.elements.count) }
            Do(Step.reset) { size.set(0) }
        }
    }
}
