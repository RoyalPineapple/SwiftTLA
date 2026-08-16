import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct CoreSupportGateTests {
  @Test("retained MultiCarElevator evidence admits only its declared bounded surface")
  func admitsRetainedElevatorEvidence() throws {
    let input = try GateFixture.retainedElevatorInput()
    let report = CoreSupportGateV1().evaluate(input)

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
    let gate = CoreSupportGateV1()

    #expect(reasons(in: gate.evaluate(try fixture.input(excluding: "hour-clock")),
                    for: "hour-clock-reachable-state-space").contains(.missingEvidence))
    #expect(reasons(in: gate.evaluate(try fixture.input(prerequisiteAvailable: false)),
                    for: "hour-clock-reachable-state-space").contains(.missingPrerequisite))

    try fixture.remove("graph-events.jsonl", from: "hour-clock")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.replaceRunID(in: "hour-clock", with: UUID())
    let foreignRunReport = gate.evaluate(try fixture.input())
    #expect(reasons(in: foreignRunReport,
                    for: "hour-clock-reachable-state-space").contains(.foreignRun))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "case.json", key: "moduleSHA256", with: fixture.digest)
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.manifestDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.remove("governance", fromJSONFile: "case.json", in: "hour-clock")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.manifestDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "toolchain.json", key: "javaVersion", with: "0")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.toolchainDigestMismatch))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "swift.json", key: "schema", with: "invented")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "comparison.json", key: "conformant", with: false)
    try fixture.replaceJSONValue(in: "hour-clock", file: "comparison.json", key: "differences", with: [
      ["category": "non-exact", "expected": [], "actual": []]
    ])
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))
  }

  @Test("a changed permanent-regression fingerprint blocks admission")
  func blocksFingerprintDrift() throws {
    let fixture = try GateFixture()
    try fixture.replaceJSONValue(in: "hour-clock-edge-mismatch", file: "comparison.json", key: "differences", with: [
      ["category": "different-difference", "expected": [], "actual": []]
    ])
    let report = CoreSupportGateV1().evaluate(try fixture.input())
    #expect(report.finalExitClass == .blocked)
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space").contains(.unresolvedDivergence))
  }

  @Test("a changed ledger fingerprint is unexplained even when retained evidence is otherwise complete")
  func blocksChangedDeclaredFingerprint() throws {
    let fixture = try GateFixture()
    let report = CoreSupportGateV1().evaluate(try fixture.input(
      ledger: try fixture.ledgerWithChangedFingerprint(recordID: "hour-clock-edge-mismatch")))

    #expect(report.finalExitClass == .blocked)
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space")
      .contains(.unexplainedDivergence))
  }

  @Test("execution and comparison failures have distinct stable admission reasons")
  func classifiesExecutionAndNonExactFailures() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGateV1()

    try fixture.replaceJSONValue(in: "hour-clock", file: "run.json", key: "exitCode", with: 2)
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.executionFailed))

    try fixture.reset("hour-clock")
    try fixture.replaceJSONValue(in: "hour-clock", file: "run.json", key: "exitCode", with: 1)
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.nonExactComparison))
  }

  @Test("canonical graph records must satisfy their graph events and comparisons")
  func blocksFabricatedCanonicalGraph() throws {
    let fixture = try GateFixture()
    try fixture.replaceJSONValue(in: "hour-clock", file: "tlc.json", key: "states", with: [])
    let report = CoreSupportGateV1().evaluate(try fixture.input())
    #expect(reasons(in: report, for: "hour-clock-reachable-state-space").contains(.partialEvidence))
  }

  @Test("TLC process evidence has one complete lifecycle and artifact manifest")
  func blocksInvalidTLCProcessLifecycle() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGateV1()

    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").isEmpty)

    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc-process.json") { object in
      var primary = try #require(object["primary"] as? [String: Any])
      primary["status"] = 999
      object["primary"] = primary
    }
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc-process.json") { object in
      let primary = try #require(object["primary"] as? [String: Any])
      object["attempted"] = ["primary", "replay"]
      object["replay"] = primary
    }
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.remove("replay.json", fromJSONFile: "raw-artifacts.json", in: "hour-clock")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.partialEvidence))

    try fixture.reset("hour-clock")
    try fixture.mutateJSONObject(in: "die-hard-violation", file: "tlc-process.json") { object in
      object["attempted"] = ["primary", "trace"]
      object["replay"] = NSNull()
    }
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    #expect(reasons(in: gate.evaluate(try fixture.input()),
                    for: "hour-clock-reachable-state-space").isEmpty)
  }

  @Test("every retained violation auxiliary is required and must match the primary run")
  func blocksForgedViolationAuxiliaries() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGateV1()
    let requestedSupport = "hour-clock-reachable-state-space"

    for file in [
      "graph-events.jsonl", "graph-events.trace.jsonl", "graph-events.replay.jsonl",
      "counterexample.json", "replay.json"
    ] {
      try fixture.reset("die-hard-violation")
      try fixture.write(Data("forged".utf8), named: file, in: "die-hard-violation")
      let report = gate.evaluate(try fixture.input())
      #expect(reasons(in: report, for: requestedSupport).contains(.unresolvedDivergence))
    }
  }

  @Test("violation traces and replays must preserve one exact action path")
  func blocksForgedTraceAndReplayPaths() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGateV1()
    let requestedSupport = "hour-clock-reachable-state-space"

    try fixture.mutateCounterexampleActionSource(in: "die-hard-violation", file: "counterexample.json")
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.mutateReplayInitialState(in: "die-hard-violation")
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.appendReplayTransition(in: "die-hard-violation")
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))

    try fixture.reset("die-hard-violation")
    try fixture.mutateTraceToNonInitialSuffix(in: "die-hard-violation")
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport)
      .contains(.unresolvedDivergence))
  }

  @Test("process lifecycle and canonical TLC outcome must agree in both directions")
  func blocksProcessOutcomeMismatches() throws {
    let fixture = try GateFixture()
    let gate = CoreSupportGateV1()
    let requestedSupport = "hour-clock-reachable-state-space"

    try fixture.mutateJSONObject(in: "hour-clock", file: "tlc.json") { object in
      object["outcome"] = ["kind": "invariantViolation", "message": "forged violation"]
    }
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport).contains(.partialEvidence))

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
    #expect(reasons(in: gate.evaluate(try fixture.input()), for: requestedSupport).contains(.unresolvedDivergence))
  }

  @Test("resolved divergences retain history but require a current exact reproduction")
  func admitsResolvedDivergenceWithExactCurrentEvidence() throws {
    let fixture = try GateFixture()
    try fixture.resetResolvedRegression("hour-clock-edge-mismatch")
    let ledger = try fixture.resolvedLedger(recordID: "hour-clock-edge-mismatch")
    let report = CoreSupportGateV1().evaluate(try fixture.input(ledger: ledger))
    #expect(report.entries.first { $0.supportID == "hour-clock-reachable-state-space" }?.decision == .admitted)
  }

  @Test("every retained divergence must be linked from the support surface")
  func rejectsUnlinkedDivergence() throws {
    let fixture = try GateFixture()
    let input = try fixture.input()
    let entries = try input.surface.entries.map { entry in
      try CoreSupportSurfaceEntryV1(
        id: entry.id, behavior: entry.behavior, category: entry.category, finiteBounds: entry.finiteBounds,
        relation: entry.relation, mandatoryCaseIDs: entry.mandatoryCaseIDs,
        requestedStatus: entry.requestedStatus,
        linkedDivergenceIDs: entry.id == "hour-clock-altered-transition-control" ? [] : entry.linkedDivergenceIDs,
        reason: entry.reason)
    }
    let incompleteSurface = try CoreSupportSurfaceV1(entries: entries)
    #expect(throws: CoreGovernanceErrorV1.invalidField(record: "support surface", field: "unlinked divergence")) {
      try incompleteSurface.validate(caseIDs: Set(input.manifest.cases.map(\.id)), ledger: input.ledger)
    }
  }

  private func reasons(in report: CoreSupportAdmissionV1, for supportID: String) -> Set<CoreSupportReasonCodeV1> {
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
  private var initialLedger: CoreDivergenceLedgerV1?

  init() throws {
    root = fileManager.temporaryDirectory.appendingPathComponent("CoreSupportGateTests-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for caseID in caseIDs { try reset(caseID) }
    let ledger = try currentLedger()
    initialLedger = try CoreDivergenceLedgerV1(records: ledger.records.filter {
      !$0.id.hasPrefix("multicar-elevator")
    })
  }

  deinit { try? fileManager.removeItem(at: root) }

  func input(
    excluding excludedCaseID: String? = nil,
    prerequisiteAvailable: Bool = true,
    excludingCaseIDs: Set<String> = [],
    ledger overrideLedger: CoreDivergenceLedgerV1? = nil
  ) throws -> CoreSupportGateInputV1 {
    let manifest = try decode(CoreConformanceCasesManifestV1.self, at: "Verification/CoreConformance/cases.json")
    let ledger = try overrideLedger ?? #require(initialLedger)
    let fullSurface = try decode(CoreSupportSurfaceV1.self, at: "Verification/CoreConformance/support-surface.json")
    let surface = try CoreSupportSurfaceV1(entries: fullSurface.entries.filter {
      !$0.id.hasPrefix("multicar-elevator")
    })
    return CoreSupportGateInputV1(
      gateRunID: gateRunID, manifest: manifest, ledger: ledger, surface: surface,
      evidence: caseIDs.filter { $0 != excludedCaseID && !excludingCaseIDs.contains($0) }.map {
        CoreSupportCaseEvidenceV1(
          caseID: $0, directory: root.appendingPathComponent($0),
          relativeDirectory: ".build/core-conformance-evidence/\($0)")
      }, prerequisiteAvailable: prerequisiteAvailable)
  }

  static func retainedElevatorInput() throws -> CoreSupportGateInputV1 {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let verificationRoot = projectRoot.appendingPathComponent("Verification/CoreConformance")
    let manifest = try JSONDecoder().decode(
      CoreConformanceCasesManifestV1.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("cases.json")))
    let allLedger = try JSONDecoder().decode(
      CoreDivergenceLedgerV1.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("divergences.json")))
    let ledger = try CoreDivergenceLedgerV1(records: allLedger.records.filter {
      $0.id == "multicar-elevator-edge-mismatch"
    })
    let allSurface = try JSONDecoder().decode(
      CoreSupportSurfaceV1.self,
      from: Data(contentsOf: verificationRoot.appendingPathComponent("support-surface.json")))
    let surface = try CoreSupportSurfaceV1(entries: allSurface.entries.filter {
      $0.id.hasPrefix("multicar-elevator")
    })
    let gateRunID = try #require(UUID(uuidString: "04b730b6-3a5e-4c9a-a3f9-55e414a696a5"))

    return CoreSupportGateInputV1(
      gateRunID: gateRunID,
      manifest: manifest,
      ledger: ledger,
      surface: surface,
      evidence: [
        CoreSupportCaseEvidenceV1(
          caseID: "multicar-elevator",
          directory: verificationRoot.appendingPathComponent("baselines/multicar-elevator"),
          relativeDirectory: "Verification/CoreConformance/baselines/multicar-elevator"),
        CoreSupportCaseEvidenceV1(
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
    footer["bodySha256"] = SHA256V1.hex(body)
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
    let manifest = try decode(CoreConformanceCasesManifestV1.self, at: "Verification/CoreConformance/cases.json")
    let declared = try #require(manifest.cases.first { $0.id == caseID })
    let correlation = ["caseID": caseID, "engine": "runner", "runID": gateRunID.uuidString.lowercased()]
    let pin: [String: Any] = [
      "tag": TLCReferencePinV1.fixture.tag, "commit": TLCReferencePinV1.fixture.commit,
      "jarSHA256": TLCReferencePinV1.fixture.jarSHA256,
      "javaDistribution": TLCReferencePinV1.fixture.javaDistribution,
      "javaVersion": TLCReferencePinV1.fixture.javaVersion,
      "javaArchiveSHA256": TLCReferencePinV1.fixture.javaArchiveSHA256,
      "bridgeClass": TLCReferencePinV1.fixture.bridgeClass,
      "bridgeSourceSHA256": TLCReferencePinV1.fixture.bridgeSourceSHA256,
      "bridgeBinarySHA256": TLCReferencePinV1.fixture.bridgeBinarySHA256
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
    try rewriteCanonicalRun(named: "swift.json", caseID: caseID, engine: "swift", in: directory)
    try rewriteCanonicalRun(named: "tlc.json", caseID: caseID, engine: "tlc", in: directory)
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
    caseID: String, declared: CoreConformanceCasesManifestV1.Entry, pin: [String: Any], in directory: URL
  ) throws {
    let provenance: [String: Any] = [
      "tlcTag": pin["tag"]!, "tlcCommit": pin["commit"]!, "tlcJarSha256": pin["jarSHA256"]!,
      "javaDistribution": pin["javaDistribution"]!, "javaVersion": pin["javaVersion"]!,
      "javaArchiveSha256": pin["javaArchiveSHA256"]!, "bridgeClass": pin["bridgeClass"]!,
      "bridgeSourceSha256": pin["bridgeSourceSHA256"]!, "bridgeBinarySha256": pin["bridgeBinarySHA256"]!,
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
      footer["bodySha256"] = SHA256V1.hex(body)
      records[records.count - 1] = footer
      let data = try records.map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) + Data("\n".utf8)
      }.reduce(into: Data(), { $0.append($1) })
      try data.write(to: url)
    }
  }

  private func currentLedger() throws -> CoreDivergenceLedgerV1 {
    try decode(CoreDivergenceLedgerV1.self, at: "Verification/CoreConformance/divergences.json")
  }

  func resolvedLedger(recordID: String) throws -> CoreDivergenceLedgerV1 {
    let records = try #require(initialLedger).records.map { record in
      let isResolved = record.id == recordID
      return try CoreDivergenceRecordV1(
        id: record.id, provenance: record.provenance, semanticCitations: record.semanticCitations,
        reproducer: record.reproducer, originalEvidence: record.originalEvidence,
        permanentRegressionCaseID: record.permanentRegressionCaseID,
        classification: record.classification, disposition: isResolved ? .resolved : record.disposition,
        normalizedDifferenceFingerprint: record.normalizedDifferenceFingerprint,
        latestComparison: isResolved
          ? try CoreDivergenceComparisonV1(
            evidence: record.latestComparison.evidence, outcome: .exact, normalizedDifferenceFingerprint: nil)
          : record.latestComparison)
    }
    return try CoreDivergenceLedgerV1(records: records)
  }

  func ledgerWithChangedFingerprint(recordID: String) throws -> CoreDivergenceLedgerV1 {
    let changedFingerprint = "changed-\(UUID().uuidString.lowercased())"
    let records = try #require(initialLedger).records.map { record in
      guard record.id == recordID else { return record }
      return try CoreDivergenceRecordV1(
        id: record.id, provenance: record.provenance, semanticCitations: record.semanticCitations,
        reproducer: record.reproducer, originalEvidence: record.originalEvidence,
        permanentRegressionCaseID: record.permanentRegressionCaseID,
        classification: record.classification, disposition: record.disposition,
        normalizedDifferenceFingerprint: changedFingerprint,
        latestComparison: try CoreDivergenceComparisonV1(
          evidence: record.latestComparison.evidence, outcome: .difference,
          normalizedDifferenceFingerprint: changedFingerprint))
    }
    return try CoreDivergenceLedgerV1(records: records)
  }

  private func governanceJSON(_ governance: CoreConformanceCaseGovernanceV1) -> [String: Any] {
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

  private func projectURL(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
  }
}
