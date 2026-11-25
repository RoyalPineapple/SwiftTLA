import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BoundedFIFOModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case m1, m2, m3
        package static var defaultValue: Self { .m1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
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
            let Message = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([Set<Datum>([Datum.m1, Datum.m2, Datum.m3])]))
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
            Constraint(q.count <= qLen)
            Invariant("TypeInvariant") {
                Message.contains(`in`.val) && (0...1).contains(`in`.rdy) && (0...1).contains(`in`.ack)
                    && Message.contains(out.val) && (0...1).contains(out.rdy) && (0...1).contains(out.ack)
                    && Sequences(of: Message).contains(q)
            }
            Validation("Upstream") {
                Bind(Message, to: Set<Datum>([Datum.m1, Datum.m2, Datum.m3]))
                Bind(qLen, to: 3)
            }
        }
    }
}
