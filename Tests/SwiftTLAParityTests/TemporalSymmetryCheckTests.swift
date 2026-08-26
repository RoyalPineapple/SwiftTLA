import Foundation
import SwiftTLA
import Testing
import UpstreamParity

struct TemporalSymmetryCheckTests {
  @Test("Temporal cases preserve bounded fairness outcomes")
  func temporalCasesPreserveFairnessOutcomes() throws {
    for temporalCase in try registeredCases().cases where temporalCase.kind == .temporal {
      let model = try TemporalSymmetryModelCatalog.model(for: temporalCase)
      let compilation = try model.spec.compile()
      let exploration = try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
      ).explore()
      let analyses = exploration.analyzeTemporalProperties(in: compilation)
      #expect(analyses.allSatisfy { $0.status == .violated })
    }
  }

  @Test("Symmetry cases use the compiled runtime for raw and reduced exploration")
  func symmetryCasesUseCompiledReduction() throws {
    for temporalCase in try registeredCases().cases where temporalCase.kind == .symmetry {
      let model = try TemporalSymmetryModelCatalog.model(for: temporalCase)
      let scope = try #require(temporalCase.configuration.symmetryScope)
      let compilation = try model.spec.compile()
      let configuration = try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
      let raw = try ModelChecker(
        compilation: compilation,
        configuration: configuration,
        usesSymmetryReduction: false
      ).explore().graph
      let reduced = try ModelChecker(
        compilation: compilation,
        configuration: configuration,
        usesSymmetryReduction: true
      ).explore().graph

      #expect(raw.states.count == 1 << scope)
      #expect(reduced.states.count == scope + 1)
      let rawBundle = try compilation.renderedTLAModuleBundle(usesSymmetryReduction: false)
      #expect(rawBundle.cfg.contains("SYMMETRY") == false)
      #expect(rawBundle.tla.contains("Init == chosen = [member \\in ChosenKeys |-> 0]"))
      #expect(try compilation.renderedTLAModuleBundle(usesSymmetryReduction: true).cfg.contains("SYMMETRY"))
    }
  }

  private func registeredCases() throws -> TemporalSymmetryCases {
    try JSONDecoder().decode(
      TemporalSymmetryCases.self,
      from: Data(contentsOf: projectRoot().appendingPathComponent(
        "Verification/TemporalSymmetryConformance/cases.json"))
    )
  }

  private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
