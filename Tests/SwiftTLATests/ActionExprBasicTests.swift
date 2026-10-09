import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct ActionExprBasicTests {
    @Test("Explicit formal assignments resolve a named target without declaring a variable", arguments: [
        "ActionExpr.assign(.named(\"counter\"), 1)",
        "SwiftTLA.ActionExpr.assign(ActionTarget.named(\"counter\"), 1)"
    ])
    func namedAssignmentConstructors(source: String) throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression(source)) == .assign(.named("counter"), .value(.int(1))))
    }

    @Test func parseBecomes() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(5)")) == ActionExpr.assign(.named("x"), .value(.int(5))))
        #expect(
            SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(x + 1)"))
                == ActionExpr.assign(.named("x"), StateExpr.add(.variable("x"), .value(.int(1))))
        )
    }

    @Test func parseStays() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.stays")) == ActionExpr.unchanged(.named("x")))
    }

    @Test func parseGuardedBecomes() throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(1).when(x == 0)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test("action guards cannot disappear when their condition cannot be decoded", arguments: [
        "x.becomes(1).when(makeGuard())",
        "x.becomes(1).when(x > 0).when(makeGuard())",
        "x.becomes(1).when()"
    ])
    func rejectsUndecodableGuard(_ source: String) throws {
        #expect(SpecParser.decodeActionExpr(try parseSpecTestExpression(source)) == nil)
    }

    @Test func parseDoubleWhen() throws {
        let decodedAction = SpecParser.decodeActionExpr(try parseSpecTestExpression("x.becomes(1).when(x > 0).when(x < 5)"))
        #expect(decodedAction == ActionExpr.and(
            ActionExpr.guard_(StateExpr.and(
                StateExpr.lessThan(.variable("x"), .value(.int(5))),
                StateExpr.greaterThan(.variable("x"), .value(.int(0)))
            )),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test func parseChoiceExpressionRetainsItsPredicate() throws {
        let decodedAction = SpecParser.decodeActionExpr(try parseSpecTestExpression(
            "x.becomes(Expr<Int>(StateExpr.choose(StateExpr.set([1, 2, 3]), \"member\", member > 1)))"
        ))
        #expect(decodedAction == .assign(.named("x"), .choose(
            .setLiteral([.int(1), .int(2), .int(3)]), "member", .greaterThan(.variable("member"), .int(1))
        )))
    }

    @Test func parseChoiceExpressionAssignment() throws {
        let decodedAction = SpecParser.decodeActionExpr(
            try parseSpecTestExpression("x.becomes(StateExpr.any(from: StateExpr.set([1, 2, 3])))")
        )
        let expectedSet = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        guard case .assign(.named("x"), .choose(let domain, _, let predicate)) = decodedAction else {
            Issue.record("Expected a deterministic CHOOSE expression assignment")
            return
        }
        #expect(domain == expectedSet)
        #expect(predicate == .bool(true))
    }
}
