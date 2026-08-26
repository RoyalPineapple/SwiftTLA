import Foundation
import SwiftTLA
import Testing
import UpstreamParity

struct TemporalSymmetryCheckTests {
  @Test("Temporal cases preserve bounded fairness outcomes")
  func temporalCasesPreserveFairnessOutcomes() throws {
    for temporalCase in try registeredManifest().temporalCases {
      let compilation = try temporalConformanceSpec(configuration: temporalCase.configuration).compile()
      let exploration = try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)
      ).explore()
      let analyses = exploration.analyzeTemporalProperties(in: compilation)
      #expect(analyses.allSatisfy { $0.status == .violated })
    }
  }

  @Test("Symmetry cases use the compiled runtime for raw and reduced exploration")
  func symmetryCasesUseCompiledReduction() throws {
    for symmetryCase in try registeredManifest().symmetryCases {
      let scope = symmetryCase.scope
      let compilation = try symmetryConformanceSpec(scope: scope).compile()
      let configuration = try FiniteExplorationConfiguration(maximumStateLimit: 1 << (scope + 1))
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
      let rawBundle = compilation.renderedTLAModuleBundle(usesSymmetryReduction: false)
      #expect(rawBundle.cfg.contains("SYMMETRY") == false)
      #expect(rawBundle.tla.contains("Init == chosen = [member \\in ChosenKeys |-> 0]"))
      #expect(compilation.renderedTLAModuleBundle(usesSymmetryReduction: true).cfg.contains("SYMMETRY"))
    }
  }

  private func registeredManifest() throws -> TemporalSymmetryManifest {
    try JSONDecoder().decode(
      TemporalSymmetryManifest.self,
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
