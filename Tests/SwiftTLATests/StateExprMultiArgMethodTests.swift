import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprMultiArgMethodTests {
    @Test func parseUpdated() throws {
        let f: StateExpr = .variable("f")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("f.updated(at: 0, to: 1)")) == StateExpr.except(f, .value(.int(0)), .value(.int(1))))
    }

    @Test func parseAt() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("t.at(3)"))
                == StateExpr.tupleAccess(.variable("t"), 3)
        )
    }
}
