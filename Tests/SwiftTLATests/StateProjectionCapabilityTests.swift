import Testing
@testable import SwiftTLA

struct StateProjectionCapabilityTests {
    @Test("Nested record fields cannot silently duplicate a formal key")
    func rejectsDuplicateRecordFields() throws {
        let token = try #require(TLAStateProjection.Token(validating: "state"))
        let duplicate = TLAValue.record(TLARecord([.init("value", .int(1)), .init("value", .int(2))]))
        #expect(throws: TLAStateProjectionDiagnostic.invalidKey(path: "state[0].value")) {
            try TLAStateProjection(validating: [.init(token: token, value: .tuple([duplicate]))])
        }
    }

    @Test("State projections require validated tokens and safely enumerate entries")
    func stateProjectionGuardsFormalKeys() throws {
        let count = try #require(TLAStateProjection.Token(validating: "count"))
        let mode = try #require(TLAStateProjection.Token(validating: "mode"))
        let state = try TLAStateProjection(validating: [
            .init(token: mode, value: .string("idle")),
            .init(token: count, value: .int(2))
        ])

        #expect(TLAStateProjection.Token(validating: "") == nil)
        #expect(TLAStateProjection.Token(validating: "2count") == nil)
        #expect(TLAStateProjection.Token(validating: "invalid-key") == nil)
        #expect(state.value(for: count) == .int(2))
        let missing = try #require(TLAStateProjection.Token(validating: "missing"))
        #expect(state.value(for: missing) == nil)
        #expect(state.entries.map(\.token.description) == ["count", "mode"])
        #expect(state.description == "count = 2, mode = \"idle\"")
    }

}
