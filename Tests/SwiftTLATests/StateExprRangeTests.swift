import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprRangeTests {
    @Test("integer ranges preserve bounds without expansion")
    func integerRangesPreserveBoundsWithoutExpansion() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("1...3")) == StateExpr.integerRange(.int(1), .int(3)))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("3...1")) == StateExpr.integerRange(.int(3), .int(1)))
    }

    @Test("half-open formal domains exclude the upper bound and can be empty at Int.min")
    func halfOpenDomain() throws {
        let ordinary = 0..<3
        #expect(ordinary.upperBound == 3)
        for (low, high, members) in [(2, 5, [2, 3, 4]), (5, 2, []), (Int.min, Int.min, []),
                                    (Int.max - 1, Int.max, [Int.max - 1])] {
            let range = Expr(low)..<Expr(high)
            #expect(try compiledValue(range.stateExpr, values: []) == .set(Set(members.map(TLAValue.int))))
        }
    }
}
