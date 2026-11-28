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

    @Test(arguments: [("true", true), ("false", false), ("Expr(true).stateExpr", true),
        ("SwiftTLA.Expr(false).stateExpr", false), ("Expr<Bool>(false).stateExpr", false)])
    func parseBools(_ source: String, _ expected: Bool) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == .value(.bool(expected)))
    }

    @Test(arguments: [("\"hello\"", "hello"), ("\"left\"", "left"), ("\"\"", ""),
        ("Expr(\"hello\").stateExpr", "hello"), ("SwiftTLA.Expr(\"\").stateExpr", ""),
        ("Expr<String>(\"left\").stateExpr", "left")])
    func parseStrings(_ source: String, _ expected: String) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == .value(.string(expected)))
    }
}
