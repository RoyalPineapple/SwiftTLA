import SwiftTLA

package func modelValidationScenarios() throws -> [(id: String, scenario: any ModelValidationScenario)] {
    let models: [(id: String, scenarios: [any ModelValidationScenario])] = [
        ("counter", try ConfiguredCounter.validationScenarios()),
        ("configured-processes", try ConfiguredProcessMachine.validationScenarios()),
        ("weakly-fair-processes", try WeaklyFairConfiguredProcessMachine.validationScenarios()),
        ("strongly-fair-processes", try StronglyFairConfiguredProcessMachine.validationScenarios()),
        ("recurring-population", try RecurringPopulation.validationScenarios()),
        ("scoped-temporal-claims", try ScopedTemporalClaims.validationScenarios()),
        ("dining-philosophers", try DiningPhilosophersModel.validationScenarios()),
        ("selected-checks", try SelectedChecksModel.validationScenarios()),
        ("unselected-predicates", try UnselectedPredicateModel.validationScenarios())
    ]
    return try models.flatMap { model in
        guard !model.scenarios.isEmpty else {
            throw EvidenceFormatError.invalidField(record: model.id, field: "no scenarios")
        }
        return model.scenarios.enumerated().map { ("\(model.id)-\($0.offset)", $0.element) }
    }
}
