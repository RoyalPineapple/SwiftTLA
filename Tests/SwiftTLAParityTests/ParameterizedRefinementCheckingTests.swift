import SwiftTLA
import Testing

struct ParameterizedRefinementCheckingTests {
    @Test("native refinement checks each configured abstract limit")
    func checksMappedAbstractParameters() throws {
        for limit in 1...2 {
            let configuration = try ParameterizedRefinementCounter.Configuration(limit: limit)
            let machines = try ParameterizedRefinementCounter.initialMachines(configuration: configuration)
            let graph = try ReachabilityGraph(initialMachines: machines, maximumStates: 10)
            #expect(graph.initialStates.map(\.state.count) == [limit + 1])
            #expect(graph.transitions.count == 2)
            #expect(graph.refinementFailures.isEmpty)
        }
    }
}
