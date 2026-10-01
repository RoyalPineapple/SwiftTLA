import SwiftTLA

private struct ModelRegistration: Sendable {
    let id: String
    let scenarios: @Sendable () throws -> [any ModelValidationScenario]
}

private let fixtureModelRegistrations: [ModelRegistration] = [
    .init(id: "counter", scenarios: { try ConfiguredCounter.validationScenarios() }),
    .init(id: "configured-processes", scenarios: { try ConfiguredProcessMachine.validationScenarios() }),
    .init(id: "weakly-fair-processes", scenarios: { try WeaklyFairConfiguredProcessMachine.validationScenarios() }),
    .init(id: "strongly-fair-processes", scenarios: { try StronglyFairConfiguredProcessMachine.validationScenarios() }),
    .init(id: "recurring-population", scenarios: { try RecurringPopulation.validationScenarios() }),
    .init(id: "scoped-temporal-claims", scenarios: { try ScopedTemporalClaims.validationScenarios() }),
    .init(id: "conditional-temporal-claims", scenarios: { try ConditionalTemporalClaims.validationScenarios() }),
    .init(id: "transition-property-claims", scenarios: { try TransitionPropertyClaims.validationScenarios() }),
    .init(id: "independent-atomic-steps", scenarios: { try IndependentAtomicSteps.validationScenarios() }),
    .init(id: "mixed-step-composition", scenarios: { try MixedStepComposition.validationScenarios() }),
    .init(id: "ordered-procedure-call", scenarios: { try OrderedCallModel.validationScenarios() }),
    .init(id: "recursive-step", scenarios: { try RecursiveStep.validationScenarios() }),
    .init(id: "parameterized-atomic-steps", scenarios: { try ParameterizedAtomicSteps.validationScenarios() }),
    .init(id: "configured-dictionary-values", scenarios: { try ConfiguredDictionaryValues.validationScenarios() }),
    .init(id: "record-union-ordering", scenarios: { try RecordUnionOrderingModel.validationScenarios() }),
    .init(id: "record-union-field-domains", scenarios: { try RecordUnionFieldDomainModel.validationScenarios() }),
    .init(id: "record-union-sentinel", scenarios: { try RecordUnionSentinelModel.validationScenarios() }),
    .init(id: "scoped-reachability-claims", scenarios: { try ScopedReachabilityClaims.validationScenarios() }),
    .init(id: "constant-state-claims", scenarios: { try ConstantStateClaims.validationScenarios() }),
    .init(id: "labelled-property-claims", scenarios: { try LabelledPropertyClaims.validationScenarios() }),
    .init(id: "refinement-counter", scenarios: { try RefinementScenarioCounter.validationScenarios() }),
    .init(id: "selected-checks", scenarios: { try SelectedChecksModel.validationScenarios() }),
    .init(id: "unselected-predicates", scenarios: { try UnselectedPredicateModel.validationScenarios() })
]

private let upstreamModelRegistrations: [ModelRegistration] = [
    .init(id: "dining-philosophers", scenarios: { try DiningPhilosophersModel.validationScenarios() }),
    .init(id: "bakery", scenarios: { try BakeryModel.validationScenarios() }),
    .init(id: "boulanger", scenarios: { try BoulangerModel.validationScenarios() }),
    .init(id: "multicar-elevator", scenarios: { try MultiCarElevator.validationScenarios() }),
    .init(id: "tlcmc-graph-1", scenarios: { try TLCMCModel.validationScenarios() }),
    .init(id: "voteproof", scenarios: { try VoteProofModel.validationScenarios() }),
    .init(id: "kvsnap", scenarios: { try KVsnapModel.validationScenarios() }),
    .init(id: "string-literals", scenarios: { try StringLiteralModel.validationScenarios() }),
    .init(id: "action-references", scenarios: { try ActionReferencesModel.validationScenarios() }),
    .init(id: "die-hard", scenarios: { try DieHardModel.validationScenarios() }),
    .init(id: "die-harder", scenarios: { try DieHarderModel.validationScenarios() }),
    .init(id: "die-hardest", scenarios: { try DieHardestModel.validationScenarios() }),
    .init(id: "die-hardest-global-freeze", scenarios: { try DieHardestGlobalFreezeModel.validationScenarios() }),
    .init(id: "die-hardest-parallel", scenarios: { try DieHardestParallelModel.validationScenarios() }),
    .init(id: "channel", scenarios: { try ChannelModel.validationScenarios() }),
    .init(id: "asynch-interface", scenarios: { try AsynchInterfaceModel.validationScenarios() }),
    .init(id: "majority", scenarios: { try MajorityModel.validationScenarios() }),
    .init(id: "n-queens", scenarios: { try NQueensModel.validationScenarios() }),
    .init(id: "queens", scenarios: { try QueensModel.validationScenarios() }),
    .init(id: "coffee-can", scenarios: { try CoffeeCanModel.validationScenarios() }),
    .init(id: "cigarette-smokers", scenarios: { try CigaretteSmokersModel.validationScenarios() }),
    .init(id: "chameneos", scenarios: { try ChameneosModel.validationScenarios() }),
    .init(id: "prisoners", scenarios: { try PrisonersModel.validationScenarios() }),
    .init(id: "prisoners-single-switch", scenarios: { try PrisonerSingleSwitchModel.validationScenarios() }),
    .init(id: "single-lane-bridge", scenarios: { try SingleLaneBridgeModel.validationScenarios() }),
    .init(id: "game-of-life", scenarios: { try GameOfLifeModel.validationScenarios() }),
    .init(id: "two-phase", scenarios: { try TwoPhaseModel.validationScenarios() }),
    .init(id: "teaching-simple", scenarios: { try TeachingSimpleN5Model.validationScenarios() }),
    .init(id: "teaching-simple-regular", scenarios: { try TeachingSimpleRegularN8Model.validationScenarios() }),
    .init(id: "hour-clock", scenarios: { try HourClockModel.validationScenarios() }),
    .init(id: "hour-clock-2", scenarios: { try HourClock2Model.validationScenarios() }),
    .init(id: "least-circular-substring", scenarios: { try LeastCircularSubstringModel.validationScenarios() }),
    .init(id: "find-highest", scenarios: { try FindHighestModel.validationScenarios() }),
    .init(id: "binary-search", scenarios: { try BinarySearchModel.validationScenarios() }),
    .init(id: "quicksort", scenarios: { try QuicksortModel.validationScenarios() })
]

private let modelRegistrations = fixtureModelRegistrations + upstreamModelRegistrations

func hasUpstreamModelValidationRegistration(_ id: String) -> Bool {
    upstreamModelRegistrations.contains { $0.id == id }
}

package func modelValidationScenarios(for id: String) throws -> [any ModelValidationScenario]? {
    guard let registration = modelRegistrations.first(where: { $0.id == id }) else { return nil }
    return try registration.scenarios()
}

package func modelValidationScenarios() throws -> [(id: String, scenario: any ModelValidationScenario)] {
    try modelRegistrations.flatMap { model in
        let scenarios = try model.scenarios()
        guard !scenarios.isEmpty else {
            throw EvidenceFormatError.invalidField(record: model.id, field: "no scenarios")
        }
        return scenarios.enumerated().map { ("\(model.id)-\($0.offset)", $0.element) }
    }
}
