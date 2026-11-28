import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SymbolicRecordConstructionModel {
    struct Payload: Hashable, Sendable {
        let value: Int
        static func == (lhs: Self, rhs: Self) -> Bool { true }
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }
    struct Packet: Hashable, Sendable { let payload: Payload; let ready: Bool }
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SymbolicRecordConstructionModel") { scope in
            let start = scope.parameter(as: Payload.self, in: SetExpr<Payload>.literal(
                Payload(value: 0), Payload(value: 1), Payload(value: 2), Payload(value: 3)
            ))
            let packet = scope.sharedVar(initial: Packet.expression(
                payload: Payload.expression(value: start.expr.value), ready: false))
            Do(Step.advance, when: packet.payload.value < 4) {
                let saved = packet
                Assign(packet, to: Packet.expression(
                    payload: Payload.expression(value: saved.payload.value + 1), ready: true))
            }
            let configured = Validation(label: "Configured") { Bind(start, to: Payload(value: 2)) }
            configured
        }
    }
}
