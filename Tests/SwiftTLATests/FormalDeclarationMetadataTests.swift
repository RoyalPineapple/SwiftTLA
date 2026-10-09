import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite struct FormalDeclarationMetadataTests {
    @Test("supplied declaration metadata must decode completely", arguments: [
        "plusCalPhase: suppliedPhase",
        "plusCalPhase: .unknownPhase",
        "dependsOn: suppliedDependencies",
        "dependsOn: [\"Known\", unknownDependency]"
    ])
    func rejectsUndecodableMetadata(_ metadata: String) throws {
        let parsed = SpecParser.parseSpecClosure(named: "Metadata", try parseSpecTestClosure("""
        {
            FormalDefinition("Value", parameters: [], body: 7, \(metadata))
        }
        """))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(parsed.formalOperatorDefinitions.isEmpty)
    }
}
