import SwiftTLA
import Testing
import UpstreamParity

struct MovingCatCorpusStateGraphTests {
    @Test("generated machines retain both published finite state spaces and transition counts")
    func retainsEvenAndOddGraphs() throws {
        let even = try ReachabilityGraph(
            initialMachines: CatEvenBoxesModel.initialMachines(), maximumStates: 50_000)
        let odd = try ReachabilityGraph(
            initialMachines: CatOddBoxesModel.initialMachines(), maximumStates: 50_000)
        #expect(even.initialStates.count == 48)
        #expect(odd.initialStates.count == 30)
        #expect(even.transitions.count == 48)
        #expect(odd.transitions.count == 30)
        #expect(even.transitions.values.reduce(0) { $0 + $1.count } == 80)
        #expect(odd.transitions.values.reduce(0) { $0 + $1.count } == 48)
    }
}
