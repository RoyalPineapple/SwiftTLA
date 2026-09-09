import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

@Suite struct ParserBindingScopeTests {
    @Test("Nested module action bindings do not replace enclosing bindings")
    func nestedModuleBindings() throws {
        let source = """
        {
            let action = SwiftTLA.Action("outer") { true }
            let support = TLASpec("Support") {
                let action = SwiftTLA.Action("inner") { false }
                action
            }
            action
            Invariant("OuterEnabled") { StateExpr.enabled(action) }
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.map(\.name) == ["outer"])
        #expect(parsed.invariants.first?.body == .enabledAction("outer"))
    }
}
