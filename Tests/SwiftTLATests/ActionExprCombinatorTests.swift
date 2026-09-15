import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct ActionExprCombinatorTests {
    @Test func parseAndOfTwoActions() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(1) && y.becomes(2)")) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.assign(.named("y"), .value(.int(2)))
        ))
    }

    @Test func parseOrOfTwoActions() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(1) || x.becomes(2)")) == ActionExpr.or(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.assign(.named("x"), .value(.int(2)))
        ))
    }

    @Test func parseGuardAndAction() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x > 0 && x.becomes(x - 1)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.greaterThan(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), StateExpr.subtract(.variable("x"), .value(.int(1))))
        ))
    }

    @Test func parseActionAndGuard() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(0) && x == 0")) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(0))),
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0))))
        ))
    }

    @Test func parseStateOrAction() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x == 0 || x.becomes(1)")) == ActionExpr.or(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test func parsesNestedGuardedDisjunction() throws {
        let decodedAction = SpecParser.decodeActionExpr(
            try parseSpecTestExpression("(x != 12) && x.becomes(x + 1) || (x == 12) && x.becomes(1)")
        )
        let left = ActionExpr.and(
            ActionExpr.guard_(StateExpr.notEqual(.variable("x"), .value(.int(12)))),
            ActionExpr.assign(.named("x"), StateExpr.add(.variable("x"), .value(.int(1))))
        )
        let right = ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(12)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        )
        #expect(decodedAction == ActionExpr.or(left, right))
    }
}
