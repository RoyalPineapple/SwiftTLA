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
            Algorithm("GeneratedSwiftRecord") {
                Do(Step.advance) {
                    Assign(packet, to: Packet(count: 1, ready: true))
                    Stop()
                }
            }
        }
    }
}
