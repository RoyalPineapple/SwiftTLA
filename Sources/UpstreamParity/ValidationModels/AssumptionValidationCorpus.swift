import Foundation
import SwiftTLA

private struct AssumptionModelRegistration: Sendable {
    let id: String
    let scenarios: @Sendable () throws -> [any AssumptionValidationScenario]
}

private let assumptionModels: [AssumptionModelRegistration] = [
    .init(id: "car-talk-puzzle", scenarios: {
        try CarTalkPuzzleModel.validationScenarios().map { $0 as any AssumptionValidationScenario }
    }),
    .init(id: "print-values", scenarios: {
        try PrintValuesModel.validationScenarios().map { $0 as any AssumptionValidationScenario }
    }),
    .init(id: "simple-math", scenarios: {
        try SimpleMathModel.validationScenarios().map { $0 as any AssumptionValidationScenario }
    }),
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
    let root = try RetainedFiles.projectRoot(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
        from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
    return try manifest.cases.compactMap { declaration in
        guard let scenario = try declaration.resolveAssumptionScenario() else { return nil }
        return (declaration.id, scenario)
    }
}
