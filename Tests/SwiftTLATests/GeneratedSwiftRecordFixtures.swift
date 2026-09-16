import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedSwiftRecord {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool
    }

    struct UnusedHelper {
        let value: Int
        init(value: Int) { self.value = value + 1 }
    }

    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedSwiftRecord") { scope in
            let packet = scope.sharedVar("packet", initial: Packet(count: 0, ready: false))
            let previousCount = scope.sharedVar("previousCount", initial: -1)
            Algorithm("GeneratedSwiftRecord") {
                Do(Step.advance) {
                    let saved = packet
                    When(saved.count == 0)
                    Assign(packet, to: Packet(count: 1, ready: true))
                    Assign(previousCount, to: saved.count)
                    Stop()
                }
            }
            Invariant("Bounded") { packet.count <= 1 }
        }
    }
}
