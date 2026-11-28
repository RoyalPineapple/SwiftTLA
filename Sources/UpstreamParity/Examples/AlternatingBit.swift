// A sender resends data until it receives an acknowledgment with the matching bit over a lossy
// channel.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/TLC/AlternatingBit.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AlternatingBitModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2
        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case send = "SndNewValue", resend = "ReSndMsg", receive = "RcvMsg"
        case sendAck = "SndAck", receiveAck = "RcvAck", loseMsg = "LoseMsg", loseAck = "LoseAck"
    }

    package static var spec: TLASpec {
        #spec("MCAlternatingBit") { scope in
            Extends(.naturals, .sequences)
            let dataValues = scope.parameter(tlaName: "Data", as: Set<Datum>.self, in: Set<Set<Datum>>([Set<Datum>([Datum.d1, Datum.d2])]))
            let messageQueueLimit = scope.parameter(tlaName: "msgQLen", as: Int.self, in: 2...2)
            let acknowledgementQueueLimit = scope.parameter(tlaName: "ackQLen", as: Int.self, in: 2...2)
            let messageQueue = scope.sharedVar(tlaName: "msgQ", initial: [Pair<Int, Datum>]())
            let acknowledgementQueue = scope.sharedVar(tlaName: "ackQ", initial: [Int]())
            let senderBit = scope.sharedVar(tlaName: "sBit", initiallyIn: 0...1)
            let acknowledgedBit = scope.sharedVar(tlaName: "sAck", initial: senderBit)
            let receiverBit = scope.sharedVar(tlaName: "rBit", initial: senderBit)
            let sent = scope.sharedVar(initiallyIn: dataValues)
            let receivedValue = scope.sharedVar(tlaName: "rcvd", initiallyIn: dataValues)

            Do(Step.send, over: dataValues) { value in
                When(acknowledgedBit == senderBit)
                messageQueue.set(messageQueue.appending(Pair<Int, Datum>.literal(1 - senderBit, value)))
                sent.set(value)
                senderBit.set(1 - senderBit)
            }
            let resend = Do(Step.resend, when: acknowledgedBit != senderBit) {
                messageQueue.set(messageQueue.appending(Pair<Int, Datum>.literal(senderBit, sent)))
            }
            let receive = Do(Step.receive, when: !messageQueue.isEmpty) {
                receiverBit.set(messageQueue.head().first())
                receivedValue.set(messageQueue.head().second())
                messageQueue.set(messageQueue.tail())
            }
            let sendAck = Do(Step.sendAck) { acknowledgementQueue.set(acknowledgementQueue.appending(receiverBit)) }
            let receiveAck = Do(Step.receiveAck, when: !acknowledgementQueue.isEmpty) {
                acknowledgedBit.set(acknowledgementQueue.head())
                acknowledgementQueue.set(acknowledgementQueue.tail())
            }
            Do(Step.loseMsg) {
                With(IntRange(1, through: messageQueue.count)) { i in messageQueue.set(messageQueue.removing(at: i)) }
            }
            Do(Step.loseAck) {
                With(IntRange(1, through: acknowledgementQueue.count)) { i in acknowledgementQueue.set(acknowledgementQueue.removing(at: i)) }
            }
            WeakFairness(resend)
            WeakFairness(sendAck)
            StrongFairness(receive)
            StrongFairness(receiveAck)
            Constraint(messageQueue.count <= messageQueueLimit && acknowledgementQueue.count <= acknowledgementQueueLimit)
            let messages = Set<Int>([0, 1]).flatMapping { bit in
                dataValues.mapping { value in Pair<Int, Datum>.literal(bit, value) }
            }
            Invariant("ABTypeInv") {
                Sequences(of: messages).contains(messageQueue) && Sequences(of: Set<Int>([0, 1])).contains(acknowledgementQueue)
                (0...1).contains(senderBit) && (0...1).contains(acknowledgedBit) && (0...1).contains(receiverBit)
                dataValues.contains(sent) && dataValues.contains(receivedValue)
            }
            let abstraction = Instance(of: ABCorrectnessModel.self) { Bind(\.dataValues, projecting: dataValues) }
            Refinement("ABCSpec", instance: abstraction) {
                Map(\.senderBit, projecting: senderBit)
                Map(\.acknowledgedBit, projecting: acknowledgedBit)
                Map(\.receiverBit, projecting: receiverBit)
                Map(\.sent, projecting: sent)
                Map(\.receivedValue, projecting: receivedValue)
            }
            let SentLeadsToRcvd = Temporal()
            SentLeadsToRcvd(forEach: dataValues) { d in
                .leadsTo(sent == d && senderBit != acknowledgedBit, receivedValue == d)
            }
            Validation("Upstream") {
                Bind(dataValues, to: Set<Datum>([Datum.d1, Datum.d2]))
                Bind(messageQueueLimit, to: 2)
                Bind(acknowledgementQueueLimit, to: 2)
            }
        }
    }
}
