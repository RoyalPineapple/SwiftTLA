import Testing
import SwiftTLA
@testable import UpstreamParity

struct TeachingConcurrencyCorpusStateGraphTests {
    @Test("The five-process Simple configuration checks its complete graph and three invariants")
    func configuredSimple() throws {
        let scenario = try #require(TeachingSimpleN5Model.validationScenarios().first)
        #expect(scenario.name == "Simple")
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == 1)
        #expect(graph.states.count == 723)
        #expect(run.native.checks.properties == [
            "PCorrect": .satisfied, "TypeOK": .satisfied, "Inv": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }

    @Test("The eight-process SimpleRegular configuration checks its complete graph and three invariants")
    func configuredSimpleRegular() throws {
        let scenario = try #require(TeachingSimpleRegularN8Model.validationScenarios().first)
        #expect(scenario.name == "SimpleRegular")
        let run = try NativeScenarioRun(scenario, maximumStates: 300_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == 1)
        #expect(graph.states.count == 277_726)
        #expect(run.native.checks.properties == [
            "PCorrect": .satisfied, "TypeOK": .satisfied, "Inv": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }
}
