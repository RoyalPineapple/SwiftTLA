@testable import SwiftTLAPlugin
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
    @Test("Branch expansion preserves lexical scopes and executable Boolean guards")
    func branchExpansionPreservesScopesAndGuards() {
        let predicate = StateExpr.or(.bool(true), .equal(.divide(.int(1), .int(0)), .int(0)))
        let first = ActionExpr.assign(.named("value"), .int(1))
        let second = ActionExpr.assign(.named("value"), .int(2))
        let action = ActionExpr.define("local", .int(3), .and(.guard_(predicate), .or(first, second)))
        #expect(ActionNormalization.branches(of: action) == [
            .define("local", .int(3), .and(.guard_(predicate), first)),
            .define("local", .int(3), .and(.guard_(predicate), second))
        ])
        #expect(ActionNormalization.branches(of: .guard_(.bool(false))).isEmpty)
        #expect(alphaKey(.and(.guard_(predicate), first)) == alphaKey(.or(
            .and(.guard_(.bool(true)), first),
            .and(.guard_(.equal(.divide(.int(1), .int(0)), .int(0))), first)
        )))
    }

}
