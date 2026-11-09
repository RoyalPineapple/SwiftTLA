import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedSwiftRecord {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.ready == rhs.ready }
        func hash(into hasher: inout Hasher) { hasher.combine(ready) }
    }

    struct UnusedHelper {
        let value: Int
        init(value: Int) { self.value = value + 1 }
    }

    typealias Swift = UnusedHelper

    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedSwiftRecord") { scope in
            let packet = scope.sharedVar(_name: "packet", initial: Packet(count: 0, ready: false))
            let previousCount = scope.sharedVar(_name: "previousCount", initial: -1)
            let history = scope.sharedVar(initial: [Packet(count: 0, ready: false)])
            let archive = scope.sharedVar(initial: Set<Packet>([
                Packet(count: 0, ready: false), Packet(count: 1, ready: true)
            ]))
            let generatedSwiftRecord = Algorithm(label: "GeneratedSwiftRecord") {
                Each(Set<Int>([0]), scoped: { _, process in
                    let localPacket = process.localVar(initial: Packet(count: 0, ready: false))
                    Do(Step.advance) {
                        let saved = packet
                        When(saved.count == 0)
                        With(IntRange(1, through: 2)) { input in
                            Assign(packet, to: Packet.expression(count: input, ready: true))
                            Assign(history, to: SequenceMapping(length: 1) { _ in
                                Packet.expression(count: input, ready: true)
                            })
                            With(IntRange(1, through: 2)) { hidden in
                                Assign(localPacket, to: Packet.expression(count: hidden, ready: false))
                            }
                        }
                        Assign(previousCount, to: saved.count)
                        Stop()
                    }
                })
            }
            generatedSwiftRecord
            Invariant("Bounded") {
                packet.count <= 1 && archive.cardinality == 2
                    && If(packet.ready,
                        then: packet != Packet(count: 9, ready: true)
                            && SequenceMapping(length: 1) { _ in packet } != [Packet(count: 9, ready: true)],
                        else: !(packet == Packet(count: 9, ready: false)))
            }
        }
    }
}
