import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprLogicalPrefixTests {
    @Test func parseLogical() throws {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x && y")) == StateExpr.and(x, y))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x || y")) == StateExpr.or(x, y))
    }

    @Test func parsePrefix() throws {
        let x: StateExpr = .variable("x")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("!x")) == StateExpr.not(x))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("-x")) == StateExpr.negate(x))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("-1")) == StateExpr.value(.int(-1)))
    }

    @Test("minimum integer negation remains structural")
    func minimumIntegerNegationRemainsStructural() throws {
        let parser = ParserSession()
        parser.constants = [Constant("Minimum", Int.min)]
        #expect(
            parser.decodeStateExpr(try parseSpecTestExpression("-Minimum"))
                == StateExpr.negate(.value(.int(.min)))
        )
    }

    @Test func preservesSwiftInfixPrecedence() throws {
        let index: StateExpr = .variable("index")
        let count: StateExpr = .variable("count")
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("index <= count + 1"))
                == StateExpr.lessOrEqual(index, .add(count, .value(.int(1))))
        )
    }

    @Test func parseParenthesized() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("(x)")) == .variable("x"))
    }
}
