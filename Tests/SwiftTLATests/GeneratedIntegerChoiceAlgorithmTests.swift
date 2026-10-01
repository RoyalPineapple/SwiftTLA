import Testing
import SwiftTLA

struct GeneratedIntegerChoiceAlgorithmTests {
    @Test("Bounded integer choice retains every generated branch")
    func boundedIntegerChoiceRetainsEveryBranch() throws {
        let graph = try ReachabilityGraph(
            initialMachines: GeneratedIntegerChoiceAlgorithm.initialMachines(), maximumStates: 10)
        #expect(Set(graph.transitions.keys.map { $0.state.selected }) == [0, 1, 2, 3])
    }
}
