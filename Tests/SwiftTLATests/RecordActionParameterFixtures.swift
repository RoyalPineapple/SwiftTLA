import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RecordActionParameterModel {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool
    }

    enum Step: String, CaseIterable { case construct, update }

    static var spec: TLASpec {
        #spec("RecordActionParameterModel") { scope in
            let packet = scope.sharedVar(initial: Packet(count: 0, ready: false))
            Do(Step.construct, over: Set<Int>([1, 2])) { input in
                Assign(packet, to: Packet.expression(count: input, ready: false))
            }
            Do(Step.update, over: Set<Int>([1, 2])) { input in
                Assign(packet.count, to: input)
            }
        }
    }
}
