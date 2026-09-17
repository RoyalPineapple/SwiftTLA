import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ChannelModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2, d3
        case ap1 = "d1_OF_DATUM", ap2 = "d2_OF_DATUM"

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .d1, .d2, .d3: .constant(rawValue)
            case .ap1, .ap2: .string(rawValue)
            }
        }
    }

    package struct Channel: Hashable, Sendable {
        package let ack: Int
        package let rdy: Int
        package let val: Datum
    }

    package enum Step: String, CaseIterable { case Send, Rcv }

    package static var spec: TLASpec {
        #spec("Channel") { scope in
            Extends(.naturals)
            let Data = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([
                Set<Datum>([Datum.d1, Datum.d2, Datum.d3]), Set<Datum>([Datum.ap1, Datum.ap2])
            ]))
            let chan = scope.sharedVar(in: Data.flatMapping { value in
                Set<Int>([0, 1]).mapping { bit in
                    Channel.expression(ack: bit, rdy: bit, val: value)
                }
            })
            let TypeInvariant = Invariant()

            Do(Step.Send, over: Data) { d in
                When(chan.rdy == chan.ack)
                Assign(chan.val, to: d)
                Assign(chan.rdy, to: 1 - chan.rdy)
            }
            Do(Step.Rcv) {
                When(chan.rdy != chan.ack)
                Assign(chan.ack, to: 1 - chan.ack)
            }
            TypeInvariant {
                Data.contains(chan.val)
                    && IntRange(0, through: 1).contains(chan.rdy)
                    && IntRange(0, through: 1).contains(chan.ack)
            }
            Validation("Upstream") { Bind(Data, to: Set<Datum>([Datum.d1, Datum.d2, Datum.d3])) }
            Validation("APChannel") { Bind(Data, to: Set<Datum>([Datum.ap1, Datum.ap2])) }
        }
    }
}
