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
            let packet = scope.sharedVar(initial: Packet(count: 0, ready: false))
            Do(Step.construct, over: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { input in
                Assign(packet, to: Packet.expression(count: input.count, ready: false))
            }
            Do(Step.update, over: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { input in
                Assign(packet.count, to: input.count)
            }
        }
    }
}
