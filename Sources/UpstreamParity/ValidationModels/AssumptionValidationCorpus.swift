import SwiftTLA

private struct AssumptionModelRegistration: Sendable {
    let id: String
    let scenarios: @Sendable () throws -> [any AssumptionValidationScenario]
}

private let assumptionModels: [AssumptionModelRegistration] = [
    .init(id: "sums-even", scenarios: {
        try SumsEvenModel.validationScenarios().map { $0 as any AssumptionValidationScenario }
    }),
    .init(id: "stones", scenarios: {
        try StonesModel.validationScenarios().map { $0 as any AssumptionValidationScenario }
    })
]

func hasAssumptionValidationRegistration(_ id: String) -> Bool {
    assumptionModels.contains { $0.id == id }
}

func assumptionValidationScenarios(for id: String) throws -> [any AssumptionValidationScenario]? {
    guard let model = assumptionModels.first(where: { $0.id == id }) else { return nil }
    return try model.scenarios()
}

package func assumptionValidationScenarios() throws -> [(id: String, scenario: any AssumptionValidationScenario)] {
    try assumptionModels.flatMap { model in
        let scenarios = try model.scenarios()
        guard !scenarios.isEmpty else {
            throw EvidenceFormatError.invalidField(record: model.id, field: "no scenarios")
        }
        return scenarios.enumerated().map { ("\(model.id)-\($0.offset)", $0.element) }
    }
}
