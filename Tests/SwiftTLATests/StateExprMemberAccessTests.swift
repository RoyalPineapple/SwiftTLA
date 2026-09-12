import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() throws {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.count")) == StateExpr.tupleLength(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }
}
