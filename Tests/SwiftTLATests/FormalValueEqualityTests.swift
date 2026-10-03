import Testing
@testable import SwiftTLA

struct FormalValueEqualityTests {
    @Test("formal equality compares function contents without changing compiler identity")
    func comparesRepresentationsExtensionally() throws {
        let pairs: [(TLAValue, TLAValue)] = [
            (.tuple([]), .function([:])),
            (.record([:]), .tuple([])),
            (.tuple([.int(7), .int(3)]), .function([.int(1): .int(7), .int(2): .int(3)])),
            (.record(["item": .tuple([.int(7)])]),
                .function([.string("item"): .function([.int(1): .int(7)])])),
            (.set([.tuple([.int(7)]), .function([.int(1): .int(7)])]), .set([.tuple([.int(7)])]))
        ]
        for (left, right) in pairs {
            #expect(CompiledValue(formal: left) != CompiledValue(formal: right))
            for (a, b) in [(left, right), (right, left)] {
                #expect(try compiledValue(.equal(.value(a), .value(b))) == .bool(true))
                #expect(try compiledValue(.notEqual(.value(a), .value(b))) == .bool(false))
            }
        }
    }

    @Test("formal equality retains domains, order, byte-exact strings, and model-value identity")
    func rejectsDifferentValues() throws {
        let pairs: [(TLAValue, TLAValue)] = [
            (.tuple([.int(7)]), .function([.int(0): .int(7)])),
            (.tuple([.int(7), .int(3)]), .function([.int(1): .int(3), .int(2): .int(7)])),
            (.record(["item": .int(7)]), .function([.string("other"): .int(7)])),
            (.set([.int(1)]), .set([.int(1), .int(2)])),
            (.string("é"), .string("e\u{301}")),
            (.constant("item"), .string("item"))
        ]
        for (left, right) in pairs {
            for (a, b) in [(left, right), (right, left)] {
                #expect(try compiledValue(.equal(.value(a), .value(b))) == .bool(false))
                #expect(try compiledValue(.notEqual(.value(a), .value(b))) == .bool(true))
            }
        }
    }
}
