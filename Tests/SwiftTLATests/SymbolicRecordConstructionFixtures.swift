import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SymbolicRecordConstructionModel {
    struct Payload: Hashable, Sendable { let value: Int }
    struct Packet: Hashable, Sendable { let payload: Payload; let ready: Bool }
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SymbolicRecordConstructionModel") { scope in
            let start = scope.parameter(as: Int.self, in: 0...3)
            let packet = scope.sharedVar(initial: Packet.expression(
                payload: Payload.expression(value: start), ready: false))
            Do(Step.advance, when: packet.payload.value < 4) {
                let saved = packet
                Assign(packet, to: Packet.expression(
                    payload: Payload.expression(value: saved.payload.value + 1), ready: true))
            }
            Validation("Configured") { Bind(start, to: 2) }
        }
    }
}
