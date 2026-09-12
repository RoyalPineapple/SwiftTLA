import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StructuralActionReferenceParsingTests {
    @Test("action declarations carry fairness and enabled references")
    func actionDeclarationsCarryReferences() throws {
        let parsed = SpecParser.parseSpecClosure(named: "StructuralActionReferences", try parseSpecTestClosure("""
        {
            let count = Var<Int>("count", initial: 0)
            Variable(count)
            let advance = Action("advance") { count.becomes(count + 1) }
            advance
            WeakFairness(advance)
            StrongFairness(advance)
            Invariant("AdvanceEnabled") { StateExpr.enabled(advance) }
        }
        """))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.map(\.name) == ["advance"])
        #expect(parsed.fairness == [.weakFairness("advance"), .strongFairness("advance")])
        #expect(parsed.invariants.first?.body == .enabledAction("advance"))
        _ = try parsed.compile()
    }

    @Test("fairness rejects an undeclared action reference")
    func fairnessRejectsUndeclaredActionReference() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure("""
        {
            WeakFairness(missing)
        }
        """))

        #expect(parsed.diagnostics.map(\.message) == [
            "Fairness action reference 'missing' is not bound by a local Action declaration."
        ])
    }
}
