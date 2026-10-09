import Testing
import SwiftTLAMacros
@testable import SwiftTLA

struct FormalValueProjectionTests {
    @Test("upstream empty sequences project through nested typed collections and records")
    func emptySequenceRepresentations() throws {
        let emptyValues: [TLAValue] = [.tuple([]), .function([:]), .record(TLARecord([]))]
        for empty in emptyValues {
            let sequence = try #require(ZeroBasedSequence<Int>(formalValue: empty))
            #expect(sequence.tlaValue == .function([:]))
            #expect([ZeroBasedSequence<Int>](formalValue: .tuple([empty])) == [sequence])
            #expect(Set<ZeroBasedSequence<Int>>(formalValue: .set([empty])) == Set([sequence]))
            let values = try #require([Int: ZeroBasedSequence<Int>](formalValue: .function([.int(3): empty])))
            #expect(values[3] == sequence)
            let keys = try #require([ZeroBasedSequence<Int>: Int](formalValue: .function([empty: .int(3)])))
            #expect(keys[sequence] == 3)
            let rotation = try #require(ZSequences.Rotation<Int>(formalValue: .record(TLARecord([
                .init("shift", .int(0)), .init("seq", empty)
            ]))))
            #expect(rotation.shift == 0 && rotation.seq == sequence)
        }
    }

    @Test("zero-based projections reject invalid domains and element types")
    func rejectsInvalidSequences() throws {
        let valid = try #require(ZeroBasedSequence<Int>(formalValue: .function([.int(0): .int(7), .int(1): .int(3)])))
        #expect(valid.element(at: 0) == 7 && valid.element(at: 1) == 3)
        let invalid: [TLAValue] = [
            .set([]), .tuple([.int(1)]), .record(TLARecord([.init("value", .int(1))])),
            .function([.int(1): .int(1)]), .function([.int(-1): .int(1)]),
            .function([.int(0): .int(1), .int(2): .int(2)]),
            .function([.string("0"): .int(1)]), .function([.int(0): .string("1")])
        ]
        for value in invalid {
            #expect(ZeroBasedSequence<Int>(formalValue: value) == nil)
        }
    }

    @Test("typed projections reject element decoders that change formal values")
    func rejectsLossyElements() {
        #expect(ZeroBasedSequence<CollidingSetMember>(formalValue: .function([.int(0): .int(1)])) == nil)
        #expect([CollidingSetMember](formalValue: .tuple([.int(1)])) == nil)
        #expect(Set<CollidingSetMember>(formalValue: .set([.int(1)])) == nil)
        #expect([Int: CollidingSetMember](formalValue: .function([.int(0): .int(1)])) == nil)
        #expect([CollidingSetMember: Int](formalValue: .function([.int(1): .int(0)])) == nil)
        #expect(LossyMemberProjectionRecord(formalValue: .record(TLARecord([.init("member", .int(1))]))) == nil)
    }

    @Test("typed sets and dictionaries reject colliding projected members and keys")
    func rejectsProjectionCollisions() {
        let tuple = TLAValue.tuple([])
        let function = TLAValue.function([:])
        #expect(Set<ZeroBasedSequence<Int>>(formalValue: .set([tuple, function])) == nil)
        #expect([ZeroBasedSequence<Int>: Int](formalValue: .function([tuple: .int(1), function: .int(2)])) == nil)
    }

    @Test("nominal projections retain byte-exact strings and distinguish model values")
    func rejectsChangedScalarIdentity() {
        #expect(ByteExactProjectionCase(formalValue: .string("\u{e9}")) == .composed)
        #expect(ByteExactProjectionCase(formalValue: .string("e\u{301}")) == nil)
        #expect(ByteExactProjectionCase(formalValue: .constant("\u{e9}")) == nil)
    }
}
