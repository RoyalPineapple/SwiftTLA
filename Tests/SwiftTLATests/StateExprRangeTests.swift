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
}
