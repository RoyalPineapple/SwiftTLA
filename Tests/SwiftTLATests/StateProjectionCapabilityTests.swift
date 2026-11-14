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

        let distinct = TLAValue.record(TLARecord([
            .init("\u{00E9}", .int(1)), .init("e\u{301}", .int(2))
        ]))
        let projected = try TLAStateProjection(validating: [.init(token: token, value: .tuple([distinct]))])
        #expect(projected.value(for: token) == .tuple([distinct]))
    }

    @Test("Set projections retain complete values and locate invalid members")
    func validatesSetMembers() throws {
        let token = try #require(TLAStateProjection.Token(validating: "state"))
        let valid = TLAValue.set([.int(1), .int(2)])
        let projection = try TLAStateProjection(validating: [.init(token: token, value: valid)])
        #expect(projection.value(for: token) == valid)

        #expect(throws: TLAStateProjectionDiagnostic.invalidConstant(path: "state{0}")) {
            try TLAStateProjection(validating: [
                .init(token: token, value: .set([.constant("invalid-key")]))
            ])
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

        let composed = TLAJSONValue.string("é")
        let decomposed = TLAJSONValue.string("e\u{301}")
        #expect("é" == "e\u{301}")
        for (left, right) in [
            (composed, decomposed),
            (.array([composed]), .array([decomposed])),
            (.object(["text": composed]), .object(["text": decomposed])),
            (.object(["é": .integer(1)]), .object(["e\u{301}": .integer(1)])),
            (.integer(1), .boolean(true)), (.array([]), .object([:])),
            (.array([.integer(1), .integer(2)]), .array([.integer(2), .integer(1)])),
            (.object(["one": .integer(1)]), .object(["one": .integer(1), "two": .integer(2)]))
        ] {
            #expect(left != right)
            #expect(right != left)
        }
        #expect(TLAJSONValue.string("é") == .string("é"))
        #expect(TLAJSONValue.array([.integer(1), decomposed]) == .array([.integer(1), .string("e\u{301}")]))
        #expect(TLAJSONValue.object(["one": .integer(1), "two": .array([decomposed])])
            == .object(["two": .array([.string("e\u{301}")]), "one": .integer(1)]))

        let composedName = "\u{00E9}"
        let decomposedName = "e\u{301}"
        let composedKey = try #require(TLAStateProjection.Token(validating: composedName))
        let decomposedKey = try #require(TLAStateProjection.Token(validating: decomposedName))
        let separate = try TLAStateProjection(validating: [.init(token: composedKey, value: .int(1))])
        #expect(separate.value(for: decomposedKey) == nil)
        let imported = try TLAJSONStateProjection(validatingJSON: [composedName: 1])
        #expect(imported.value(for: decomposedKey) == nil)

        let distinctKeys = try TLAStateProjection(validating: [
            .init(token: composedKey, value: .int(1)), .init(token: decomposedKey, value: .int(2))
        ])
        #expect(distinctKeys.value(for: composedKey) == .int(1))
        #expect(distinctKeys.value(for: decomposedKey) == .int(2))
        #expect(distinctKeys.entries.map { Array($0.token.description.utf8) }
            == [Array(decomposedName.utf8), Array(composedName.utf8)])
        #expect(throws: TLAStateProjectionDiagnostic.invalidKey(path: composedName)) {
            try TLAStateProjection(validating: [
                .init(token: composedKey, value: .int(1)), .init(token: composedKey, value: .int(2))
            ])
        }
    }

}
