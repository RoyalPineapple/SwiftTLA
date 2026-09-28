import SwiftTLA

package func assumptionValidationScenarios() throws -> [(id: String, scenario: any AssumptionValidationScenario)] {
    let sumsEven: [(id: String, scenario: any AssumptionValidationScenario)] = try SumsEvenModel.validationScenarios().enumerated().map {
        ("sums-even-\($0.offset)", $0.element as any AssumptionValidationScenario)
    }
    let stones: [(id: String, scenario: any AssumptionValidationScenario)] = try StonesModel.validationScenarios().enumerated().map {
        ("stones-\($0.offset)", $0.element as any AssumptionValidationScenario)
    }
    return sumsEven + stones
}
