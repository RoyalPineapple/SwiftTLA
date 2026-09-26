@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedRangeInitializedAlgorithmTests {
    @Test("compiled initialization preserves every finite SharedVar value")
    func generatedRangePreservesEveryInitialHour() throws {
        let compilation = try GeneratedRangeInitializedAlgorithm.spec.compile()
        let hour = try #require(compilation.layout.testVariableID(named: "hour"))
        let initialHours = try CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.value(for: hour).rendered(using: compilation.layout)
        }

        #expect(Set(initialHours) == [.int(1), .int(2), .int(3)])
    }
}
