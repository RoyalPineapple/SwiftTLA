import SwiftTLA

package func modelValidationScenarios() throws -> [(id: String, scenario: any ModelValidationScenario)] {
    let models: [(id: String, scenarios: [any ModelValidationScenario])] = [
        ("counter", try ConfiguredCounter.validationScenarios()),
        ("configured-processes", try ConfiguredProcessMachine.validationScenarios()),
        ("weakly-fair-processes", try WeaklyFairConfiguredProcessMachine.validationScenarios()),
        ("strongly-fair-processes", try StronglyFairConfiguredProcessMachine.validationScenarios()),
        ("recurring-population", try RecurringPopulation.validationScenarios()),
        ("scoped-temporal-claims", try ScopedTemporalClaims.validationScenarios()),
        ("conditional-temporal-claims", try ConditionalTemporalClaims.validationScenarios()),
        ("transition-property-claims", try TransitionPropertyClaims.validationScenarios()),
        ("independent-atomic-steps", try IndependentAtomicSteps.validationScenarios()),
        ("parameterized-atomic-steps", try ParameterizedAtomicSteps.validationScenarios()),
        ("configured-dictionary-values", try ConfiguredDictionaryValues.validationScenarios()),
        ("scoped-reachability-claims", try ScopedReachabilityClaims.validationScenarios()),
        ("constant-state-claims", try ConstantStateClaims.validationScenarios()),
        ("labelled-property-claims", try LabelledPropertyClaims.validationScenarios()),
        ("refinement-counter", try RefinementScenarioCounter.validationScenarios()),
        ("dining-philosophers", try DiningPhilosophersModel.validationScenarios()),
        ("die-hard", try DieHardModel.validationScenarios()),
        ("hour-clock", try HourClockModel.validationScenarios()),
        ("hour-clock-2", try HourClock2Model.validationScenarios()),
        ("least-circular-substring", try LeastCircularSubstringModel.validationScenarios()),
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
