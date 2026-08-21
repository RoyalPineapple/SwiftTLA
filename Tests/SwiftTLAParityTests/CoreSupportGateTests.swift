import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct CoreSupportGateTests {
  @Test("retained MultiCarElevator evidence admits only its declared bounded surface")
  func admitsRetainedElevatorEvidence() throws {
    let input = try GateFixture.retainedElevatorInput()
    let report = try CoreSupportGate().evaluate(input)

    #expect(report.finalExitClass == .success)
    #expect(report.entries.filter { $0.decision == .admitted }.count == 2)
    #expect(report.entries.filter { $0.decision == .unsupported }.count == 1)
    #expect(report.entries.filter { $0.decision == .admitted }.allSatisfy {
      $0.reasonCodes.isEmpty && $0.caseRunCorrelations.allSatisfy { $0.gateRunID == input.gateRunID }
    })
  }

  @Test("missing, stale, incomplete, and fabricated evidence blocks requested support")
  func blocksInvalidEvidence() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()

    #expect(reasons(in: try gate.evaluate(try fixture.input(excluding: "hour-clock")),
                    for: "hour-clock-reachable-state-space").contains(.missingEvidence))
    #expect(reasons(in: try gate.evaluate(try fixture.input(prerequisiteAvailable: false)),
                    for: "hour-clock-reachable-state-space").contains(.missingPrerequisite))

    try fixture.remove("graph-events.jsonl", from: "hour-clock")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.replaceRunID(in: "hour-clock", with: UUID())
    let foreignRunReport = try gate.evaluate(try fixture.input())
    #expect(reasons(in: foreignRunReport,
                    for: "hour-clock-reachable-state-space").contains(.foreignRun))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "case.json", key: "moduleSHA256", with: fixture.digest)
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.manifestDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.remove("governance", fromJSONFile: "case.json", in: "hour-clock")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.manifestDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "toolchain.json", key: "javaVersion", with: "0")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.toolchainDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "swift-run.json", key: "schema", with: "invented")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "comparison.json", key: "conformant", with: false)
    try fixture.replaceJSONValue(in: "hour-clock", file: "comparison.json", key: "differences", with: [
      ["category": "non-exact", "expected": [], "actual": []]
    ])
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))
  }

  @Test("a changed permanent-regression fingerprint blocks admission")
  func blocksFingerprintDrift() throws {
    let fixture = try GateFixture()
    try fixture.replaceJSONValue(in: "hour-clock-edge-mismatch", file: "comparison.json", key: "differences", with: [
      ["category": "different-difference", "expected": [], "actual": []]
    ])
    let report = try CoreSupportGate().evaluate(try fixture.input())
    #expect(report.finalExitClass == .blocked)
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space").contains(.unresolvedDivergence))
  }

  @Test("a changed ledger fingerprint is unexplained even when retained evidence is otherwise complete")
  func blocksChangedDeclaredFingerprint() throws {
    let fixture = try GateFixture()
    let report = try CoreSupportGate().evaluate(try fixture.input(
      ledger: try fixture.ledgerWithChangedFingerprint(recordID: "hour-clock-edge-mismatch")))

    #expect(report.finalExitClass == .blocked)
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space")
      .contains(.unexplainedDivergence))
  }

  @Test("execution and comparison failures have distinct stable admission reasons")
  func classifiesExecutionAndNonExactFailures() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()

    try fixture.replaceJSONValue(in: "hour-clock", file: "run.json", key: "exitCode", with: 2)
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.executionFailed))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "run.json", key: "exitCode", with: 1)
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.nonExactComparison))
  }

  @Test("canonical graph records must satisfy their graph events and comparisons")
  func blocksFabricatedCanonicalGraph() throws {
    let fixture = try GateFixture()
    try fixture.replaceJSONValue(in: "hour-clock", file: "tlc-run.json", key: "states", with: [])
    let report = try CoreSupportGate().evaluate(try fixture.input())
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space").contains(.partialEvidence))
  }

  @Test("retained graph evidence uses its declared exploration bound")
  func blocksReceiptWithDifferentExplorationBound() throws {
    let fixture = try GateFixture()
    try fixture.mutateJSONObject(in: "hour-clock", file: "swift-run.json") { record in
      var context = try #require(record["receiptContext"] as? [String: Any])
      context["maximumStateLimit"] = 1
      record["receiptContext"] = context
    }

    let report = try CoreSupportGate().evaluate(try fixture.input())
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space").contains(.partialEvidence))
  }

  @Test("TLC process evidence has one complete lifecycle and artifact manifest")
  func blocksInvalidTLCProcessLifecycle() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()

    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").isEmpty)

    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc-process.json") { object in
      var primary = try #require(object["primary"] as? [String: Any])
      primary["status"] = 999
      object["primary"] = primary
    }
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc-process.json") { object in
      let primary = try #require(object["primary"] as? [String: Any])
      object["attempted"] = ["primary", "replay"]
      object["replay"] = primary
    }
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.remove("replay.json", fromJSONFile: "raw-artifacts.json", in: "hour-clock")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.mutateJSONObject(in: "die-hard-violation", file: "tlc-process.json") { object in
      object["attempted"] = ["primary", "trace"]
      object["replay"] = NSNull()
    }
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    #expect(reasons(in: try gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").isEmpty)
  }

  @Test("every retained violation auxiliary is required and must match the primary run")
  func blocksForgedViolationAuxiliaries() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()
    let requestedSupport = "hour-clock-reachable-state-space"

    for file in [
      "graph-events.jsonl", "graph-events.trace.jsonl", "graph-events.replay.jsonl",
      "counterexample.json", "replay.json"
    ] {
      try fixture.reset("die-hard-violation")
      try fixture.write(Data("forged".utf8), named: file, in: "die-hard-violation")
      let report = try gate.evaluate(try fixture.input())
      #expect(reasons(in: report, for: requestedSupport).contains(.unresolvedDivergence))
    }
  }

  @Test("violation traces and replays must preserve one exact action path")
  func blocksForgedTraceAndReplayPaths() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()
    let requestedSupport = "hour-clock-reachable-state-space"

    try fixture.mutateCounterexampleActionSource(in: "die-hard-violation", file: "counterexample.json")
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.mutateReplayInitialState(in: "die-hard-violation")
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.appendReplayTransition(in: "die-hard-violation")
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.mutateTraceToNonInitialSuffix(in: "die-hard-violation")
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))
  }

  @Test("process lifecycle and canonical TLC outcome must agree in both directions")
  func blocksProcessOutcomeMismatches() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGate()
    let requestedSupport = "hour-clock-reachable-state-space"

    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc-run.json") { object in
      object["outcome"] = ["kind": "invariantViolation", "message": "forged violation"]
    }
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport).contains(.partialEvidence))

    try fixture.reset("die-hard-violation")
    try fixture.mutateJSONObject(in: "die-hard-violation", file: "tlc-process.json") { object in
      object["attempted"] = ["primary"]
      object["primary"] = ["status": 0, "isViolation": false, "reportedExhaustiveCompletion": true]
      object["trace"] = NSNull()
      object["replay"] = NSNull()
    }
    try fixture.mutateJSONObject(in: "die-hard-violation", file: "raw-artifacts.json") { object in
      object["graph-events.trace.jsonl"] = false
      object["graph-events.replay.jsonl"] = false
      object["counterexample.json"] = false
      object["replay.json"] = false
    }
    for file in ["graph-events.trace.jsonl", "graph-events.replay.jsonl", "counterexample.json", "replay.json"] {
      try fixture.remove(file, from: "die-hard-violation")
    }
    #expect(reasons(in: try gate.evaluate(try fixture.input()), for: requestedSupport).contains(.unresolvedDivergence))
  }

  @Test("resolved divergences retain history but require a current exact reproduction")
  func admitsResolvedDivergenceWithExactCurrentEvidence() throws {
    let fixture = try GateFixture()
    try fixture.resetResolvedRegression("hour-clock-edge-mismatch")
    let ledger = try fixture.resolvedLedger(recordID: "hour-clock-edge-mismatch")
    let report = try CoreSupportGate().evaluate(try fixture.input(ledger: ledger))
    #expect(report.entries.first { $0.supportID == "hour-clock-reachable-state-space" }?.decision == .admitted)
  }

  @Test("every retained divergence must be linked from the support surface")
  func rejectsUnlinkedDivergence() throws {
    let fixture = try GateFixture()
    let input = try fixture.input()
    let entries = try input.surface.entries.map { entry in
      try CoreSupportSurfaceEntry(
        id: entry.id, behavior: entry.behavior, category: entry.category, finiteBounds: entry.finiteBounds,
        relation: entry.relation, mandatoryCaseIDs: entry.mandatoryCaseIDs,
        requestedStatus: entry.requestedStatus,
        linkedDivergenceIDs: entry.id == "hour-clock-altered-transition-control" ? [] : entry.linkedDivergenceIDs,
        reason: entry.reason)
    }
    let incompleteSurface = try CoreSupportSurface(entries: entries)
    #expect(throws: ConformanceGovernanceError.invalidField(record: "support surface", field: "unlinked divergence")) {
      try incompleteSurface.validate(caseIDs: Set(input.manifest.cases.map(\.id)), ledger: input.ledger)
    }
  }

  private func reasons(in report: CoreSupportAdmission, for supportID: String) -> Set<CoreSupportReasonCode> {
    Set(report.entries.first { $0.supportID == supportID }?.reasonCodes ?? [])
  }
}

private final class GateFixture {
  let gateRunID = UUID()
  let root: URL
  let digest = String(repeating: "f", count: 64)
  private let fileManager = FileManager.default
  private let caseIDs = [
    "hour-clock", "die-hard-type-ok", "hour-clock-edge-mismatch", "die-hard-violation"
  ]
  private var initialLedger: CoreDivergenceLedger?

  init() throws {
    root = fileManager.temporaryDirectory.appendingPathComponent("CoreSupportGateTests-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for caseID in caseIDs { try reset(caseID) }
    let ledger = try currentLedger()
    initialLedger = try CoreDivergenceLedger(records: ledger.records.filter {
      !$0.id.hasPrefix("multicar-elevator")
    })
  }

  deinit { try? fileManager.removeItem(at: root) }

  func input(
    excluding excludedCaseID: String? = nil,
    prerequisiteAvailable: Bool = true,
    excludingCaseIDs: Set<String> = [],
    ledger overrideLedger: CoreDivergenceLedger? = nil
  ) throws -> CoreSupportGateInput {
    let manifest = try decode(CoreConformanceCasesManifest.self, at: "Verification/CoreConformance/cases.json")
    let ledger = try overrideLedger ?? #require(initialLedger)
    let fullSurface = try decode(CoreSupportSurface.self, at: "Verification/CoreConformance/support-surface.json")
    let surface = try CoreSupportSurface(entries: fullSurface.entries.filter {
      !$0.id.hasPrefix("multicar-elevator")
    })
    return CoreSupportGateInput(
      gateRunID: gateRunID, manifest: manifest, ledger: ledger, surface: surface,
      evidence: caseIDs.filter { $0 != excludedCaseID && !excludingCaseIDs.contains($0) }.map {
        CoreSupportCaseEvidence(
          caseID: $0, directory: root.appendingPathComponent($0),
          relativeDirectory: ".build/core-conformance-evidence/\($0)")
      }, prerequisiteAvailable: prerequisiteAvailable)
  }

  static func retainedElevatorInput() throws -> CoreSupportGateInput {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let verificationRoot = projectRoot.appendingPathComponent("Verification/CoreConformance")
    let manifest = try JSONDecoder().decode(
      CoreConformanceCasesManifest.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("cases.json")))
    let allLedger = try JSONDecoder().decode(
      CoreDivergenceLedger.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("divergences.json")))
    let ledger = try CoreDivergenceLedger(records: allLedger.records.filter {
      $0.id == "multicar-elevator-edge-mismatch"
    })
    let allSurface = try JSONDecoder().decode(
      CoreSupportSurface.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("support-surface.json")))
    let surface = try CoreSupportSurface(entries: allSurface.entries.filter {
      $0.id.hasPrefix("multicar-elevator")
    })
    let gateRunID = try #require(UUID(uuidString: "04b730b6-3a5e-4c9a-a3f9-55e414a696a5"))

    return CoreSupportGateInput(
      gateRunID: gateRunID,
      manifest: manifest,
      ledger: ledger,
      surface: surface,
      evidence: [
        CoreSupportCaseEvidence(
          caseID: "multicar-elevator",
          directory: verificationRoot.appendingPathComponent("baselines/multicar-elevator"),
          relativeDirectory: "Verification/CoreConformance/baselines/multicar-elevator"),
        CoreSupportCaseEvidence(
          caseID: "multicar-elevator-edge-mismatch",
          directory: verificationRoot.appendingPathComponent("baselines/multicar-elevator-edge-mismatch"),
          relativeDirectory: "Verification/CoreConformance/baselines/multicar-elevator-edge-mismatch")
      ])
  }

  func reset(_ caseID: String) throws {
    let destination = root.appendingPathComponent(caseID)
    if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let source: URL
    if caseID == "hour-clock-edge-mismatch" || caseID == "die-hard-violation" {
      source = projectURL("Verification/CoreConformance/fixtures/\(caseID)/evidence")
    } else {
      source = projectURL("Verification/CoreConformance/baselines/\(caseID)")
    }
    for file in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
      try fileManager.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
    }
    try rewriteEvidence(caseID, in: destination)
  }

  func resetResolvedRegression(_ caseID: String) throws {
    let destination = root.appendingPathComponent(caseID)
    if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let source = projectURL("Verification/CoreConformance/baselines/hour-clock")
    for file in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
      try fileManager.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
    }
    try rewriteEvidence(caseID, in: destination)
    var run = try #require(JSONSerialization.jsonObject(
      with: Data(contentsOf: destination.appendingPathComponent("run.json"))) as? [String: Any])
    run["exitCode"] = 0
    try write(run, named: "run.json", in: destination)
  }

  func replaceRunID(in caseID: String, with newRunID: UUID) throws {
    let directory = root.appendingPathComponent(caseID)
    let oldRunID = gateRunID.uuidString.lowercased()
    for file in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where file.pathExtension == "json" {
      let source = try #require(String(data: Data(contentsOf: file), encoding: .utf8))
      try Data(source.replacingOccurrences(of: oldRunID, with: newRunID.uuidString.lowercased()).utf8).write(to: file)
    }
  }

  func replaceJSONValue(in caseID: String, file: String, key: String, with value: Any) throws {
    let url = root.appendingPathComponent(caseID).appendingPathComponent(file)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    if key == "javaVersion" {
      for pinKey in ["declaredPin", "referencePin"] {
        var pin = try #require(object[pinKey] as? [String: Any])
        pin[key] = value
        object[pinKey] = pin
      }
    } else {
      object[key] = value
    }
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
  }

  func remove(_ file: String, from caseID: String) throws {
    try fileManager.removeItem(at: root.appendingPathComponent(caseID).appendingPathComponent(file))
  }

  func remove(_ key: String, fromJSONFile file: String, in caseID: String) throws {
    let url = root.appendingPathComponent(caseID).appendingPathComponent(file)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    object.removeValue(forKey: key)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
  }

  func mutateJSONObject(
    in caseID: String,
    file: String,
    _ mutate: (inout [String: Any]) throws -> Void
  ) throws {
    let url = root.appendingPathComponent(caseID).appendingPathComponent(file)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    try mutate(&object)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
  }

  func mutateCounterexampleActionSource(in caseID: String, file: String) throws {
    let url = root.appendingPathComponent(caseID).appendingPathComponent(file)
    var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var counterexample = try #require(root["counterexample"] as? [String: Any])
    var actions = try #require(counterexample["action"] as? [Any])
    var triple = try #require(actions[0] as? [Any])
    var source = try #require(triple[0] as? [Any])
    var bindings = try #require(source[1] as? [String: Any])
    bindings["big"] = 1
    source[1] = bindings
    triple[0] = source
    actions[0] = triple
    counterexample["action"] = actions
    root["counterexample"] = counterexample
    try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]).write(to: url)
  }

  func mutateReplayInitialState(in caseID: String) throws {
    try mutateGraphEvents(in: caseID, file: "graph-events.replay.jsonl") { records in
      let initialIndex = try #require(records.firstIndex { $0["type"] as? String == "initial" })
      let transition = try #require(records.first {
        $0["type"] as? String == "transition" && $0["callback"] as? String == "writeState.action"
      })
      records[initialIndex]["state"] = transition["target"]
    }
  }

  func appendReplayTransition(in caseID: String) throws {
    try mutateGraphEvents(in: caseID, file: "graph-events.replay.jsonl") { records in
      let transition = try #require(records.first {
        $0["type"] as? String == "transition" && $0["callback"] as? String == "writeState.action"
      })
      records.insert(transition, at: records.count - 1)
    }
  }

  func mutateTraceToNonInitialSuffix(in caseID: String) throws {
    for file in ["counterexample.json", "replay.json"] {
      try mutateJSONObject(in: caseID, file: file) { root in
        var counterexample = try #require(root["counterexample"] as? [String: Any])
        let states = try #require(counterexample["state"] as? [Any])
        let actions = try #require(counterexample["action"] as? [Any])
        counterexample["state"] = Array(states.dropFirst())
        counterexample["action"] = Array(actions.dropFirst())
        root["counterexample"] = counterexample
      }
    }

    try mutateGraphEvents(in: caseID, file: "graph-events.replay.jsonl") { records in
      let initialIndex = try #require(records.firstIndex { $0["type"] as? String == "initial" })
      let transitionIndex = try #require(records.firstIndex {
        $0["type"] as? String == "transition" && $0["callback"] as? String == "writeState.action"
      })
      records[initialIndex]["state"] = records[transitionIndex]["target"]
      records.remove(at: transitionIndex)
    }
  }

  private func mutateGraphEvents(
    in caseID: String,
    file: String,
    _ mutate: (inout [[String: Any]]) throws -> Void
  ) throws {
    let url = root.appendingPathComponent(caseID).appendingPathComponent(file)
    var records = try Data(contentsOf: url).split(separator: 10).map { line in
      try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
    }
    try mutate(&records)
    for index in records.indices { records[index]["seq"] = index }
    let body = try records.dropLast().map {
      try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) + Data("\n".utf8)
    }.reduce(into: Data(), { $0.append($1) })
    var footer = try #require(records.last)
    footer["lastBodySeq"] = records.count - 2
    footer["bodySha256"] = SHA256.hex(body)
    footer["counts"] = Dictionary(grouping: records.dropLast(), by: { $0["type"] as? String ?? "" })
      .mapValues(\.count)
    records[records.count - 1] = footer
    let data = try records.map {
      try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) + Data("\n".utf8)
    }.reduce(into: Data(), { $0.append($1) })
    try data.write(to: url)
  }

  func write(_ data: Data, named file: String, in caseID: String) throws {
    try data.write(to: root.appendingPathComponent(caseID).appendingPathComponent(file))
  }

  private func rewriteEvidence(_ caseID: String, in directory: URL) throws {
    let manifest = try decode(CoreConformanceCasesManifest.self, at: "Verification/CoreConformance/cases.json")
    let declared = try #require(manifest.cases.first { $0.id == caseID })
    let correlation = ["caseID": caseID, "engine": "runner", "runID": gateRunID.uuidString.lowercased()]
    let pin: [String: Any] = [
      "tag": TLCReferencePin.fixture.tag, "commit": TLCReferencePin.fixture.commit,
      "jarSHA256": TLCReferencePin.fixture.jarSHA256,
      "javaDistribution": TLCReferencePin.fixture.javaDistribution,
      "javaVersion": TLCReferencePin.fixture.javaVersion,
      "javaArchiveSHA256": TLCReferencePin.fixture.javaArchiveSHA256,
      "bridgeClass": TLCReferencePin.fixture.bridgeClass,
      "bridgeSourceSHA256": TLCReferencePin.fixture.bridgeSourceSHA256,
      "bridgeBinarySHA256": TLCReferencePin.fixture.bridgeBinarySHA256
    ]
    try write([
      "id": caseID, "moduleSHA256": declared.moduleSHA256, "cfgSHA256": declared.cfgSHA256,
      "arguments": declared.arguments, "argumentsSHA256": declared.argumentsSHA256,
      "workers": declared.workers, "fingerprintPolynomial": declared.fingerprintPolynomial,
      "deadlock": declared.deadlock, "operatingSystem": "macos", "architecture": "arm64",
      "environment": [:], "pin": pin, "governance": governanceJSON(declared.governance),
      "invocationMappings": declared.invocationMappings.map { mapping in
        ["wrapper": mapping.wrapper, "action": mapping.action,
         "arguments": mapping.arguments, "indices": mapping.indices]
      },
      "valueNormalizations": declared.valueNormalizations.map { normalization in
        ["binding": normalization.binding, "functionKeys": normalization.functionKeys]
      }
    ], named: "case.json", in: directory)
    var toolchain = try #require(JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent("toolchain.json"))) as? [String: Any])
    toolchain["declaredPin"] = pin
    toolchain["referencePin"] = pin
    try write(toolchain, named: "toolchain.json", in: directory)
    try write(["arguments": declared.arguments], named: "arguments.json", in: directory)
    try write([
      "swift": ["caseID": caseID, "engine": "swift", "runID": gateRunID.uuidString.lowercased()],
      "tlc": ["caseID": caseID, "engine": "tlc", "runID": gateRunID.uuidString.lowercased()],
      "runner": correlation
    ], named: "correlations.json", in: directory)
    try write(["correlation": correlation, "exitCode": declared.governance.expectedRegressionOutcome == .exact ? 0 : 1],
              named: "run.json", in: directory)
    try rewriteCanonicalRun(named: "swift-run.json", caseID: caseID, engine: "swift", in: directory)
    try rewriteCanonicalRun(named: "tlc-run.json", caseID: caseID, engine: "tlc", in: directory)
    var comparison = try #require(JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent("comparison.json"))) as? [String: Any])
    comparison["correlation"] = correlation
    try write(comparison, named: "comparison.json", in: directory)
    try rewriteProcess(caseID, in: directory)
    try rewriteGraphEvents(caseID: caseID, declared: declared, pin: pin, in: directory)
  }

  private func rewriteCanonicalRun(named file: String, caseID: String, engine: String, in directory: URL) throws {
    var object = try #require(JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent(file))) as? [String: Any])
    object["correlation"] = ["caseID": caseID, "engine": engine, "runID": gateRunID.uuidString.lowercased()]
    try write(object, named: file, in: directory)
  }

  private func rewriteProcess(_ caseID: String, in directory: URL) throws {
    var object = try #require(JSONSerialization.jsonObject(
      with: Data(contentsOf: directory.appendingPathComponent("tlc-process.json"))) as? [String: Any])
    object["correlation"] = ["caseID": caseID, "engine": "tlc", "runID": gateRunID.uuidString.lowercased()]
    try write(object, named: "tlc-process.json", in: directory)
  }

  private func rewriteGraphEvents(
    caseID: String, declared: CoreConformanceCasesManifest.Entry, pin: [String: Any], in directory: URL
  ) throws {
    let tlcTag = try #require(pin["tag"])
    let tlcCommit = try #require(pin["commit"])
    let tlcJarSHA256 = try #require(pin["jarSHA256"])
    let javaDistribution = try #require(pin["javaDistribution"])
    let javaVersion = try #require(pin["javaVersion"])
    let javaArchiveSHA256 = try #require(pin["javaArchiveSHA256"])
    let bridgeClass = try #require(pin["bridgeClass"])
    let bridgeSourceSHA256 = try #require(pin["bridgeSourceSHA256"])
    let bridgeBinarySHA256 = try #require(pin["bridgeBinarySHA256"])
    let provenance: [String: Any] = [
      "tlcTag": tlcTag, "tlcCommit": tlcCommit, "tlcJarSha256": tlcJarSHA256,
      "javaDistribution": javaDistribution, "javaVersion": javaVersion,
      "javaArchiveSha256": javaArchiveSHA256, "bridgeClass": bridgeClass,
      "bridgeSourceSha256": bridgeSourceSHA256, "bridgeBinarySha256": bridgeBinarySHA256,
      "moduleSha256": declared.moduleSHA256, "cfgSha256": declared.cfgSHA256,
      "arguments": declared.arguments, "argumentsSha256": declared.argumentsSHA256,
      "workers": declared.workers, "fingerprintPolynomial": declared.fingerprintPolynomial,
      "deadlock": declared.deadlock, "os": "macos", "architecture": "arm64", "environment": [:]
    ]
    for name in ["graph-events.jsonl", "graph-events.trace.jsonl", "graph-events.replay.jsonl"] {
      let url = directory.appendingPathComponent(name)
      guard fileManager.fileExists(atPath: url.path) else { continue }
      var records = try Data(contentsOf: url).split(separator: 10).map { line -> [String: Any] in
        try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
      }
      for index in records.indices {
        records[index]["caseId"] = caseID
        records[index]["runId"] = gateRunID.uuidString.lowercased()
      }
      records[0]["provenance"] = provenance
      let body = try records.dropLast().map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) + Data("\n".utf8)
      }.reduce(into: Data(), { $0.append($1) })
      var footer = records[records.count - 1]
      footer["bodySha256"] = SHA256.hex(body)
      records[records.count - 1] = footer
      let data = try records.map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) + Data("\n".utf8)
      }.reduce(into: Data(), { $0.append($1) })
      try data.write(to: url)
    }
  }

  private func currentLedger() throws -> CoreDivergenceLedger {
    try decode(CoreDivergenceLedger.self, at: "Verification/CoreConformance/divergences.json")
  }

  func resolvedLedger(recordID: String) throws -> CoreDivergenceLedger {
    let records = try #require(initialLedger).records.map { record in
      let isResolved = record.id == recordID
      return try CoreDivergenceRecord(
        id: record.id, provenance: record.provenance, semanticCitations: record.semanticCitations,
        reproducer: record.reproducer, originalEvidence: record.originalEvidence,
        permanentRegressionCaseID: record.permanentRegressionCaseID,
        classification: record.classification, disposition: isResolved ? .resolved : record.disposition,
        normalizedDifferenceFingerprint: record.normalizedDifferenceFingerprint,
        latestComparison: isResolved
          ? try CoreDivergenceComparison(
            evidence: record.latestComparison.evidence, outcome: .exact, normalizedDifferenceFingerprint: nil)
          : record.latestComparison)
    }
    return try CoreDivergenceLedger(records: records)
  }

  func ledgerWithChangedFingerprint(recordID: String) throws -> CoreDivergenceLedger {
    let changedFingerprint = "changed-\(UUID().uuidString.lowercased())"
    let records = try #require(initialLedger).records.map { record in
      guard record.id == recordID else { return record }
      return try CoreDivergenceRecord(
        id: record.id, provenance: record.provenance, semanticCitations: record.semanticCitations,
        reproducer: record.reproducer, originalEvidence: record.originalEvidence,
        permanentRegressionCaseID: record.permanentRegressionCaseID,
        classification: record.classification, disposition: record.disposition,
        normalizedDifferenceFingerprint: changedFingerprint,
        latestComparison: try CoreDivergenceComparison(
          evidence: record.latestComparison.evidence, outcome: .difference,
          normalizedDifferenceFingerprint: changedFingerprint))
    }
    return try CoreDivergenceLedger(records: records)
  }

  private func governanceJSON(_ governance: CoreConformanceCaseGovernance) -> [String: Any] {
    ["role": governance.role.rawValue,
     "finiteBounds": ["summary": governance.finiteBounds.summary, "limits": governance.finiteBounds.limits],
     "semanticCitations": governance.semanticCitations,
     "expectedRegressionOutcome": governance.expectedRegressionOutcome.rawValue]
  }

  private func decode<T: Decodable>(_ type: T.Type, at path: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: projectURL(path)))
  }

  private func write(_ object: Any, named file: String, in directory: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: directory.appendingPathComponent(file))
  }
}
