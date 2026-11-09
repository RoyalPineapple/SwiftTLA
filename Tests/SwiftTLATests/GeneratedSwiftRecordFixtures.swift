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

    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedSwiftRecord") { scope in
            let packet = scope.sharedVar(_name: "packet", initial: Packet(count: 0, ready: false))
            let previousCount = scope.sharedVar(_name: "previousCount", initial: -1)
            let generatedSwiftRecord = Algorithm(label: "GeneratedSwiftRecord") {
                Do(Step.advance) {
                    let saved = packet
                    When(saved.count == 0)
                    Assign(packet, to: Packet(count: 1, ready: true))
                    Assign(previousCount, to: saved.count)
                    Stop()
                }
            }
            generatedSwiftRecord
            Invariant("Bounded") {
                packet.count <= 1
                    && If(packet.ready,
                        then: packet != Packet(count: 9, ready: true)
                            && SequenceMapping(length: 1) { _ in packet } != [Packet(count: 9, ready: true)],
                        else: !(packet == Packet(count: 9, ready: false)))
            }
        }
    }
}
