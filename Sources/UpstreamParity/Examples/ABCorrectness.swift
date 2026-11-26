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
            let dataValues = scope.parameter(tlaName: "Data", as: Set<Datum>.self, in: Set<Set<Datum>>([Set<Datum>([Datum.d1, Datum.d2])]))
            let senderBit = scope.sharedVar(tlaName: "sBit", initiallyIn: 0...1)
            let acknowledgedBit = scope.sharedVar(tlaName: "sAck", initial: senderBit)
            let receiverBit = scope.sharedVar(tlaName: "rBit", initial: senderBit)
            let sent = scope.sharedVar(initiallyIn: dataValues)
            let receivedValue = scope.sharedVar(tlaName: "rcvd", initiallyIn: dataValues)

            Do(Step.send, over: dataValues) { value in
                When(acknowledgedBit == senderBit)
                sent.set(value)
                senderBit.set(1 - senderBit)
            }
            let receive = Do(Step.receive, when: receiverBit != senderBit) {
                receiverBit.set(senderBit)
                receivedValue.set(sent)
            }
            let acknowledge = Do(Step.acknowledge, when: receiverBit != acknowledgedBit) {
                acknowledgedBit.set(receiverBit)
            }
            WeakFairness(receive)
            WeakFairness(acknowledge)

            Invariant("TypeInv") {
                (0...1).contains(senderBit) && (0...1).contains(acknowledgedBit) && (0...1).contains(receiverBit)
                    && dataValues.contains(sent) && dataValues.contains(receivedValue)
            }
            Validation("Upstream") { Bind(dataValues, to: Set<Datum>([Datum.d1, Datum.d2])) }
        }
    }
}
