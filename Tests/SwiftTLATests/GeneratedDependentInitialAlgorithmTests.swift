@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedDependentInitialAlgorithmTests {
    @Test("#spec preserves a dependent typed function initializer")
    func compiledSpecificationPreservesDependentInitialStates() throws {
        let compilation = try GeneratedDependentInitialAlgorithm.spec.compile()
        let mirrors = try #require(compilation.layout.testVariableID(named: "mirrors"))
        let states = try CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.value(for: mirrors).rendered(using: compilation.layout)
        }

        #expect(Set(states) == [
            .function([.string("left"): .string("inactive"), .string("right"): .string("inactive")]),
            .function([.string("left"): .string("active"), .string("right"): .string("inactive")])
        ])
    }
}
