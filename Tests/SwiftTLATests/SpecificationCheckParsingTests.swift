import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite struct SpecificationCheckParsingTests {
    @Test("Deadlock checking is opt-in in both the parser and DSL builder")
    func deadlockCheckingIsOptIn() throws {
        let defaultSpec = SpecParser.parseSpecClosure(named: "Default", try parseSpecTestClosure("{}"))
        let parsed = SpecParser.parseSpecClosure(named: "Checked", try parseSpecTestClosure("{ DeadlockCheck() }"))
        let built = TLASpec("Checked") { DeadlockCheck() }
        #expect(!defaultSpec.checkDeadlock)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.checkDeadlock == built.checkDeadlock)
        #expect(parsed.checkDeadlock)
    }

    @Test("Malformed deadlock declarations fail at the source boundary", arguments: [
        "DeadlockCheck(true)", "DeadlockCheck { true }"
    ])
    func rejectsMalformedDeadlockChecks(_ source: String) throws {
        let parsed = SpecParser.parseSpecClosure(named: "Checked", try parseSpecTestClosure("{ \(source) }"))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(!parsed.checkDeadlock)
    }

    @Test("Specification assumptions match the DSL builder and remain conjunctive")
    func conjunctiveAssumptions() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Assumptions", try parseSpecTestClosure("{ Assume(true); Assume(false) }"))
        let built = TLASpec("Assumptions") { Assume(true); Assume(false) }
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.assume == built.assume)
    }

    @Test("Malformed assumptions fail at the source boundary", arguments: ["Assume()", "Assume(true, false)", "Assume(unknown())"])
    func rejectsMalformedAssumptions(_ source: String) throws {
        let parsed = SpecParser.parseSpecClosure(named: "Assumptions", try parseSpecTestClosure("{ \(source) }"))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(parsed.assume == nil)
    }
}
