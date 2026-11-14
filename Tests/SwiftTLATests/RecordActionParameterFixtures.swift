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
            let packet = scope.sharedVar(in: SetExpr<Packet>.literal(Packet(count: 0, ready: false), Packet(count: 0, ready: false)).filtering { value in value.count == 0 })
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
