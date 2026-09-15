@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedRestrictedProcessDomainTests {
    @Test("a process declaration keeps its explicit member subset")
    func compiledProcessUsesOnlyDeclaredMembers() throws {
        let compilation = try GeneratedRestrictedProcessDomain.spec.compile()
        let binding = try #require(compilation.semantics.behavior.actions.first?.bindings.first)
        #expect(binding.sourceName == "process")
        #expect(binding.values == [.integer(1)])
    }
}
