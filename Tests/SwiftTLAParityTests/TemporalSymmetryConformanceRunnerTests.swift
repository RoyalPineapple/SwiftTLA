import Foundation
import SwiftTLA
import Testing
import UpstreamParity

struct TemporalSymmetryConformanceRunnerTests {
  @Test("Temporal cases preserve bounded fairness outcomes")
  func temporalCasesPreserveFairnessOutcomes() throws {
    for declaredCase in try registeredCases().cases where declaredCase.kind == .temporal {
      let model = try TemporalSymmetryModelCatalog.model(for: declaredCase)
      let compilation = try model.spec.compile()
      let exploration = try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
      ).explore()
      let analyses = LivenessChecker(compilation: compilation, graph: exploration.graph).analyze(
        initialStateIDs: exploration.initialStateIDs,
        isComplete: exploration.isComplete
      )
      #expect(analyses.allSatisfy { $0.status == .violated })
    }
  }

  @Test("Symmetry cases use the compiled runtime for raw and reduced exploration")
  func symmetryCasesUseCompiledReduction() throws {
    for declaredCase in try registeredCases().cases where declaredCase.kind == .symmetry {
      let model = try TemporalSymmetryModelCatalog.model(for: declaredCase)
      let scope = try #require(declaredCase.configuration.symmetryScope)
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
      #expect(try compilation.renderedTLAModuleBundle(usesSymmetryReduction: false).cfg.contains("SYMMETRY") == false)
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
