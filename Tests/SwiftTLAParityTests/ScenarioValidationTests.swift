import Testing
import SwiftTLA
@testable import UpstreamParity

struct ScenarioValidationTests {
    @Test("named upstream configurations reach native validation without positional duplicates")
    func identifiesNamedUpstreamScenario() throws {
        let scenarios = try modelValidationScenarios()
        for (id, name) in [
            ("ewd840-ap", "APEWD840"),
            ("ewd840-json-0", "EWD840_json"),
            ("sync-termination-detection-ap", "APSyncTerminationDetection")
        ] {
            #expect(scenarios.first { $0.id == id }?.scenario.name == name)
        }
        #expect(Set(scenarios.map(\.id)).isDisjoint(with: [
            "ewd840-1", "ewd840-2", "sync-termination-detection-1"
        ]))
    }

    @Test("registered model scenarios have unique identities")
    func identifiesRegisteredScenarios() throws {
        let scenarios = try modelValidationScenarios()
        #expect(!scenarios.isEmpty)
        #expect(Set(scenarios.map(\.id)).count == scenarios.count)
    }

    @Test("registered scenarios retain exhausted graphs or decisive counterexamples with declared outcomes",
        arguments: try modelValidationScenarios().map(\.id))
    func validatesRegisteredScenarios(id: String) throws {
        let scenario = try #require(modelValidationScenarios().first { $0.id == id }).scenario
        let run = try NativeScenarioRun(scenario, maximumStates: 10_000_000)
        try run.validateExpectations()
        if let graph = run.native.graph { #expect(graph.isComparable) }
        #expect(Set(run.native.checks.properties.keys) == run.native.rendered.checkNames)
    }
}
