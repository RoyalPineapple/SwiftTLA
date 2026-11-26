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
            let Data = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([Set<Datum>([Datum.d1, Datum.d2])]))
            let msgQLen = scope.parameter(as: Int.self, in: 2...2)
            let ackQLen = scope.parameter(as: Int.self, in: 2...2)
            let msgQ = scope.sharedVar(initial: [Pair<Int, Datum>]())
            let ackQ = scope.sharedVar(initial: [Int]())
            let sBit = scope.sharedVar(initiallyIn: 0...1)
            let sAck = scope.sharedVar(initial: sBit)
            let rBit = scope.sharedVar(initial: sBit)
            let sent = scope.sharedVar(initiallyIn: Data)
            let rcvd = scope.sharedVar(initiallyIn: Data)

            Do(Step.send, over: Data) { value in
                When(sAck == sBit)
                msgQ.set(msgQ.appending(Pair<Int, Datum>.literal(1 - sBit, value)))
                sent.set(value)
                sBit.set(1 - sBit)
            }
            let resend = Do(Step.resend, when: sAck != sBit) {
                msgQ.set(msgQ.appending(Pair<Int, Datum>.literal(sBit, sent)))
            }
            let receive = Do(Step.receive, when: !msgQ.isEmpty) {
                rBit.set(msgQ.head().first())
                rcvd.set(msgQ.head().second())
                msgQ.set(msgQ.tail())
            }
            let sendAck = Do(Step.sendAck) { ackQ.set(ackQ.appending(rBit)) }
            let receiveAck = Do(Step.receiveAck, when: !ackQ.isEmpty) {
                sAck.set(ackQ.head())
                ackQ.set(ackQ.tail())
            }
            Do(Step.loseMsg) {
                With(IntRange(1, through: msgQ.count)) { i in msgQ.set(msgQ.removing(at: i)) }
            }
            Do(Step.loseAck) {
                With(IntRange(1, through: ackQ.count)) { i in ackQ.set(ackQ.removing(at: i)) }
            }
            WeakFairness(resend)
            WeakFairness(sendAck)
            StrongFairness(receive)
            StrongFairness(receiveAck)
            Constraint(msgQ.count <= msgQLen && ackQ.count <= ackQLen)
            let messages = Set<Int>([0, 1]).flatMapping { bit in
                Data.mapping { value in Pair<Int, Datum>.literal(bit, value) }
            }
            Invariant("ABTypeInv") {
                Sequences(of: messages).contains(msgQ) && Sequences(of: Set<Int>([0, 1])).contains(ackQ)
                (0...1).contains(sBit) && (0...1).contains(sAck) && (0...1).contains(rBit)
                Data.contains(sent) && Data.contains(rcvd)
            }
            let abstraction = Instance(of: ABCorrectnessModel.self) { Bind(\.Data, projecting: Data) }
            Refinement("ABCSpec", instance: abstraction) {
                Map(\.sBit, projecting: sBit)
                Map(\.sAck, projecting: sAck)
                Map(\.rBit, projecting: rBit)
                Map(\.sent, projecting: sent)
                Map(\.rcvd, projecting: rcvd)
            }
            let SentLeadsToRcvd = Temporal()
            SentLeadsToRcvd(forEach: Data) { d in
                .leadsTo(sent == d && sBit != sAck, rcvd == d)
            }
            Validation("Upstream") {
                Bind(Data, to: Set<Datum>([Datum.d1, Datum.d2]))
                Bind(msgQLen, to: 2)
                Bind(ackQLen, to: 2)
            }
        }
    }
}
