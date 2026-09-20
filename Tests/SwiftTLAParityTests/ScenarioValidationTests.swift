import Testing
import SwiftTLA
@testable import UpstreamParity

struct ScenarioValidationTests {
    @Test("registered model scenarios have unique identities")
    func identifiesRegisteredScenarios() throws {
        let scenarios = try modelValidationScenarios()
        #expect(scenarios.count == 66)
        #expect(Set(scenarios.map(\.id)).count == scenarios.count)
    }

    @Test("registered model scenarios derive complete graphs and satisfy their declared outcomes",
        arguments: try modelValidationScenarios().map(\.id))
    func validatesRegisteredScenarios(id: String) throws {
        let scenario = try #require(modelValidationScenarios().first { $0.id == id }).scenario
        let run = try NativeScenarioRun(scenario, maximumStates: 10_000_000)
        try run.validateExpectations()
        #expect(run.native.graph.isComparable)
        #expect(Set(run.native.checks.properties.keys) == run.native.rendered.checkNames)
    }
}
