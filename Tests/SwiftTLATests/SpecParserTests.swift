import Testing
import SwiftSyntax
import SwiftParser
import SwiftTLA

struct SpecParserTests {
    @Test("Parse integer literal")
    func parseInt() {
        let src = "42"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        let result = SpecParser.parseStateExpr(expr)
        #expect(result?.description == "42")
    }

    @Test("Parse variable reference")
    func parseVar() {
        let src = "x"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        #expect(SpecParser.parseStateExpr(expr)?.description == "x")
    }

    @Test("Parse arithmetic: x + 5")
    func parseAdd() {
        let src = "x + 5"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        let result = SpecParser.parseStateExpr(expr)
        #expect(result?.description == "(x + 5)")
    }

    @Test("Parse comparison: x == y")
    func parseEqual() {
        let src = "x == y"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        #expect(SpecParser.parseStateExpr(expr)?.description == "(x = y)")
    }

    @Test("Parse becomes chain: x.becomes(1)")
    func parseBecomes() {
        let src = "x.becomes(1)"
        let call = Parser.parse(source: src).statements.first!.item.as(FunctionCallExprSyntax.self)!
        let result = SpecParser.parseSingleAction(ExprSyntax(call))
        #expect(result?.description.contains("x' = 1") == true)
    }

    @Test("Parse guarded becomes: x.becomes(1).when(x == 0)")
    func parseWhen() {
        let src = "x.becomes(1).when(x == 0)"
        let call = Parser.parse(source: src).statements.first!.item.as(FunctionCallExprSyntax.self)!
        let result = SpecParser.parseSingleAction(ExprSyntax(call))
        #expect(result?.description.contains("(x = 0)") == true)
        #expect(result?.description.contains("x' = 1") == true)
    }

    @Test("Parse stays: x.stays")
    func parseStays() {
        let src = "x.stays"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        let result = SpecParser.parseSingleAction(expr)
        #expect(result?.description.contains("UNCHANGED x") == true)
    }

    @Test("Parse prefix negation")
    func parseNegate() {
        let src = "-x"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        #expect(SpecParser.parseStateExpr(expr)?.description == "(-x)")
    }


    @Test("Parse cardinality property")
    func parseCard() {
        let src = "s.cardinality"
        let expr = Parser.parse(source: src).statements.first!.item.as(ExprSyntax.self)!
        #expect(SpecParser.parseStateExpr(expr)?.description.contains("Cardinality") == true)
    }
}
