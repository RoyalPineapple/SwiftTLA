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

    @Test("both configured refinements keep the no-failure probe state-level and graph-free")
    func checksInitialFailureProbeForBothLimits() throws {
        for scenario in try ParameterizedRefinementCounter.validationScenarios() {
            let rendered = try scenario.render()
            let probe = try #require(try rendered.initialEvaluationFailureBundle())
            let initName = probe.root.name + "__ProbeInit"
            let nextName = probe.root.name + "__ProbeNext"
            let stateName = probe.root.name + "__ProbeState"
            #expect(probe.tla.contains(#"\#(initName) == FALSE /\ Init"#))
            #expect(probe.tla.contains("\(nextName) == FALSE /\\ \(stateName)' = \(stateName)"))
            #expect(probe.cfg.contains("INIT \(initName)"))
            #expect(probe.tla.contains("ASSUME ~__SwiftTLAAnyInitialEvaluationFailure"))
        }
    }
}
