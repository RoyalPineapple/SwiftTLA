import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ChannelModel: Sendable {
    package enum Data: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2, d3

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package struct Channel: Hashable, Sendable {
        package let ack: Int
        package let rdy: Int
        package let val: Data
    }

    package enum Step: String, CaseIterable { case Send, Rcv }

    package static var spec: TLASpec {
        #spec("Channel") { scope in
            Extends(.naturals)
            let chan = scope.sharedVar(in: Set<Data>([Data.d1, Data.d2, Data.d3]).flatMapping { value in
                Set<Int>([0, 1]).mapping { bit in
                    Channel.expression(ack: bit, rdy: bit, val: value)
                }
            })
            let TypeInvariant = Invariant()

            Do(Step.Send, over: Set<Data>([Data.d1, Data.d2, Data.d3])) { d in
                When(chan.rdy == chan.ack)
                Assign(chan.val, to: d)
                Assign(chan.rdy, to: 1 - chan.rdy)
            }
            Do(Step.Rcv) {
                When(chan.rdy != chan.ack)
                Assign(chan.ack, to: 1 - chan.ack)
            }
            TypeInvariant {
                Data.all.contains(chan.val)
                    && IntRange(0, through: 1).contains(chan.rdy)
                    && IntRange(0, through: 1).contains(chan.ack)
            }
            Validation("Upstream") {}
        }
    }
}
