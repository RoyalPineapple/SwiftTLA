import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RecordFieldAssignmentModel {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool
    }

    struct Envelope: Hashable, Sendable {
        let packet: Packet
        let untouched: Int
    }

    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("RecordFieldAssignment") { scope in
            let envelope = scope.sharedVar("envelope", initial: Envelope(packet: Packet(count: 0, ready: false), untouched: 7))
            let savedCount = scope.sharedVar("savedCount", initial: -1)
            Algorithm("RecordFieldAssignment") {
                Do(Step.advance) {
                    let saved = envelope
                    Assign(envelope.packet.count, to: 1)
                    Assign(envelope.packet.count, to: envelope.packet.count + 1)
                    Assign(envelope.packet.ready, to: true)
                    Assign(savedCount, to: saved.packet.count)
                    Stop()
                }
            }
            Invariant("Bounded") { envelope.packet.count <= 2 }
        }
    }
}
