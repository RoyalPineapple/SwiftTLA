import Testing
import SwiftTLA
import UpstreamParity

struct BakeryBoundedGraphContractTests {
    @Test("Bakery PlusCal-shaped model matches its upstream bounded graph")
    func bakeryN2MatchesTLC() throws {
        let exploration = try ModelChecker(
            compilation: try BakeryN2Model.spec.compile(),
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000, symmetryReduction: .disabled)
        ).explore()
        #expect(exploration.graph.states.count == Example.bakeryN2.expectedDistinct)

        guard case .ok = exploration.outcome else {
            Issue.record("Bakery PlusCal-shaped model did not verify")
            return
        }
    }
}
