import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite struct SpecificationCheckParsingTests {
    @Test("Deadlock checking is enabled by default in the parser and DSL")
    func deadlockCheckingIsDefault() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Default", try parseSpecTestClosure("{}"))
        let built = TLASpec("Default") {}
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.checkDeadlock)
        #expect(built.checkDeadlock)
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
