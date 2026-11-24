import SwiftTLA
import Testing
@testable import UpstreamParity

struct ReadersWritersCorpusCheckingTests {
    @Test("the same request queue satisfies the published safety and fair scenarios")
    func publishedScenarios() throws {
        let scenarios = try ReadersWritersModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["APReadersWriters", "MC"])
        for scenario in scenarios {
            let run = try NativeScenarioRun(scenario, maximumStates: 25_000)
            try run.validateExpectations()
            let graph = try #require(run.native.graph)
            #expect(graph.isComplete)
            #expect(graph.graph.initialStateKeys.count == 1)
            #expect(graph.graph.states.count == 21_527)
            let expected = scenario.name == "MC" ? ["TypeOK", "Safety", "Liveness"] : ["Safety"]
            #expect(Set(run.native.checks.properties.keys) == Set(expected))
            #expect(run.native.checks.properties.values.allSatisfy { $0 == .satisfied })
            #expect(run.native.checks.deadlock == .satisfied)
        }
    }
}
