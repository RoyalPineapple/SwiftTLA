import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

struct BooleanActionCompositionTests {
    private func action(_ source: String) throws -> ActionExpr {
        let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        return try #require(SpecParser.decodeActionExpr(expression))
    }

    @Test("Boolean operators inside actions remain one short-circuit predicate")
    func predicatesPreserveBooleanComposition() throws {
        #expect(try action("true || false") == .guard_(.or(.bool(true), .bool(false))))
        #expect(try action("true && false") == .guard_(.and(.bool(true), .bool(false))))
        #expect(try action("(true && false) || true")
            == .guard_(.or(.and(.bool(true), .bool(false)), .bool(true))))
    }

    @Test("Transition operands retain action disjunction and conjunction")
    func transitionsPreserveActionComposition() throws {
        #expect(try action("value.becomes(1) || value.becomes(2)") == .or(
            .assign(.named("value"), .int(1)), .assign(.named("value"), .int(2))
        ))
        #expect(try action("true || value.stays") == .or(
            .guard_(.bool(true)), .unchanged(.named("value"))
        ))
        #expect(try action("true && value.becomes(1)") == .and(
            .guard_(.bool(true)), .assign(.named("value"), .int(1))
        ))
    }
}
