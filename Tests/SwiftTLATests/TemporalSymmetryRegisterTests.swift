import Foundation
import Testing
import UpstreamParity
import SwiftTLA

struct TemporalSymmetryRegisterTests {
  @Test("P3 register declares every temporal form, fairness boundary, and exact symmetry scope")
  func registerIsCompleteAndCrossLinked() throws {
    let root = try packageRoot()
    let register = try decode(TemporalSymmetryCasesV1.self, root, "cases.json")
    let ledger = try decode(TemporalSymmetryDivergenceLedgerV1.self, root, "divergences.json")
    let support = try decode(TemporalSymmetrySupportSurfaceV1.self, root, "support-surface.json")
    try support.validate(cases: register, ledger: ledger)

    let temporal = register.cases.filter { $0.kind == .temporal }
    let baseline = try baseline(root)
    #expect(Set(temporal.compactMap(\.configuration.property)) == [
      "AlwaysP", "EventuallyP", "AlwaysEventuallyP", "EventuallyAlwaysP", "LeadsToPQ"
    ])
    #expect(Set(temporal.compactMap(\.configuration.fairness)) == [.none, .weak, .strong])
    #expect(temporal.allSatisfy { $0.finiteBounds.limits["states"] == 3 })
    let reachability = try #require(baseline["temporalReachabilityBounds"] as? [String: Any])
    #expect(reachability["states"] as? Int == 3)
    #expect(reachability["stateValues"] as? [Int] == [0, 1, 2])
    #expect(Set(register.cases.filter { $0.kind == .symmetry }.compactMap(\.configuration.symmetryScope))
      .isSuperset(of: [2, 3, 4]))
    #expect(support.entries.contains { $0.requestedStatus == .unsupported })
  }

  @Test("P3 symmetry scopes use distinct raw and TLC SYMMETRY configurations")
  func symmetryConfigurationsAreExecutablePairs() throws {
    let root = try packageRoot()
    let register = try decode(TemporalSymmetryCasesV1.self, root, "cases.json")
    let baseline = try baseline(root)
    let configurations = try #require(baseline["configurationFixtures"] as? [String: [String: String]])
    let expectedScopes = Set(2...4)
    let requested = register.cases.filter {
      $0.kind == .symmetry && $0.expectedOutcome == .exact && expectedScopes.contains($0.configuration.symmetryScope ?? 0)
    }
    #expect(Set(requested.compactMap(\.configuration.symmetryScope)) == expectedScopes)
    for item in requested {
      let fixture = try #require(configurations[item.id])
      let reducedPath = try #require(fixture["path"])
      let rawPath = try #require(fixture["rawPath"])
      let reduced = try String(contentsOf: root.appendingPathComponent(reducedPath))
      let raw = try String(contentsOf: root.appendingPathComponent(rawPath))
      #expect(reducedPath != rawPath)
      #expect(reduced.contains("SYMMETRY Symmetry"))
      #expect(!raw.contains("SYMMETRY"))
      #expect(item.provenance.cfgSHA256 == fixture["sha256"])
      #expect(try SHA256V1.hex(Data(contentsOf: root.appendingPathComponent(rawPath))) == fixture["rawSHA256"])
      let module = try String(contentsOf: root.appendingPathComponent(item.sourceInput.path))
      #expect(module.contains("Symmetry == Permutations(Members)"))
    }
  }

  @Test("P3 fairness boundary rejects the intermittent B/C recurrence only under strong fairness")
  func fairnessBoundaryUsesIntermittentEnabledness() throws {
    let root = try packageRoot()
    let register = try decode(TemporalSymmetryCasesV1.self, root, "cases.json")
    let weak = try #require(register.cases.first { $0.id == "temporal-weak-fairness-boundary" })
    let strong = try #require(register.cases.first { $0.id == "temporal-strong-fairness-boundary" })
    #expect(weak.configuration.property == "AlwaysEventuallyP")
    #expect(strong.configuration.property == weak.configuration.property)
    #expect(weak.configuration.fairness == .weak)
    #expect(strong.configuration.fairness == .strong)
    #expect(weak.configuration.fairnessActions == ["A"])
    #expect(strong.configuration.fairnessActions == ["A"])
    let start = StateGraph.StateID(0)
    let alternate = StateGraph.StateID(1)
    let accepting = StateGraph.StateID(2)
    let graph = StateGraph(
      specName: "intermittent-fairness-boundary", variableNames: ["x"],
      transitions: [
        start: [.init(action: "A", target: accepting), .init(action: "B", target: alternate)],
        alternate: [.init(action: "C", target: start)],
        accepting: [.init(action: "Stay", target: accepting)]
      ],
      states: [
        start: ["x": .int(0)], alternate: ["x": .int(1)], accepting: ["x": .int(2)]
      ])
    let predicate: StateExpr = .equal(.variable("x"), .value(.int(2)))
    let actions = ["A", "B", "C", "Stay"].map { NamedAction(name: $0, body: .guard_(true)) }
    let checker = LivenessChecker(graph: graph)
    let weakResult = checker.analyze(
      .alwaysEventually(predicate), fairness: [.weakFairness("A")], actions: actions, initialStateIDs: [start])
    let strongResult = checker.analyze(
      .alwaysEventually(predicate), fairness: [.strongFairness("A")], actions: actions, initialStateIDs: [start])
    #expect(weakResult.status == .violated)
    #expect(weakResult.witness?.cycle == [start, alternate, start])
    #expect(weakResult.enabledActions["A"]?[start] == true)
    #expect(weakResult.enabledActions["A"]?[alternate] == false)
    #expect(weakResult.fairComponents.contains(Set([start, alternate])))
    #expect(strongResult.status == .violated)
    #expect(strongResult.rejectedComponents.contains(Set([start, alternate])))
    #expect(strongResult.witness?.cycle == [alternate, alternate])
  }

  @Test("P3 unsupported boundaries retain distinct executable control shapes")
  func unsupportedControlsMatchTheirBoundaryDescriptions() throws {
    let root = try packageRoot()
    let baseline = try baseline(root)
    let controls = try #require(baseline["unsupportedControls"] as? [String: [String: String]])
    for control in controls.values {
      let modulePath = try #require(control["module"])
      let configurationPath = try #require(control["configuration"])
      let module = try String(contentsOf: root.appendingPathComponent(modulePath))
      let configuration = try String(contentsOf: root.appendingPathComponent(configurationPath))
      #expect(module.contains("Symmetry") || module.contains("LegacySymmetryGroup"))
      #expect(configuration.contains("SYMMETRY"))
      #expect(try SHA256V1.hex(Data(contentsOf: root.appendingPathComponent(modulePath))) == control["moduleSHA256"])
      #expect(try SHA256V1.hex(Data(contentsOf: root.appendingPathComponent(configurationPath))) == control["configurationSHA256"])
    }
    let combined = try #require(controls["combined-temporal-symmetry"])
    let combinedConfiguration = try String(contentsOf: root.appendingPathComponent(try #require(combined["configuration"])))
    #expect(combinedConfiguration.contains("PROPERTY"))
    let nested = try #require(controls["nested-members-symmetry"])
    let nestedConfiguration = try String(contentsOf: root.appendingPathComponent(try #require(nested["configuration"])))
    #expect(nestedConfiguration.contains("{{a}, {b}}"))
    let support = try decode(TemporalSymmetrySupportSurfaceV1.self, root, "support-surface.json")
    #expect(support.entries.contains { $0.id == "nested-members-symmetry" && $0.requestedStatus == .unsupported })
    #expect(support.entries.filter { $0.kind == .temporal && $0.requestedStatus == .requested }
      .allSatisfy { $0.finiteBounds.limits["states"] == 3 })
  }

  @Test("P3 register pins every declared source input to its checked-in digest")
  func registerSourceDigestsMatchFixtures() throws {
    let root = try packageRoot()
    let register = try decode(TemporalSymmetryCasesV1.self, root, "cases.json")
    let baseline = try baseline(root)
    let configurations = try #require(baseline["configurationFixtures"] as? [String: [String: String]])
    for item in register.cases {
      let source = root.appendingPathComponent(item.sourceInput.path)
      #expect(FileManager.default.fileExists(atPath: source.path))
      #expect(try SHA256V1.hex(Data(contentsOf: source)) == item.sourceInput.sha256)
      let configuration = try #require(configurations[item.id])
      let path = try #require(configuration["path"])
      let sha256 = try #require(configuration["sha256"])
      #expect(try SHA256V1.hex(Data(contentsOf: root.appendingPathComponent(path))) == sha256)
      #expect(item.provenance.cfgSHA256 == sha256)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ root: URL, _ name: String) throws -> T {
    try JSONDecoder().decode(
      type,
      from: Data(contentsOf: root.appendingPathComponent("Verification/TemporalSymmetryConformance/\(name)")))
  }

  private func baseline(_ root: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
      "Verification/TemporalSymmetryConformance/baselines/manifest.json"))) as? [String: Any])
  }

  private func packageRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
      let parent = directory.deletingLastPathComponent()
      guard parent != directory else { throw CocoaError(.fileNoSuchFile) }
      directory = parent
    }
    return directory
  }
}
