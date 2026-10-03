import Testing
@testable import UpstreamParity

@Suite("Chang-Roberts corpus checking")
struct ChangRobertsCorpusContractTests {
    @Test("Both published configurations use complete generated-machine checks")
    func publishedConfigurations() throws {
        let scenarios = try ChangRobertsModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["MCChangRoberts", "APChangRoberts"])

        for scenario in scenarios {
            let run = try NativeScenarioRun(scenario, maximumStates: 500)
            try run.validateExpectations()
            guard case .exhausted(let result) = run.native else {
                Issue.record("Expected complete generated-machine exploration for \(scenario.name)")
                continue
            }
            #expect(result.graph.isComplete)
            #expect(result.graph.graph.initialStateKeys.count == 8)
            #expect(result.graph.graph.edgeCount > 0)
            #expect(result.checks.deadlock == nil)
            #expect(result.checks.allSatisfied)
            let expectedChecks: Set<String> = scenario.name == "MCChangRoberts"
                ? ["TypeOK", "Correctness", "Liveness"] : ["TypeOK", "Correctness"]
            #expect(Set(result.checks.properties.keys) == expectedChecks)
        }
    }
}
