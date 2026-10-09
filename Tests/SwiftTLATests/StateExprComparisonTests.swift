import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprComparisonTests {
    @Test func parseComparisons() throws {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x == y")) == StateExpr.equal(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x != y")) == StateExpr.notEqual(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x < y")) == StateExpr.lessThan(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x <= y")) == StateExpr.lessOrEqual(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x > y")) == StateExpr.greaterThan(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x >= y")) == StateExpr.greaterOrEqual(x, y))
    }
}
