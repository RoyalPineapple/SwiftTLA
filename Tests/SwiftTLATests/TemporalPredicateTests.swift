import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct TemporalPredicateTests {
    @Test func parseLeadsTo() throws {
        let call = try #require(try parseSpecTestExpression("x.leadsTo(y)").as(FunctionCallExprSyntax.self))
        #expect(
            SpecParser.decodeTemporal(call)
                == TemporalCondition<StateExpr>.leadsTo(.variable("x"), .variable("y"))
        )
    }

    @Test func parseLeadsToWithExpressions() throws {
        let call = try #require(
            try parseSpecTestExpression("(x > 0).leadsTo(y == 0)").as(FunctionCallExprSyntax.self)
        )
        let decodedProperty = SpecParser.decodeTemporal(call)
        #expect(decodedProperty == TemporalCondition<StateExpr>.leadsTo(
            StateExpr.greaterThan(.variable("x"), .value(.int(0))),
            StateExpr.equal(.variable("y"), .value(.int(0)))
        ))
    }
}
