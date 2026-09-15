@testable import SwiftTLA
import Testing

@Suite struct CollectionCardinalityBoundaryTests {
    @Test("powerset cardinalities must fit a positive collection count")
    func rejectsUnrepresentablePowersets() {
        for count in [Int.bitWidth - 1, Int.bitWidth] {
            let members = StateExpr.setLiteral((0..<count).map { .int($0) })
            #expect(throws: EvalError.powerSetTooLarge(actualCount: count, maximumCount: Int.bitWidth - 2)) {
                try compiledValue(.powerSet(members))
            }
        }
    }

    @Test("integer ranges reject unrepresentable counts before iteration")
    func rejectsUnrepresentableRanges() {
        for lower in [Int.min, 0] {
            #expect(throws: EvalError.collectionCardinalityOverflow(.integerRange, operands: [lower, Int.max])) {
                try compiledValue(.integerRange(.int(lower), .int(Int.max)))
            }
        }
    }

    @Test("function spaces reject unrepresentable counts before expansion")
    func rejectsUnrepresentableFunctionSpaces() {
        let count = Int.bitWidth - 1
        let domain = StateExpr.setLiteral((0..<count).map { .int($0) })
        #expect(throws: EvalError.collectionCardinalityOverflow(.functionSet, operands: [count, 2])) {
            try compiledValue(.functionSet(domain, .setLiteral([.int(0), .int(1)])))
        }
    }

    @Test("empty collections and short ranges at integer boundaries remain exact")
    func representableCollections() throws {
        #expect(try compiledValue(.powerSet(.setLiteral([]))) == .set([.set([])]))
        #expect(try compiledValue(.integerRange(.int(2), .int(1))) == .set([]))
        #expect(try compiledValue(.integerRange(.int(Int.max - 1), .int(Int.max))) == .set([.int(Int.max - 1), .int(Int.max)]))
        #expect(try compiledValue(.integerRange(.int(Int.min), .int(Int.min + 1))) == .set([.int(Int.min), .int(Int.min + 1)]))
        #expect(try compiledValue(.functionSet(.setLiteral([]), .setLiteral([]))) == .set([.function([:])]))
        #expect(try compiledValue(.functionSet(.setLiteral([.int(1)]), .setLiteral([]))) == .set([]))
    }

    @Test("function-space membership validates the space before evaluating its candidate")
    func membershipFailureOrder() {
        let candidate = StateExpr.functionLiteral(.setLiteral([.int(0)]), "key", .divide(.int(1), .int(0)))
        let count = Int.bitWidth - 1
        let largeDomain = StateExpr.setLiteral((0..<count).map { .int($0) })
        #expect(throws: EvalError.collectionCardinalityOverflow(.functionSet, operands: [count, 2])) {
            try compiledValue(.in(candidate, .functionSet(largeDomain, .setLiteral([.int(0), .int(1)]))))
        }
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try compiledValue(.in(candidate, .functionSet(
                .setLiteral([.add(.int(Int.max), .int(1))]),
                .setLiteral([.divide(.int(1), .int(0))]))))
        }
        #expect(throws: EvalError.divisionByZero) {
            try compiledValue(.in(candidate, .functionSet(.setLiteral([.int(0)]), .setLiteral([]))))
        }
    }

    @Test("an empty function domain still evaluates its range")
    func emptyDomainDoesNotSkipRange() {
        #expect(throws: EvalError.divisionByZero) {
            try compiledValue(.in(.value(.function([:])), .functionSet(
                .setLiteral([]), .setLiteral([.divide(.int(1), .int(0))]))))
        }
    }
}
