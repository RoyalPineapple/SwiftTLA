// A sender and receiver alternate a bit to distinguish a new message from a retransmission.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/TLC/ABCorrectness.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ABCorrectnessModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2
        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Step: String, CaseIterable {
        case send = "CSndNewValue"
        case receive = "CRcvMsg"
        case acknowledge = "CRcvAck"
    }

    package static var spec: TLASpec {
        #spec("ABCorrectness") { scope in
            Extends(.naturals)
            let Data = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([Set<Datum>([Datum.d1, Datum.d2])]))
            let sBit = scope.sharedVar(initiallyIn: 0...1)
            let sAck = scope.sharedVar(initial: sBit)
            let rBit = scope.sharedVar(initial: sBit)
            let sent = scope.sharedVar(initiallyIn: Data)
            let rcvd = scope.sharedVar(initiallyIn: Data)

            Do(Step.send, over: Data) { value in
                When(sAck == sBit)
                sent.set(value)
                sBit.set(1 - sBit)
            }
            let receive = Do(Step.receive, when: rBit != sBit) {
                rBit.set(sBit)
                rcvd.set(sent)
            }
            let acknowledge = Do(Step.acknowledge, when: rBit != sAck) {
                sAck.set(rBit)
            }
            WeakFairness(receive)
            WeakFairness(acknowledge)

            Invariant("TypeInv") {
                (0...1).contains(sBit) && (0...1).contains(sAck) && (0...1).contains(rBit)
                    && Data.contains(sent) && Data.contains(rcvd)
            }
            Validation("Upstream") { Bind(Data, to: Set<Datum>([Datum.d1, Datum.d2])) }
        }
    }
}
