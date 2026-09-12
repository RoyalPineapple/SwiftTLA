@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedProcessLocalInvariantTests {
    @Test("compilation preserves process-local invariants")
    func compilationPreservesProcessLocalInvariant() throws {
        let compilation = try GeneratedProcessLocalInvariant.spec.compile()
        #expect(compilation.semantics.behavior.invariants.map(\.name) == ["LocalCount", "ControlLocation"])
    }
}
