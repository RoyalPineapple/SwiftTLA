import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprArithmeticTests {
    @Test func parseArithmetic() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x + 5")) == StateExpr.add(.variable("x"), .value(.int(5))))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x - 3")) == StateExpr.subtract(.variable("x"), .value(.int(3))))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x * 2")) == StateExpr.multiply(.variable("x"), .value(.int(2))))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x / 4")) == StateExpr.divide(.variable("x"), .value(.int(4))))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x % 7")) == StateExpr.modulo(.variable("x"), .value(.int(7))))
    }
}
