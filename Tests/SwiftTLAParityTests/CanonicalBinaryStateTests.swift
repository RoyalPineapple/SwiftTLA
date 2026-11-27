import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct CanonicalBinaryStateTests {
    @Test("a view value has a distinct exact identity from a full state")
    func viewValueBytes() throws {
        let projection = try state([("View", .int(1))])
        let expected = Data("STLAVW01".utf8) + Data([
            0, 0, 0, 1,
            0, 0, 0, 4, 0x56, 0x69, 0x65, 0x77,
            1, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 1
        ])
        #expect(try CanonicalBinaryState.encode(projection, viewed: true) == expected)
        #expect(try CanonicalBinaryState.encode(projection) != expected)
        #expect(CanonicalBinaryState.isView(expected))
        try CanonicalBinaryState.validate(expected)
        #expect(throws: CanonicalBinaryState.CodingError.malformed) {
            try CanonicalBinaryState.encode(state([("x", .int(1))]), viewed: true)
        }
    }

    @Test("a tuple VIEW retains repeated and reordered full-state fields byte for byte")
    func encodesTupleViewFromFullState() throws {
        let a = TLAValue.function([.int(1): .set([.string("é")])])
        let b = TLAValue.tuple([.string("e\u{301}")])
        let full = try state([("z", b), ("a", a)])
        var representative = CanonicalBinaryState.Encoder()
        var key = CanonicalBinaryState.Encoder()
        try representative.encode(full, tupleView: [1, 0, 1], key: &key)
        #expect(try key.bytes == CanonicalBinaryState.encode(state([("View", .tuple([b, a, b]))]), viewed: true))
        #expect(try representative.bytes == CanonicalBinaryState.encode(full))
        #expect(throws: CanonicalBinaryState.CodingError.malformed) {
            try representative.encode(full, tupleView: [2], key: &key)
        }
    }

    @Test("a state value has a versioned, unambiguous byte identity")
    func exactStateBytes() throws {
        let projection = try state([("x", .int(1))])
        let expected = Data([
            0x53, 0x54, 0x4c, 0x41, 0x53, 0x56, 0x30, 0x31,
            0, 0, 0, 1,
            0, 0, 0, 1, 0x78,
            1, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 1
        ])
        #expect(try CanonicalBinaryState.encode(projection) == expected)
        try CanonicalBinaryState.validate(expected)
        #expect(try CanonicalBinaryState.encode(state([("x", .bool(true))])) != expected)

        var encoder = CanonicalBinaryState.Encoder()
        try encoder.encode(state([("x", .tuple([.string("a longer value"), .bool(true)]))]))
        try encoder.encode(projection)
        #expect(encoder.bytes == expected)

        let nested = Data([
            0x53, 0x54, 0x4c, 0x41, 0x53, 0x56, 0x30, 0x31,
            0, 0, 0, 1,
            0, 0, 0, 1, 0x78,
            6, 0, 0, 0, 16,
            0, 0, 0, 2,
            2, 0, 0, 0, 1, 1,
            3, 0, 0, 0, 1, 0x41
        ])
        #expect(try CanonicalBinaryState.encode(state([("x", .tuple([.bool(true), .string("A")]))])) == nested)
        try CanonicalBinaryState.validate(nested)
    }

    @Test("canonical state decoding rejects truncated and invalid UTF-8 values")
    func malformedStateBytes() throws {
        var valid = try CanonicalBinaryState.encode(state([("x", .string("value"))]))
        var truncated = valid
        truncated.removeLast()
        #expect(throws: CanonicalBinaryState.CodingError.self) {
            try CanonicalBinaryState.validate(truncated)
        }
        valid[16] = 0xff
        #expect(throws: CanonicalBinaryState.CodingError.self) {
            try CanonicalBinaryState.validate(valid)
        }
    }

    @Test("unordered values are stable while tuple order remains significant")
    func collectionIdentity() throws {
        let first = try state([
            ("z", .set([.string("b"), .string("a")])),
            ("a", .record(["right": .int(2), "left": .int(1)]))
        ])
        let reordered = try state([
            ("a", .record(["left": .int(1), "right": .int(2)])),
            ("z", .set([.string("a"), .string("b")]))
        ])
        #expect(try CanonicalBinaryState.encode(first) == CanonicalBinaryState.encode(reordered))
        #expect(try CanonicalBinaryState.encode(state([("x", .tuple([.int(1), .int(2)]))]))
            != CanonicalBinaryState.encode(state([("x", .tuple([.int(2), .int(1)]))])))
        let equivalentMembers = try state([("x", .set([
            .tuple([.int(1)]), .function([.int(1): .int(1)])
        ]))])
        let oneMember = try state([("x", .set([.tuple([.int(1)])]))])
        #expect(try CanonicalBinaryState.encode(equivalentMembers) == CanonicalBinaryState.encode(oneMember))
    }

    @Test("Unicode state names use byte order in both projection and evidence")
    func stateNameByteOrder() throws {
        let first = try state([("é", .int(1)), ("e\u{301}a", .int(2))])
        let reversed = try state([("e\u{301}a", .int(2)), ("é", .int(1))])
        #expect(first.entries.map(\.token.description) == ["e\u{301}a", "é"])
        let encoded = try CanonicalBinaryState.encode(first)
        #expect(encoded == (try CanonicalBinaryState.encode(reversed)))
        try CanonicalBinaryState.validate(encoded)
    }

    @Test("TLC-compatible function shapes share their full value identity")
    func functionIdentity() throws {
        let tuple = try state([("x", .tuple([.int(3), .int(4)]))])
        let function = try state([("x", .function([.int(2): .int(4), .int(1): .int(3)]))])
        #expect(try CanonicalBinaryState.encode(tuple) == CanonicalBinaryState.encode(function))

        let record = try state([("x", .record(["field": .bool(true)]))])
        let keyed = try state([("x", .function([.string("field"): .bool(true)]))])
        #expect(try CanonicalBinaryState.encode(record) == CanonicalBinaryState.encode(keyed))

        let modelKeyed = try state([("x", .function([.constant("p1"): .bool(true)]))])
        let expectedModelKeyed = Data([
            0x53, 0x54, 0x4c, 0x41, 0x53, 0x56, 0x30, 0x31,
            0, 0, 0, 1, 0, 0, 0, 1, 0x78,
            8, 0, 0, 0, 17, 0, 0, 0, 1,
            4, 0, 0, 0, 2, 0x70, 0x31,
            2, 0, 0, 0, 1, 1
        ])
        #expect(try CanonicalBinaryState.encode(modelKeyed) == expectedModelKeyed)

        let first = try state([("x", .function([
            .constant("p2"): .bool(false), .constant("p1"): .bool(true)
        ]))])
        let reordered = try state([("x", .function([
            .constant("p1"): .bool(true), .constant("p2"): .bool(false)
        ]))])
        let changed = try state([("x", .function([
            .constant("p1"): .bool(true), .constant("p2"): .bool(true)
        ]))])
        let encoded = try CanonicalBinaryState.encode(first)
        #expect(encoded == (try CanonicalBinaryState.encode(reordered)))
        #expect(encoded != (try CanonicalBinaryState.encode(changed)))
        try CanonicalBinaryState.validate(encoded)
    }

    @Test("generated field traversal supplies the same complete state and tuple VIEW to both consumers")
    func generatedProjectionConsumers() throws {
        let scenario = try #require(try NanoBlockchainModel.validationScenarios().first)
        let machine = try #require(try scenario.initialOutcomes().states.first)
        let projection = try machine.formalProjection(of: machine.snapshot)
        var materialized = false
        var walked = false
        var full = CanonicalBinaryState.Encoder(), key = CanonicalBinaryState.Encoder()
        try full.encode(tupleView: [3, 0, 3], key: &key, visit: {
            walked = try machine._visitFormalProjection(of: machine.snapshot, into: &$0)
            return walked
        }, projection: {
            materialized = true
            return projection
        })
        var reference = CanonicalBinaryState.Encoder(), view = CanonicalBinaryState.Encoder()
        try reference.encode(projection, tupleView: [3, 0, 3], key: &view)
        #expect(walked && !materialized)
        #expect(key.bytes == view.bytes)
        #expect(full.bytes == reference.bytes)
    }

    @Test("tuple capture reports the same nested paths and first conversion failure as formal projection")
    func projectionFailureOrder() throws {
        let field = try #require(TLAStateProjection.Token(validating: "ledger"))
        func visit<S: _NativeProjectionSink>(_ sink: inout S, duplicate: String?) throws -> Bool {
            try sink.field(field, "1invalid") { name, out in
                try out.record(_NativeProjectionRecord(["account"])) { _, child in try child.projected(.constant(name)) }
            }
            if duplicate == "set" {
                try sink.field(field, [1, 1]) { values, out in
                    try out.members(values) { item, child in try child.projected(.int(item)) }
                }
            } else if duplicate == "function" {
                let entries = [(key: 0, value: 1), (key: 0, value: 2)]
                try sink.field(field, entries) { pairs, out in
                    try out.constantFunction(pairs, key: { _ in .constant("same") },
                        value: { value, child in try child.projected(.int(value)) })
                }
            }
            return true
        }
        for (duplicate, diagnostic) in [
            (nil as String?, TLAStateProjectionDiagnostic.invalidConstant(path: "ledger.account")),
            ("set", .invalidValue(path: "duplicate formal set element")),
            ("function", .invalidValue(path: "duplicate formal function key"))
        ] {
            func projection() throws -> TLAStateProjection {
                var values = _NativeProjectionCollector()
                _ = try visit(&values, duplicate: duplicate)
                return try values.projection()
            }
            var full = CanonicalBinaryState.Encoder(), key = CanonicalBinaryState.Encoder()
            #expect(throws: diagnostic) { try projection() }
            #expect(throws: diagnostic) {
                try full.encode(tupleView: [0], key: &key, visit: { try visit(&$0, duplicate: duplicate) },
                    projection: projection)
            }
        }
    }

    @Test("distinct formal members with identical wire bytes retain the canonical set identity")
    func equivalentMemberCapture() throws {
        let token = try #require(TLAStateProjection.Token(validating: "members"))
        func visit<S: _NativeProjectionSink>(_ sink: inout S) throws -> Bool {
            try sink.field(token, [TLAValue.tuple([.int(1)]), .function([.int(1): .int(1)])]) { values, out in
                try out.members(values) { member, child in try child.projected(member) }
            }
            return true
        }
        var values = _NativeProjectionCollector()
        _ = try visit(&values)
        let projection = try values.projection()
        var full = CanonicalBinaryState.Encoder(), key = CanonicalBinaryState.Encoder()
        try full.encode(tupleView: [0, 0], key: &key, visit: visit, projection: { projection })
        var reference = CanonicalBinaryState.Encoder(), view = CanonicalBinaryState.Encoder()
        try reference.encode(projection, tupleView: [0, 0], key: &view)
        #expect(key.bytes == view.bytes)
        #expect(full.bytes == reference.bytes)
    }

    private func state(_ bindings: [(String, TLAValue)]) throws -> TLAStateProjection {
        try TLAStateProjection(validating: bindings.map { name, value in
            TLAStateProjection.Entry(token: TLAStateProjection.Token(validating: name)!, value: value)
        })
    }
}
