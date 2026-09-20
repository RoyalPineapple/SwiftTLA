import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprBinaryMethodTests {
    @Test("Scoped integer division retains midpoint bindings and its integer result type")
    func scopedIntegerDivision() throws {
        let parser = ParserSession()
        let low = StateExpr.variable("resolvedLow")
        let high = StateExpr.variable("resolvedHigh")
        let scope = ParserSession.TypedFacadeScope.empty
            .extending(binding: "low", to: low, shape: .int)
            .extending(binding: "high", to: high, shape: .int)
        let expression = try parseSpecTestExpression("(low + high).integerDivided(by: 2)")
        #expect(parser.decodeTypedFacadeValue(expression, scope: scope)
            == .integerDivide(.add(low, high), .value(.int(2))))
        #expect(parser.typedFacadeValueType(expression, scope: scope) == .int)
        for invalid in ["low.integerDivided(2)", "low.integerDivided(by: 2, extra: 3)"] {
            #expect(parser.decodeTypedFacadeValue(try parseSpecTestExpression(invalid), scope: scope) == nil)
        }
    }

    @Test func parseBinaryMethods() throws {
        let x: StateExpr = .variable("x")
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.isIn(s)")) == StateExpr.in(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.union(s)")) == StateExpr.union(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.intersection(s)")) == StateExpr.intersection(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.subtracting(s)")) == StateExpr.setDifference(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.isSubset(of: s)")) == StateExpr.subset(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.applying(s)")) == StateExpr.functionApply(x, s))
        let decodedFilterExpression = SpecParser.decodeStateExpr(try parseSpecTestExpression("x.filtering(s)"))
        guard case .setFilter(let filterDomain, _, let filterBody) = decodedFilterExpression else {
            Issue.record("Expected a structural set filter")
            return
        }
        #expect(filterDomain == x)
        #expect(filterBody == s)
        let decodedMapExpression = SpecParser.decodeStateExpr(try parseSpecTestExpression("x.mapping(s)"))
        guard case .setMap(let mapBody, _, let mapDomain) = decodedMapExpression else {
            Issue.record("Expected a structural set map")
            return
        }
        #expect(mapBody == s)
        #expect(mapDomain == x)
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.appending(s)")) == StateExpr.tupleAppend(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.concatenating(s)")) == StateExpr.tupleConcatenate(x, s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x.integerDivided(by: 2)")) == StateExpr.integerDivide(x, .value(.int(2))))
    }
}
