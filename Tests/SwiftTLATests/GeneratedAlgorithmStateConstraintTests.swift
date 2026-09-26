@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedAlgorithmStateConstraintTests {
    @Test("compiled exploration enforces an algorithm state constraint")
    func compiledExplorationPreservesStateConstraint() throws {
        let compilation = try GeneratedAlgorithmStateConstraint.spec.compile()
        #expect(compilation.semantics.behavior.constraint != nil)
        let graph = try ModelChecker(compilation: compilation, configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).exploreGraph()
        #expect(try Set(graph.states.values.compactMap { try value("count", in: $0) }) == [.int(0), .int(1)])
    }
}
