@testable import SwiftTLA
import Testing

@Suite struct FunctionUpdateDomainTests {
    @Test("EXCEPT replaces function values without extending the domain")
    func functionUpdates() throws {
        let original = TLAValue.function([.int(1): .int(10)])
        #expect(try compiledValue(.except(.value(original), .int(1), .int(20))) == .function([.int(1): .int(20)]))
        #expect(try compiledValue(.except(.value(original), .int(2), .int(20))) == original)
        #expect(try compiledValue(.except(.value(.function([:])), .int(1), .int(20))) == .function([:]))
    }

    @Test("EXCEPT replaces record fields without adding fields")
    func recordUpdates() throws {
        let original = TLAValue.record(["item": .int(10)])
        #expect(try compiledValue(.except(.value(original), .value(.string("item")), .int(20))) == .record(["item": .int(20)]))
        #expect(try compiledValue(.except(.value(original), .value(.string("missing")), .int(20))) == original)
        #expect(try compiledValue(.except(.value(.record([:])), .value(.string("item")), .int(20))) == .record([:]))
    }

    @Test("EXCEPT supports sequence functions and preserves their domain")
    func sequenceUpdates() throws {
        let original = TLAValue.tuple([.int(10), .int(20)])
        #expect(try compiledValue(.except(.value(original), .int(1), .int(30))) == .tuple([.int(30), .int(20)]))
        #expect(try compiledValue(.except(.value(original), .int(2), .int(30))) == .tuple([.int(10), .int(30)]))
        for index in [Int.min, 0, 3, Int.max] {
            #expect(try compiledValue(.except(.value(original), .int(index), .int(30))) == original)
        }
        #expect(try compiledValue(.except(.tupleLiteral([]), .int(1), .int(30))) == .tuple([]))
        #expect(throws: EvalError.expected(.integer, actual: [.string("item")])) {
            try compiledValue(.except(.value(original), .value(.string("item")), .int(30)))
        }
    }
}
