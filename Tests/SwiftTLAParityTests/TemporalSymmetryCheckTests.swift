import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

struct TemporalSymmetryCheckTests {
  @Test("Temporal cases preserve bounded fairness outcomes")
  func temporalCasesPreserveFairnessOutcomes() throws {
    let zero = CanonicalState(bindings: ["x": .integer(0)])
    let one = CanonicalState(bindings: ["x": .integer(1)])
    let two = CanonicalState(bindings: ["x": .integer(2)])
    let expected = try CanonicalGraph(initialStates: [zero], states: [zero, one, two], edges: [
      .init(source: zero.key, action: "A", target: two.key),
      .init(source: zero.key, action: "B", target: one.key),
      .init(source: one.key, action: "C", target: zero.key),
      .init(source: two.key, action: "Stay", target: two.key)
    ])
    let cases = try registeredManifest().temporalCases
    #expect(cases.map(\.fairness) == [.none, .weak, .strong])
    for temporalCase in cases {
      let fairness = temporalCase.fairness
      let model = try temporalConformanceRun(fairness: fairness, maximumStates: 10)
      #expect(Set(model.properties.keys) == ["AlwaysP", "EventuallyP", "AlwaysEventuallyP",
        "EventuallyAlwaysP", "LeadsToPQ", "LeavesZero"])
      for check in model.properties.values {
        #expect(check.graph.isComplete)
        #expect(check.graph.graph == expected)
        #expect(check.result != .unavailable)
      }
      for (property, native) in model.properties {
        let expectsProgress = property == "LeavesZero" && fairness != .none
        if expectsProgress {
          #expect(native.result == .satisfied)
        } else if case .violated(let trace) = native.result {
          #expect(trace == native.graph.trace)
        } else {
          Issue.record("Expected a native counterexample for \(temporalCase.id)/\(property)")
        }
      }
      #expect(throws: ExplorationError.stateLimitExceeded(2)) {
        try temporalConformanceRun(fairness: fairness, maximumStates: 2)
      }
    }
  }

  @Test("Temporal cases require unreduced Swift exploration")
  func temporalCasesRejectSymmetryReduction() throws {
    let temporalCase = try #require(try registeredManifest().temporalCases.first)

    #expect(throws: EvidenceFormatError.self) {
      _ = try TemporalCase(
        id: temporalCase.id,
        fairness: temporalCase.fairness,
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
      ).explore()
      let reduced = try ModelChecker(
        compilation: compilation,
        configuration: symmetryCase.reducedExploration
      ).explore().graph

      #expect(raw.graph.states.count == 1 << scope)
      #expect(reduced.states.count == scope + 1)
      let rawBundle = try compilation.render().tlaBundle(
        symmetryReduction: symmetryCase.rawExploration.symmetryReduction)
      #expect(rawBundle.cfg.contains("SYMMETRY") == false)
      #expect(raw.initialStateIDs.count == 1)
      let initialID = try #require(raw.initialStateIDs.first)
      let initial = try #require(raw.compiledStates[initialID])
      let chosen = try #require(compilation.layout.variables.first { $0.declaration.name == "chosen" })
      let members = try #require(chosen.collection?.members)
      let allZero = CompiledValue.function(Dictionary(uniqueKeysWithValues: members.map { ($0, .integer(0)) }))
      #expect(try initial.value(for: chosen.id) == allZero)
      #expect(try compilation.render().tlaBundle(
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
      fairness: .none,
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

    #expect(outcomes.count == 7)
    #expect(outcomes.allSatisfy { $0.outcome == .unavailable })
    #expect(Set(outcomes.map(\.caseID)) == ["temporal-AlwaysP", "temporal-EventuallyP",
      "temporal-AlwaysEventuallyP", "temporal-EventuallyAlwaysP", "temporal-LeadsToPQ", "temporal-LeavesZero", "symmetry"])
    for caseID in outcomes.map(\.caseID) {
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
