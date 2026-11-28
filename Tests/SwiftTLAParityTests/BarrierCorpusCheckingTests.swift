import SwiftTLA
import Testing
@testable import UpstreamParity

struct BarrierCorpusCheckingTests {
    @Test("Six processes enter independently and leave the barrier together")
    func publishedScenarios() throws {
        let scenarios = try BarrierModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["APBarrier", "Barrier"])
        for scenario in scenarios {
            let run = try NativeScenarioRun(scenario, maximumStates: 100)
            try run.validateExpectations()
            let graph = try #require(run.native.graph)
            #expect(graph.isComplete)
            #expect(graph.graph.initialStateKeys.count == 1)
            #expect(graph.graph.states.count == 64)
            #expect(graph.graph.edges.count == 193)
            let checks = run.native.checks.properties
            let expected = scenario.name == "APBarrier" ? ["TypeOK"] : ["TypeOK", "BarrierProperty"]
            #expect(Set(checks.keys) == Set(expected))
            #expect(checks.values.allSatisfy { $0 == .satisfied })
            #expect(run.native.checks.deadlock == .satisfied)
        }
    }
}
