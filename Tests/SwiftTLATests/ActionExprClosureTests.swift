import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct ActionExprClosureTests {
    @Test("Action diagnostics identify the failed statement after valid local bindings")
    func diagnosticsRetainLexicalFailureLocation() throws {
        let source = "{ let prior = Expr<Int>(1); x.becomes(prior); UnsupportedStep() }"
        let closure = try parseSpecTestClosure(source)
        do {
            _ = try SpecParser.decodeActionFromClosure(closure)
            Issue.record("Expected unsupported action syntax to fail")
        } catch {
            #expect(error.source == "UnsupportedStep()")
            let range = try #require(source.range(of: "UnsupportedStep()"))
            #expect(error.sourceSpan.location == .utf8Offset(source[..<range.lowerBound].utf8.count))
        }
    }

    @Test func parseEmptyClosure() throws {
        let closure = try parseSpecTestClosure("{}")
        #expect(try SpecParser.decodeActionFromClosure(closure) == ActionExpr.guard_(.value(.bool(true))))
    }

    @Test func parseSingleStatementClosure() throws {
        let closure = try parseSpecTestClosure("{ x.becomes(1) }")
        #expect(try SpecParser.decodeActionFromClosure(closure) == ActionExpr.assign(.named("x"), .value(.int(1))))
    }

    @Test func parseMultiStatementClosure() throws {
        let closure = try parseSpecTestClosure("{ x.becomes(1) ; y.stays }")
        #expect(try SpecParser.decodeActionFromClosure(closure) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.unchanged(.named("y"))
        ))
    }
}
