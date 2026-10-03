import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct SourceLiteralParsingTests {
    @Test("escaped source string preserves its formal value")
    func preservesEscapedStringLiteral() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression(#""alpha\"beta""#))
                == .value(.string("alpha\"beta"))
        )
    }
}
