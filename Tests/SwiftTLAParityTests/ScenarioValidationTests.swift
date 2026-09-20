import Testing
import SwiftTLA
@testable import UpstreamParity

struct ScenarioValidationTests {
    @Test("registered model scenarios have unique identities")
    func identifiesRegisteredScenarios() throws {
        let scenarios = try modelValidationScenarios()
        #expect(scenarios.count == 63)
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

    @Test("scenario admission requires complete agreeing checks and declared expectations")
    func validatesIndependentResults() throws {
        for scenario in try ConfiguredCounter.validationScenarios() {
            let run = try NativeScenarioRun(scenario, maximumStates: 10)
            var checks = run.native.checks.properties.map { name, result in
                PropertyComparison(caseID: scenario.name, check: .property(name), status: .exact,
                    swiftResult: result, tlcResult: result)
            }
            let deadlock = try #require(run.native.checks.deadlock)
            checks.append(.init(caseID: scenario.name, check: .deadlock, status: .exact,
                swiftResult: deadlock, tlcResult: deadlock))
            try run.validateComparison(.init(differences: []), checks: checks)
            #expect(throws: EvidenceFormatError.self) {
                try run.validateComparison(.init(differences: []), checks: Array(checks.dropLast()))
            }
            #expect(throws: EvidenceFormatError.self) {
                try run.validateComparison(.init(differences: []), checks: checks + [checks[0]])
            }
            #expect(throws: ScenarioExpectationError.self) {
                try run.validateComparison(.init(differences: [.completion(tlc: false, swift: true)]), checks: checks)
            }
            for status in [PropertyComparisonStatus.unavailable, .propertyOutcomeDifference, .graphDifference] {
                var changed = checks
                changed[0] = .init(caseID: scenario.name, check: checks[0].check, status: status,
                    swiftResult: checks[0].swiftResult, tlcResult: checks[0].tlcResult)
                #expect(throws: ScenarioExpectationError.self) {
                    try run.validateComparison(.init(differences: []), checks: changed)
                }
            }
            checks[checks.count - 1] = .init(caseID: scenario.name, check: .deadlock, status: .exact,
                swiftResult: deadlock, tlcResult: .unavailable)
            #expect(throws: ScenarioExpectationError.self) {
                try run.validateComparison(.init(differences: []), checks: checks)
            }
        }
    }

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

    @Test("expected temporal outcomes leave initialization, transitions, fairness, and results unchanged")
    func expectationsPreserveFairBehavior() throws {
        let original = try #require(WeaklyFairConfiguredProcessMachine.validationScenarios()
            .first { $0.configuration.nodes == [1] && $0.behavior == .specification })
        let changed = WeaklyFairConfiguredProcessMachine.ValidationScenario(
            name: original.name, configuration: original.configuration,
            checking: original.checking, behavior: original.behavior,
            expectations: [.AllVisited: .violated], deadlockExpectation: original.deadlockExpectation)
        #expect(try Set(original.initialMachines().map(\.snapshot)) == Set(changed.initialMachines().map(\.snapshot)))
        let originalRun = try NativeScenarioRun(original, maximumStates: 10)
        let changedRun = try NativeScenarioRun(changed, maximumStates: 10)
        #expect(originalRun.native.graph == changedRun.native.graph)
        #expect(originalRun.native.checks == changedRun.native.checks)
        #expect(originalRun.native.checks.properties["AllVisited"] == .satisfied)
        #expect(originalRun.native.checks.deadlock == .satisfied)
        let originalBundle = try original.render().tlaBundle
        let changedBundle = try changed.render().tlaBundle
        #expect(originalBundle.tla == changedBundle.tla)
        #expect(originalBundle.cfg == changedBundle.cfg)
        #expect(originalBundle.tla.contains("WF_<<selected, pc>>(visit(_process))"))
        try originalRun.validateExpectations()
        #expect(throws: ScenarioExpectationError.unexpectedOutcome(
            check: .property("AllVisited"), expected: .violated, actual: .satisfied)) {
            try changedRun.validateExpectations()
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
            #expect(run.expectations["__pcal_assert_0"] == .satisfied)
            #expect(run.native.checks.properties["__pcal_assert_0"] == .satisfied)
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
