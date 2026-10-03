@testable import SwiftTLA
import Testing

struct FiniteExplorationConfigurationTests {
    @Test("finite exploration rejects non-positive state and permutation limits")
    func rejectsNonPositiveLimits() {
        #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(0)) {
            _ = try FiniteExplorationConfiguration(maximumStateLimit: 0, symmetryReduction: .disabled)
        }
        #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(-1)) {
            _ = try FiniteExplorationConfiguration(maximumStateLimit: -1, symmetryReduction: .disabled)
        }
        #expect(throws: FiniteExplorationConfigurationError.nonPositivePermutationLimit(0)) {
            _ = try FiniteExplorationConfiguration(
                maximumStateLimit: 1, symmetryReduction: .enabled(maximumPermutationCount: 0))
        }
    }
}
