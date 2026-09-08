import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

@Suite("Sequence selection retains nested lexical bindings")
struct SequenceSelectionBindingTests {
    @Test("An inner selection can compare its member to the outer member")
    func nestedSelection() throws {
        let built = TupleExpr<Int>.literal(1, 2).selecting { outer in
            TupleExpr<Int>.literal(1, 2).selecting { inner in outer == inner } == TupleExpr<Int>.literal(outer.expr)
        }
        let syntax = Parser.parse(source: """
        TupleExpr<Int>.literal(1, 2).selecting { outer in
            TupleExpr<Int>.literal(1, 2).selecting { inner in outer == inner } == TupleExpr<Int>.literal(outer.expr)
        }
        """)
        let expression = try #require(syntax.statements.first?.item.as(ExprSyntax.self))
        let parsed = try #require(SpecParser.decodeStateExpr(expression))
        #expect(try evaluateClosed(built.raw) == .tuple([.int(1), .int(2)]))
        #expect(try evaluateClosed(parsed) == .tuple([.int(1), .int(2)]))
        guard case .sequenceSelect(_, let outer, .equal(.sequenceSelect(_, let inner, _), _)) = built.raw else {
            Issue.record("Expected nested sequence selection")
            return
        }
        #expect(outer != inner)
    }

    @Test("Counting a nested selection retains its sequence shape and outer binding")
    func countsNestedSelection() throws {
        let built = TupleExpr<Int>.literal(1, 2).selecting { outer in
            TupleExpr<Int>.literal(1, 2).selecting { inner in outer == inner }.count == 1
        }
        let syntax = Parser.parse(source: """
        TupleExpr<Int>.literal(1, 2).selecting { outer in
            TupleExpr<Int>.literal(1, 2).selecting { inner in outer == inner }.count == 1
        }
        """)
        let expression = try #require(syntax.statements.first?.item.as(ExprSyntax.self))
        let parsed = try #require(SpecParser.decodeStateExpr(expression))
        #expect(try evaluateClosed(built.raw) == .tuple([.int(1), .int(2)]))
        #expect(try evaluateClosed(parsed) == .tuple([.int(1), .int(2)]))
    }
    @Test("Counting sequence removal retains the bound index and sequence shape")
    func countsRemovalInsideSelection() throws {
        let built = TupleExpr<Int>.literal(1, 2).selecting { index in
            TupleExpr<Int>.literal(7, 8).removing(at: index.expr).count == 1
        }
        let syntax = Parser.parse(source: """
        TupleExpr<Int>.literal(1, 2).selecting { index in
            TupleExpr<Int>.literal(7, 8).removing(at: index.expr).count == 1
        }
        """)
        let expression = try #require(syntax.statements.first?.item.as(ExprSyntax.self))
        let parsed = try #require(SpecParser.decodeStateExpr(expression))
        #expect(try evaluateClosed(built.raw) == .tuple([.int(1), .int(2)]))
        #expect(try evaluateClosed(parsed) == .tuple([.int(1), .int(2)]))
    }

}
