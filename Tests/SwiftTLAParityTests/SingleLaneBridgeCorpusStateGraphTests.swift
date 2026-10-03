import Testing
import SwiftTLA
@testable import UpstreamParity

struct SingleLaneBridgeCorpusStateGraphTests {
    @Test("published bridge configuration checks the complete native graph and selected properties")
    func publishedConfiguration() throws {
        let scenarios = try SingleLaneBridgeModel.validationScenarios()
        #expect(scenarios.count == 1)
        let scenario = try #require(scenarios.first)
        #expect(scenario.name == "MC")

        let run = try NativeScenarioRun(scenario, maximumStates: 5_000)
        try run.validateExpectations()
        let graphRun = try #require(run.native.graph)
        #expect(graphRun.isComplete)
        let graph = graphRun.graph
        #expect(graph.initialStateKeys.count == 1)
        #expect(graph.states.count == 3_605)
        #expect(run.native.checks.properties == [
            "Invariants": .satisfied,
            "CarsInBridgeExitBridge": .satisfied,
            "CarsEnterBridge": .satisfied,
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }
}
