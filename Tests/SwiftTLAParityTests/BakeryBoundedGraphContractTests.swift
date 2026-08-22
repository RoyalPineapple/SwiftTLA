import Testing
import SwiftTLA
import UpstreamParity

struct BakeryBoundedGraphContractTests {
    @Test("Bakery PlusCal-shaped model matches its upstream bounded graph")
    func bakeryN2MatchesTLC() throws {
        let checker = try ModelChecker(compilation: try BakeryN2Model.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        let graph = try checker.exploreGraph()
        #expect(graph.states.count == Example.bakeryN2.expectedDistinct, "Bakery graph has \(graph.states.count) states; TLC records \(Example.bakeryN2.expectedDistinct).")

        guard case .ok = try checker.check() else {
            Issue.record("Bakery PlusCal-shaped model did not verify")
            return
        }
    }
}
