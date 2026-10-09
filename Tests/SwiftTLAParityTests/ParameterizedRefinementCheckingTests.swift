import SwiftTLA
import Testing
import UpstreamParity

struct ParameterizedRefinementCheckingTests {
    @Test("configured refinement export binds the abstract module to its typed parameter")
    func exportsMappedAbstractParameters() throws {
        for (index, scenario) in try ParameterizedRefinementCounter.validationScenarios().enumerated() {
            let bundle = try scenario.render().tlaBundle
            let abstract = try #require(bundle.imports.first { $0.name.hasSuffix("__Refinement0") })
            #expect(bundle.cfg.contains("CONSTANT limit = \(index + 1)"))
            #expect(abstract.tla.contains("CONSTANTS limit"))
            #expect(bundle.tla.contains("limit <- limit"))
        }
    }

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
