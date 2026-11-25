import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BoundedFIFOModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case m1, m2, m3
        case ap1 = "m1_OF_MSG", ap2 = "m2_OF_MSG", ap3 = "m3_OF_MSG"
        package static var defaultValue: Self { .m1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .m1, .m2, .m3: .constant(rawValue)
            case .ap1, .ap2, .ap3: .string(rawValue)
            }
        }
    }

    package struct Channel: Hashable, Sendable {
        package let val: Datum
        package let rdy: Int
        package let ack: Int
    }

    package enum Step: String, CaseIterable {
        case send = "SSend", enqueue = "BufRcv", dequeue = "BufSend", receive = "RRcv"
    }

    package static var spec: TLASpec {
        #spec("MCInnerFIFO") { scope in
            Extends(.naturals, .sequences)
            let Message = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([
                Set<Datum>([Datum.m1, Datum.m2, Datum.m3]), Set<Datum>([Datum.ap1, Datum.ap2, Datum.ap3])
            ]))
            let constrainQueue = scope.parameter(as: Bool.self)
            let qLen = scope.parameter(as: Int.self, in: 3...3)
            let initialChannels = Message.flatMapping { value in
                Set<Int>([0, 1]).mapping { bit in
                    Channel.expression(val: value, rdy: bit, ack: bit)
                }
            }
            let `in` = scope.sharedVar(initiallyIn: initialChannels)
            let out = scope.sharedVar(initiallyIn: initialChannels)
            let q = scope.sharedVar(initial: [Datum]())

            Do(Step.send, over: Message) { message in
                When(`in`.ack == `in`.rdy)
                `in`.val.set(message)
                `in`.rdy.set(1 - `in`.rdy)
            }
            Do(Step.enqueue, when: `in`.rdy != `in`.ack) {
                `in`.ack.set(1 - `in`.ack)
                q.set(q.appending(`in`.val))
            }
            Do(Step.dequeue, when: !q.isEmpty && out.rdy == out.ack) {
                out.val.set(q.head())
                out.rdy.set(1 - out.rdy)
                q.set(q.tail())
            }
            Do(Step.receive, when: out.rdy != out.ack) {
                out.ack.set(1 - out.ack)
            }
            Constraint(!constrainQueue || q.count <= qLen)
            let channelsAreValid = Message.contains(`in`.val) && (0...1).contains(`in`.rdy) && (0...1).contains(`in`.ack)
                && Message.contains(out.val) && (0...1).contains(out.rdy) && (0...1).contains(out.ack)
            let TypeInvariant = Invariant()
            TypeInvariant { channelsAreValid && Sequences(of: Message).contains(q) }
            let ChannelTypeInvariants = Invariant()
            ChannelTypeInvariants { channelsAreValid && q.count <= qLen }
            Validation("Upstream") {
                Bind(Message, to: Set<Datum>([Datum.m1, Datum.m2, Datum.m3]))
                Bind(qLen, to: 3)
                Bind(constrainQueue, to: true)
            }.checking(only: [TypeInvariant])
            Validation("APMCInnerFIFO") {
                Bind(Message, to: Set<Datum>([Datum.ap1, Datum.ap2, Datum.ap3]))
                Bind(qLen, to: 3)
                Bind(constrainQueue, to: false)
            }.checking(only: [ChannelTypeInvariants]).checkingMode(.decisiveCounterexample)
                .expect(ChannelTypeInvariants, .violated)
        }
    }
}
