import Testing
@testable import SwiftTLA

struct AssumptionOnlyValidationTests {
    @Test("configured assumptions produce native verdicts and state-free TLC input")
    func checksConfiguredAssumptionsWithoutState() throws {
        let scenarios = try AssumptionOnlyFixture.validationScenarios()
        #expect(scenarios.map(\.name) == ["even", "odd"])
        #expect(try scenarios.map { try $0.checkAssumptions() } == [true, false])
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
}
