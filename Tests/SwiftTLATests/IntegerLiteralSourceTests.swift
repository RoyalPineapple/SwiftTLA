@testable import SwiftTLAPlugin
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

struct IntegerLiteralSourceTests {
    @Test("Parser integer literals preserve signs, radices and boundary values")
    func integerLiteralSpellings() throws {
        let cases: [(String, Int)] = [
            ("0b1010", 10), ("0o17", 15), ("0x7f", 127), ("1_000", 1000),
            ("-0x10", -16), ("-9223372036854775808", Int.min),
            ("9223372036854775807", Int.max)
        ]
        for (source, value) in cases {
            let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
            #expect(SourceIntegerLiteral.value(expression) == value)
            #expect(SpecParser.decodeStateExpr(expression) == .value(.int(value)))
            #expect(SpecParser.decodeTypedFacadeValue(expression) == .value(.int(value)))
            #expect(ParserSession().parseLiteralValue(expression) == .int(value))
        }
        for source in ["9223372036854775808", "-9223372036854775809", "0x10000000000000000"] {
            let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
            #expect(SourceIntegerLiteral.value(expression) == nil)
        }
    }
}
