import Testing
@testable import SwiftTLA

struct GeneratedRecordProjectionTests {
    @Test("generated records reject malformed formal values, including nested fields")
    func rejectsMalformedValues() throws {
        typealias Packet = SymbolicRecordConstructionModel.Packet
        let valid: TLAValue = .record([
            "payload": .record(["value": .int(2)]),
            "ready": .bool(true)
        ])
        let packet = try #require(Packet(formalValue: valid))
        #expect(packet == .init(payload: .init(value: 2), ready: true))
        #expect(packet.tlaValue == valid)

        let malformed: [TLAValue] = [
            .record(["payload": .record(["value": .bool(false)]), "ready": .bool(true)]),
            .record(TLARecord([
                .init("payload", .record(["value": .int(2)])),
                .init("payload", .record(["value": .int(3)])),
                .init("ready", .bool(true))
            ])),
            .record(["payload": .record(["value": .int(2)])]),
            .record(["payload": .record(["value": .int(2)]), "ready": .bool(true), "extra": .int(1)]),
            .record(["payload": .record(["value": .int(2), "extra": .int(1)]), "ready": .bool(true)])
        ]
        for value in malformed {
            #expect(Packet(formalValue: value) == nil)
        }
    }
}
