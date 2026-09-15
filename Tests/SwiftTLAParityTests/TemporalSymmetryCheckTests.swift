import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

struct TemporalSymmetryCheckTests {
  @Test("expected violations require a counterexample result, never an unavailable check")
  func expectedVerdictsRejectMissingAndOppositeResults() throws {
    let model = try temporalConformanceRun(fairness: .none, maximumStates: 10)
    let violation = try #require(model.checks.properties["AlwaysP"])
    #expect(ValidationExpectation.violated.accepts(violation))
    #expect(!ValidationExpectation.satisfied.accepts(violation))
    #expect(ValidationExpectation.satisfied.accepts(.satisfied))
    #expect(!ValidationExpectation.violated.accepts(.satisfied))
    #expect(!ValidationExpectation.satisfied.accepts(.unavailable))
    #expect(!ValidationExpectation.violated.accepts(.unavailable))
  }

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
      let model = try temporalConformanceRun(fairness: temporalCase.fairness, maximumStates: 10)
      #expect(Set(model.checks.properties.keys) == ["AlwaysP", "EventuallyP", "AlwaysEventuallyP",
        "EventuallyAlwaysP", "LeadsToPQ", "LeavesZero"])
      #expect(model.graph.isComplete)
      #expect(model.checks.deadlock == .satisfied)
      #expect(model.graph.graph == expected)
      #expect(model.graph.trace == nil)
      #expect(model.checks.properties.values.allSatisfy { $0 != .unavailable })
      for (property, native) in model.checks.properties {
        let expectation = try #require(temporalCase.expectedProperties[property])
        #expect(expectation.accepts(native))
        if case .violated(let trace) = native {
          try trace.validate(in: model.graph.graph)
        }
      }
      #expect(throws: ExplorationError.stateLimitExceeded(2)) {
        try temporalConformanceRun(fairness: temporalCase.fairness, maximumStates: 2)
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
        ),
        expectedProperties: temporalCase.expectedProperties
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
      exploration: exploration,
      expectedProperties: try #require(registeredManifest().temporalCases.first).expectedProperties
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

    #expect(outcomes.count == 8)
    #expect(outcomes.allSatisfy { $0.outcome == .unavailable })
    #expect(Set(outcomes.map(\.caseID)) == ["temporal-properties-AlwaysP", "temporal-properties-EventuallyP",
      "temporal-properties-AlwaysEventuallyP", "temporal-properties-EventuallyAlwaysP", "temporal-properties-LeadsToPQ", "temporal-properties-LeavesZero", "temporal-deadlock", "symmetry"])
    let modelDirectory = output.appendingPathComponent("temporal")
    #expect(FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("swift-graph.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("source-input").path))
    for caseID in outcomes.map(\.caseID) {
      let directory: URL
      switch caseID {
      case "symmetry": directory = output.appendingPathComponent(caseID)
      case "temporal-deadlock": directory = modelDirectory.appendingPathComponent("deadlock")
      default:
        directory = modelDirectory.appendingPathComponent("properties")
          .appendingPathComponent(String(caseID.dropFirst("temporal-properties-".count)))
      }
      #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("swift-graph.jsonl").path))
      let record = try #require(try JSONSerialization.jsonObject(
        with: Data(contentsOf: directory.appendingPathComponent("case-outcome.json"))
      ) as? [String: String])
      #expect(record["caseID"] == caseID)
      #expect(record["outcome"] == TemporalSymmetryOutcome.unavailable.rawValue)
      #expect(record["diagnostic"]?.isEmpty == false)
      if caseID != "symmetry" {
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("check-error.txt").path))
      }
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
