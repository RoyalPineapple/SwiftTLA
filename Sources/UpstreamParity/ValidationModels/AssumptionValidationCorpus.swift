import SwiftTLA

package func assumptionValidationScenarios() throws -> [(id: String, scenario: any AssumptionValidationScenario)] {
    try SumsEvenModel.validationScenarios().enumerated().map {
        ("sums-even-\($0.offset)", $0.element)
    }
}
