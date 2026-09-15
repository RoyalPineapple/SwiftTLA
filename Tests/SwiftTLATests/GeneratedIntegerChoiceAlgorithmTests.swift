@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedIntegerChoiceAlgorithmTests {
    @Test("#spec retains a bounded integer choice")
    func compiledSpecificationRetainsIntegerChoice() throws {
        let spec = GeneratedIntegerChoiceAlgorithm.spec
        let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).exploreGraph()
        #expect(try Set(graph.states.values.compactMap { try value("selected", in: $0) }) == [.int(0), .int(1), .int(2), .int(3)])
    }
}
