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
        configuration: temporalCase.exploration
      ).explore()
      let analyses = try exploration.analyzeTemporalProperties(in: compilation)
      #expect(analyses.allSatisfy { $0.status == .violated })
    }
  }

  @Test("Temporal cases require unreduced Swift exploration")
  func temporalCasesRejectSymmetryReduction() throws {
    let temporalCase = try #require(try registeredManifest().temporalCases.first)

    #expect(throws: EvidenceFormatError.self) {
      _ = try TemporalCase(
        id: temporalCase.id,
        sourceInput: temporalCase.sourceInput,
        configuration: temporalCase.configuration,
        exploration: FiniteExplorationConfiguration(
          maximumStateLimit: temporalCase.exploration.maximumStateLimit,
          symmetryReduction: .enabled(maximumPermutationCount: 2)
        )
      )
    }
  }

  @Test("Symmetry cases use the compiled runtime for raw and reduced exploration")
  func symmetryCasesUseCompiledReduction() throws {
    for symmetryCase in try registeredManifest().symmetryCases {
      let scope = symmetryCase.scope
      let compilation = try symmetryConformanceSpec(scope: scope).compile()
      let raw = try ModelChecker(
        compilation: compilation,
        configuration: symmetryCase.rawExploration
      ).explore().graph
      let reduced = try ModelChecker(
        compilation: compilation,
        configuration: symmetryCase.reducedExploration
      ).explore().graph

      #expect(raw.states.count == 1 << scope)
      #expect(reduced.states.count == scope + 1)
      let rawBundle = compilation.renderedTLAModuleBundle(
        symmetryReduction: symmetryCase.rawExploration.symmetryReduction)
      #expect(rawBundle.cfg.contains("SYMMETRY") == false)
      #expect(rawBundle.tla.contains("Init == chosen = [member \\in ChosenKeys |-> 0]"))
      #expect(compilation.renderedTLAModuleBundle(
        symmetryReduction: symmetryCase.reducedExploration.symmetryReduction
      ).cfg.contains("SYMMETRY"))
    }
  }

  @Test("Temporal and symmetry cases retain unavailable outcomes")
  func unavailableCasesRetainOutcomes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TemporalSymmetryCheckTests-\(UUID())",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("TemporalFixture.tla")
    try Data("---- MODULE TemporalFixture ----\n====\n".utf8).write(to: source)
    let exploration = try FiniteExplorationConfiguration(
      maximumStateLimit: 10,
      symmetryReduction: .disabled
    )
    let temporalCase = try TemporalCase(
      id: "temporal",
      sourceInput: try SourceInputPin(
        path: "TemporalFixture.tla",
        sha256: SHA256.hex(Data(contentsOf: source))
      ),
      configuration: .init(property: .always, fairness: .none, allowsImplicitStuttering: false),
      exploration: exploration
    )
    let symmetryCase = try SymmetryCase(
      id: "symmetry",
      scope: 2,
      rawExploration: exploration,
      reducedExploration: try .init(
        maximumStateLimit: 10,
        symmetryReduction: .enabled(maximumPermutationCount: 2)
      )
    )
    let output = root.appendingPathComponent("evidence", isDirectory: true)
    let outcomes = try TemporalSymmetryCheck().run(.init(
      manifest: try .init(temporalCases: [temporalCase], symmetryCases: [symmetryCase]),
      projectRoot: root,
      outputDirectory: output,
      toolRoot: root.appendingPathComponent("missing-toolchain", isDirectory: true),
      referencePin: try testReferencePin()
    ))

    #expect(outcomes.map(\.outcome) == [.unavailable, .unavailable])
    for caseID in ["temporal", "symmetry"] {
      let record = try #require(try JSONSerialization.jsonObject(
        with: Data(contentsOf: output
          .appendingPathComponent(caseID, isDirectory: true)
          .appendingPathComponent("case-outcome.json"))
      ) as? [String: String])
      #expect(record["caseID"] == caseID)
      #expect(record["outcome"] == TemporalSymmetryOutcome.unavailable.rawValue)
      #expect(record["diagnostic"]?.isEmpty == false)
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
