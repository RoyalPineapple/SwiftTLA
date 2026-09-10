@testable import SwiftTLAPlugin
@testable import SwiftTLA
import SwiftParser
import SwiftSyntax
import Testing

@Suite(.serialized)
struct SelectSeqContractsTests {
    private func parseExpression(_ source: String) throws -> ExprSyntax {
        try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
    }

    private func compilation(for expression: StateExpr) throws -> CompiledSpecification {
        try TLASpec(
            name: "SelectSeqContracts",
            variables: [NamedVar(
                name: "result",
                initialization: .expression(expression),
                origin: .compiler
            )],
            actions: [],
            invariants: []
        ).compile()
    }

    @Test("typed selection preserves empty order and duplicate occurrences")
    func typedSelectionPreservesSequenceOccurrences() throws {
        let empty = Expr<TupleExpr<Int>>(.tupleLiteral([])).selecting { $0 == 1 }
        let selected = TupleExpr<Int>.literal(3, 2, 2, 1).selecting { $0 >= 2 }

        #expect(try compiledValue(empty.raw) == .tuple([]))
        #expect(try compiledValue(selected.raw) == .tuple([.int(3), .int(2), .int(2)]))
    }

    @Test("parser and typed facade produce one selection meaning")
    func parserAndFacadeHaveOneIdentity() throws {
        let built = TupleExpr<Int>.literal(3, 2, 2, 1).selecting(where: { item in item >= 2 })
        let parsed = try #require(SpecParser.decodeStateExpr(try parseExpression(
            "TupleExpr<Int>.literal(3, 2, 2, 1).selecting(where: { item in item >= 2 })"
        )))

        #expect(try compilation(for: built.raw).identity == compilation(for: parsed).identity)
    }

    @Test("selection binding shadows outer names and avoids substitution capture")
    func selectionBindingIsStructural() throws {
        let shadowed = StateExpr.letValue(
            "item",
            .int(9),
            .sequenceSelect(
                .tupleLiteral([.int(1), .int(2)]),
                "item",
                .equal(.variable("item"), .int(2))
            )
        )
        let substituted = StateExpr.substituteVariable(
            "target",
            with: .variable("item"),
            in: .sequenceSelect(
                .tupleLiteral([.int(1)]),
                "item",
                .equal(.variable("target"), .variable("item"))
            )
        )

        #expect(shadowed.freeVariableNames.isEmpty)
        #expect(try compiledValue(shadowed) == .tuple([.int(2)]))
        guard case .sequenceSelect(_, let binder, .equal(.variable(let target), .variable(let item))) = substituted else {
            Issue.record("Expected a structurally renamed sequence selection")
            return
        }
        #expect(binder == "item_1")
        #expect(target == "item")
        #expect(item == "item_1")
    }

    @Test("selection rejects a non-sequence and renders direct standard syntax")
    func selectionRejectsInvalidShapesAndRendersDirectly() throws {
        let selected = TupleExpr<Int>.literal(3, 2, 2, 1).selecting { $0 >= 2 }
        let invalid = StateExpr.sequenceSelect(.int(1), "item", .bool(true))

        do {
            _ = try compiledValue(invalid)
            Issue.record("Expected a non-sequence selection to fail")
        } catch let error as EvalError {
            #expect(error == .expected(.sequence, actual: [.integer(1)]))
        }

        let rendered = try compilation(for: selected.raw).renderedTLAModuleBundle().tla
        #expect(rendered.contains("SelectSeq(<<3, 2, 2, 1>>, LAMBDA "))
        #expect(rendered.contains(" >= 2"))
    }
}
