import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct FormalDefinitionFidelityMacroTests {
    @Test func macroExpansionRetainsFormalDefinition() throws {
        #expect(FormalDefinitionFidelityMacro.spec.formalOperatorDefinitions.map(\.name) == ["Refines"])
        _ = try FormalDefinitionFidelityMacro.spec.compile()
    }
}
