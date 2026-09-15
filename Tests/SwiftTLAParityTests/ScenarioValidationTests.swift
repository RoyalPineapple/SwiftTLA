import Testing
import SwiftTLA
import UpstreamParity

struct ScenarioValidationTests {
    @Test("expected failures change only the validation verdict")
    func distinguishesExpectedDeadlock() throws {
        let scenarios = try DeadlockScenarios.validationScenarios()
        let unexpected = try NativeScenarioRun(scenarios[0], maximumStates: 1)
        let expected = try NativeScenarioRun(scenarios[1], maximumStates: 1)
        #expect(unexpected.native.graph == expected.native.graph)
        #expect(unexpected.native.checks == expected.native.checks)
        #expect(unexpected.expectations.isEmpty)
        #expect(throws: ScenarioExpectationError.self) { try unexpected.validateExpectations() }
        try expected.validateExpectations()
    }

    @Test("scenario validation rejects omitted checks")
    func rejectsMissingExpectations() throws {
        let original = try #require(ConfiguredCounter.validationScenarios().first)
        #expect(throws: EvidenceFormatError.invalidField(record: original.name, field: "scenario check coverage")) {
            try NativeScenarioRun(IncompleteCounterScenario(original: original), maximumStates: 10)
        }
    }

    @Test("Counter scenarios derive canonical graphs and every property result without runtime compilation")
    func derivesCompleteCounterEvidence() throws {
        for scenario in try ConfiguredCounter.validationScenarios() {
            let run = try NativeScenarioRun(scenario, maximumStates: 10)
            try run.validateExpectations()
            #expect(run.name == scenario.name)
            #expect(run.native.graph.isComparable)
            #expect(run.native.graph.graph.states.count == scenario.configuration.limit + 1)
            #expect(Set(run.native.checks.properties.keys) == run.native.rendered.checkNames)
            guard case .reached(let witness) = run.native.checks.properties["AtLimit"] else {
                Issue.record("Missing Counter reachability witness")
                continue
            }
            #expect(witness.steps.count == scenario.configuration.limit + 1)
            if scenario.configuration.stopAtLimit {
                #expect(run.native.checks.deadlock == .satisfied)
            } else {
                guard case .violated(let deadlock) = run.native.checks.deadlock else {
                    Issue.record("Missing expected deadlock witness")
                    continue
                }
                try deadlock.validate(in: run.native.graph.graph)
                #expect(deadlock.steps.count == scenario.configuration.limit + 1)
            }
        }
    }

    @Test("expected failures do not suppress incomplete exploration")
    func rejectsIncompleteExpectedFailure() throws {
        let scenario = try #require(ConfiguredCounter.validationScenarios().last)
        #expect(throws: ExplorationError.stateLimitExceeded(2)) {
            try NativeScenarioRun(scenario, maximumStates: 2)
        }
    }
}
