import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprLiteralTests {
    @Test func parseInts() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("0")) == .value(.int(0)))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("42")) == .value(.int(42)))
    }

    @Test("static Swift integer spelling is decoded")
    func decodesStaticSwiftIntegerSpelling() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("1_000")) == .int(1_000))
    }

    @Test func parseBools() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("true")) == .value(.bool(true)))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("false")) == .value(.bool(false)))
    }

    @Test func parseStrings() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("\"hello\"")) == .value(.string("hello")))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("\"left\"")) == .value(.string("left")))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("\"\"")) == .value(.string("")))
    }
}
