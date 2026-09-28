import Testing
@testable import SwiftTLA

struct AssumptionOnlyValidationTests {
    @Test("configured assumptions produce native verdicts and state-free TLC input")
    func checksConfiguredAssumptionsWithoutState() throws {
        let scenarios = try AssumptionOnlyFixture.validationScenarios()
        #expect(scenarios.map(\.name) == ["even", "odd"])
        let evaluations = try scenarios.map { try $0.evaluateAssumptions() }
        #expect(evaluations.map(\.satisfied) == [true, false])
        #expect(evaluations.allSatisfy { $0.evaluatedValues.isEmpty })
        for scenario in scenarios {
            let rendered = try scenario.render()
            #expect(rendered.tlaBundle.cfg == "CONSTANT limit = \(scenario.configuration.limit)\n")
            #expect(rendered.tlaBundle.tla.contains("ASSUME"))
            #expect(!rendered.tlaBundle.tla.contains("VARIABLES"))
            #expect(!rendered.tlaBundle.tla.contains("Init =="))
        }
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try AssumptionOnlyFixture.Configuration(limit: 4)
        }
    }

    @Test("PrintT records only the branch evaluated by a configured assumption")
    func recordsAssumptionValuesAtEvaluationSite() throws {
        let scenarios = try PrintedAssumptionFixture.validationScenarios()
        #expect(scenarios.map(\.name) == ["solution", "fallback"])
        let results = try scenarios.map { try $0.evaluateAssumptions() }
        #expect(results.map(\.satisfied) == [true, true])
        #expect(results.map(\.evaluatedValues) == [[.int(2)], [.string("No solution")]])
        #expect(try scenarios[0].render().tlaBundle.tla.contains("PrintT("))
    }
}
