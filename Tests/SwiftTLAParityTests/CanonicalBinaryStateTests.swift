import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct CanonicalBinaryStateTests {
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

    private func state(_ bindings: [(String, TLAValue)]) throws -> TLAStateProjection {
        try TLAStateProjection(validating: bindings.map { name, value in
            TLAStateProjection.Entry(token: TLAStateProjection.Token(validating: name)!, value: value)
        })
    }
}
