import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprVariableTests {
    @Test func parseVariableReferences() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("x")) == .variable("x"))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("count")) == .variable("count"))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("direction")) == .variable("direction"))
    }
}
