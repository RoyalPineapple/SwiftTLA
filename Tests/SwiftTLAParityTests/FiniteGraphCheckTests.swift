import Foundation
import os
import SwiftTLA
import Testing
@testable import UpstreamParity
struct FiniteGraphCheckTests {
  @Test("Finite enum model values are declared in generated upstream modules")
  func declaresFiniteEnumModelValues() throws {
    let channel = try #require(ChannelModel.validationScenarios().first)
    let asynch = try #require(AsynchInterfaceModel.validationScenarios().first)
    for rendered in [try asynch.render(), try channel.render()] {
      #expect(rendered.tlaBundle.tla.contains("CONSTANTS Data, d1, d2, d3\n"))
      for name in ["d1", "d2", "d3"] {
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT \(name) = \(name)\n"))
      }
    }
  }

  @Test("finite model exports retain complete native graphs and every declared check")
  func nativeExportsRetainCompleteGraphsAndChecks() throws {
    func validate<Scenario: ModelValidationScenario>(_ scenario: Scenario, native: NativeModelRun) throws {
      for (property, expectation) in scenario.expectations {
        let name = try #require(scenario.formalPropertyNames[property])
        let result = try #require(native.checks.properties[name])
        #expect(expectation.accepts(result), "\(scenario.name): \(name)")
        if case .violated(let trace) = result { try trace.validate(in: native.graph.graph) }
      }
    }
    let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
      from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
    for declaration in manifest.cases {
      let scenario = try declaration.resolveScenario()
      let rendered = try scenario?.render() ?? declaration.sourceModel.spec.compile().render()
      let finiteGraphCase = try FiniteGraphCase(id: declaration.id, exploration: declaration.exploration,
        moduleSHA256: declaration.moduleSHA256, cfgSHA256: declaration.cfgSHA256,
        arguments: [], environment: [:], pin: testReferencePin(), renderedActions: rendered.actions)
      let native = try declaration.sourceModel.nativeRun(rendered: rendered, checkingDeadlock: false,
        scenario: scenario, for: finiteGraphCase)
      let renderedNames = Set(finiteGraphCase.renderedActions.map(\.renderedName))
      #expect(Set(native.graph.graph.edges.map(\.action)).isSubset(of: renderedNames))
      #expect(native.graph.isComplete, "\(declaration.id)")
      #expect(!native.graph.graph.initialStateKeys.isEmpty, "\(declaration.id)")
      if let scenario {
        try validate(scenario, native: native)
      } else if declaration.sourceModel == .nQueensFour {
        guard case .violated(let trace) = native.checks.properties["NoSolutions"] else {
          Issue.record("FourQueens must report the upstream NoSolutions counterexample")
          continue
        }
        try trace.validate(in: native.graph.graph)
        #expect(native.checks.properties.filter { $0.key != "NoSolutions" }.values.allSatisfy { $0 == .satisfied })
      } else {
        #expect(native.checks.properties.values.allSatisfy { $0 == .satisfied }, "\(declaration.id)")
      }
      #expect(Set(native.checks.properties.keys) == rendered.checkNames, "\(declaration.id)")
      #expect((native.checks.deadlock != nil) == rendered.checksDeadlock, "\(declaration.id)")
      if rendered.checksDeadlock {
        let enabledStates = Set(native.graph.graph.edges.map(\.source))
        let terminalStates = Set(native.graph.graph.states.keys).subtracting(enabledStates)
        switch try #require(native.checks.deadlock) {
        case .satisfied:
          break
        case .violated(let trace):
          try trace.validate(in: native.graph.graph)
          #expect(terminalStates.contains(try #require(trace.steps.last?.state)))
        case .unavailable:
          Issue.record("Missing deadlock result for \(declaration.id)")
        case .reached, .unreachable:
          Issue.record("Unexpected reachability result for deadlock in \(declaration.id)")
        }
      }
    }
  }

  @Test("finite graph staging consumes declared case identities")
  func stagesDeclaredSourceModels() throws {
    let output = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [projectURL("Tests/Fixtures/FiniteGraph/Command/assert_command.sh").path]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(message)")
  }

  @Test("TLC setup pins the rebuilt binary and its hosted provenance")
  func usesImmutableTLCBuild() throws {
    let data = try Data(contentsOf: projectURL("Verification/FiniteGraph/toolchain.json"))
    let lock = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tlc = try #require(lock["tlc"] as? [String: Any])
    let jar = try #require(tlc["jar"] as? [String: Any])

    #expect(jar["repository"] as? String == "RoyalPineapple/SwiftTLA")
    #expect(try #require(jar["artifactID"] as? Int) > 0)
    #expect(try #require(jar["buildRunID"] as? Int) > 0)
    #expect(try #require(jar["archiveSHA256"] as? String).count == 64)
    #expect(try #require(jar["buildRevision"] as? String).count == 40)
    #expect(jar["assetID"] == nil)
    #expect(jar["url"] == nil)
  }

  @Test("finite graph manifests reject unknown exploration fields")
  func rejectsUnknownExplorationFields() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FiniteGraphManifest.self, from: manifest(exploration: """
        {
          "maximumStateLimit": 10,
          "symmetryReduction": "disabled",
          "maximumStateLmit": 10
        }
        """))
    }
  }

  @Test("finite graph manifests reject unknown source models")
  func rejectsUnknownSourceModels() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        FiniteGraphManifest.self,
        from: manifest(sourceModel: "unknown", exploration: """
          {
            "maximumStateLimit": 10,
            "symmetryReduction": "disabled"
          }
          """)
      )
    }
  }

  @Test("declared finite graph cases cover registered source models")
  func resolvesDeclaredSourceModels() throws {
    let data = try Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json"))
    let manifest = try JSONDecoder().decode(FiniteGraphManifest.self, from: data)
    let sources = manifest.cases.map(\.sourceModel)
    #expect(Set(sources) == Set(FiniteGraphSourceModel.allCases))
    for source in sources {
      _ = source.spec
    }
  }

  @Test("finite graph manifests reject unknown dependency fields")
  func rejectsUnknownDependencyFields() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FiniteGraphManifest.self, from: manifest(
        dependencies: """
          [{
            "importingModule": "Fixture",
            "importedModule": "Imported",
            "inferred": true
          }]
          """,
        exploration: """
          {
            "maximumStateLimit": 10,
            "symmetryReduction": "disabled"
          }
          """
      ))
    }
  }

  @Test("finite graph manifests require unreduced Swift exploration")
  func rejectsSymmetryReduction() {
    #expect(throws: EvidenceFormatError.self) {
      try JSONDecoder().decode(FiniteGraphManifest.self, from: manifest(exploration: """
        {
          "maximumStateLimit": 10,
          "symmetryReduction": "enabled",
          "maximumPermutationCount": 2
        }
        """))
    }
  }

  @Test("finite graph cases require a positive process timeout")
  func rejectsInvalidTimeouts() {
    for timeout in [0, -1] {
      #expect(throws: EvidenceFormatError.invalidField(record: "fixture", field: "timeoutSeconds")) {
        try JSONDecoder().decode(FiniteGraphManifest.self, from: manifest(timeoutSeconds: timeout,
          exploration: """
            {"maximumStateLimit": 10, "symmetryReduction": "disabled"}
            """))
      }
    }
  }

  private func manifest(
    sourceModel: String = "hour-clock",
    dependencies: String = "[]",
    timeoutSeconds: Int = 60,
    exploration: String
  ) -> Data {
    Data("""
      {
        "schema": "FiniteGraphCases",
        "cases": [{
          "id": "fixture",
          "sourceModel": "\(sourceModel)",
          "timeoutSeconds": \(timeoutSeconds),
          "module": "Fixture.tla",
          "configuration": "Fixture.cfg",
          "imports": [],
          "dependencies": \(dependencies),
          "exploration": \(exploration),
          "moduleSHA256": "\(String(repeating: "a", count: 64))",
          "cfgSHA256": "\(String(repeating: "b", count: 64))"
        }]
      }
      """.utf8)
  }

  @Test("finite graph check retains complete graphs and reports same-count edge differences")
  func retainsIndependentRunsAtomically() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let executor = FixtureTLCExecutor()
    let check = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: executor))
    let output = root.appendingPathComponent("evidence")
    let checkOutput = check.run(
      nativeRun: { try fixtureRun() },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )
    #expect(checkOutput.exitCode == .semanticDifference)
    #expect(checkOutput.comparison?.differences.contains { if case .edges = $0 { true } else { false } } == true)
    let swiftCompletion = try graphCompletion(
      at: output.appendingPathComponent("swift-graph.jsonl"))
    let tlcCompletion = try graphCompletion(
      at: output.appendingPathComponent("tlc-graph.jsonl"))
    #expect(swiftCompletion["isComplete"] as? Bool == true)
    #expect(tlcCompletion["isComplete"] as? Bool == true)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("comparison.json").path))
    let process = try json(at: output.appendingPathComponent("tlc-process.json"))
    #expect(process["caseID"] as? String == request.finiteGraphCase.id)
    #expect(process["runID"] as? String == request.runID.uuidString.lowercased())
    let inputs = try #require(process["inputs"] as? [[String: String]])
    #expect(Set(inputs.compactMap { $0["file"] }) == ["Fixture.tla", "Fixture.cfg"])
    #expect(Set(inputs.compactMap { $0["sha256"] }) ==
      [request.finiteGraphCase.moduleSHA256, SHA256.hex(Data(try fixtureConfiguration(request)
        .bundle(from: request.bundle, native: fixtureRun(), checking: [], checkDeadlock: false).cfg.utf8))])
    #expect(process["toolPin"] != nil)
    let primary = try #require(process["invocation"] as? [String: Any])
    let arguments = try #require(primary["arguments"] as? [String])
    #expect(arguments.contains("-workers"))
    #expect(arguments.contains(where: { $0.hasSuffix("/Fixture.cfg") }))
    #expect(arguments.contains(where: { $0.hasSuffix("/Fixture.tla") }))
    #expect(!fileManager.fileExists(atPath: output.appendingPathComponent("case.json").path))
    #expect(try json(at: output.appendingPathComponent("comparison.json"))["result"] as? String == "difference")
    let comparison = try #require(checkOutput.comparison)
    let report = try #require(comparison.failureReports.first {
      $0.whatFailed == "The labeled transition relations differ."
    })
    #expect(report.expected.contains("TLC permits"))
    #expect(report.actual.contains("SwiftTLA does not permit"))
    #expect(report.nextSafeAction.contains("guard"))
  }

  @Test("finite graph check publishes partial evidence and a diagnostic after TLC capture failure")
  func retainsFailureEvidenceAtomically() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: FailingTLCExecutor()))
    let output = root.appendingPathComponent("failed-evidence")
    let checkOutput = check.run(
      nativeRun: { try fixtureRun() },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )
    #expect(checkOutput.exitCode == .failure)
    #expect(checkOutput.evidenceDirectory == output)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("swift-graph.jsonl").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("diagnostic.json").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("tlc-process.json").path))
    #expect(
      fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.stdout.log").path))
    #expect(
      fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.stderr.log").path))
    let diagnostic = try json(at: output.appendingPathComponent("diagnostic.json"))
    #expect(diagnostic["code"] as? String == "tlc-execution-failed")
    #expect(diagnostic["phase"] as? String == "tlc-execution")
    let report = try #require(diagnostic["report"] as? [String: Any])
    #expect(report["whatFailed"] as? String == "TLC did not finish before the configured time limit.")
    #expect((report["expected"] as? String)?.contains("complete") == true)
    #expect((report["actual"] as? String)?.contains("terminated") == true)
    #expect((report["nextSafeAction"] as? String)?.contains("retained stdout") == true)
    #expect((report["toolOutput"] as? [[String: Any]])?.count == 2)
    #expect(
      (try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))).contains(
        "partial stdout"))
    #expect(
      !(try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))).contains(
        "secret"))
  }

  @Test("finite graph check rejects a complete graph stream from another TLC run")
  func rejectsWrongTLCStreamRunBinding() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let otherRun = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000006"))
    let check = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: FixtureTLCExecutor(
          runID: otherRun)))
    let output = root.appendingPathComponent("wrong-tlc-run")
    let checkOutput = check.run(
      nativeRun: { try fixtureRun() },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )
    #expect(checkOutput.exitCode == .failure)
    #expect(checkOutput.evidenceDirectory == output)
    let diagnostic = try json(at: output.appendingPathComponent("diagnostic.json"))
    #expect(diagnostic["phase"] as? String == "tlc-parsing")
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("graph-events.jsonl").path))
  }
  @Test("finite graph check replaces stale raw output and retains one complete TLC graph")
  func replacesStaleRawOutputAndRetainsCompleteGraph() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    try Data("stale graph stream".utf8).write(to: request.graphEvents)
    let output = root.appendingPathComponent("exact-evidence")
    let checkOutput = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: FixtureTLCExecutor())
    ).run(
      nativeRun: { try fixtureRun(action: "Next") },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )
    #expect(checkOutput.exitCode == .exact)
    #expect(try Data(contentsOf: output.appendingPathComponent("graph-events.jsonl")) == graphStream(for: request.finiteGraphCase, runID: request.runID))
    let tlcGraph = output.appendingPathComponent("tlc-graph.jsonl")
    #expect(try graphCompletion(at: tlcGraph)["isComplete"] as? Bool == true)
    let graphRecords = try graphRecords(at: tlcGraph)
    #expect(graphRecords.filter { $0["type"] as? String == "state" }.count == 2)
    #expect(graphRecords.filter { $0["type"] as? String == "edge" }.count == 1)
  }

  @Test("matching evidence retains both complete graphs and one exact comparison")
  func retainsExactComparison() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("matching-evidence")
    let checkOutput = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(
        executor: FixtureTLCExecutor()
    )).run(
      nativeRun: { try fixtureRun(action: "Next") },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )

    #expect(checkOutput.exitCode == .exact)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("comparison.json").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("tlc-process.json").path))
    let swiftCompletion = try graphCompletion(
      at: output.appendingPathComponent("swift-graph.jsonl"))
    let tlcCompletion = try graphCompletion(
      at: output.appendingPathComponent("tlc-graph.jsonl"))
    #expect(swiftCompletion["isComplete"] as? Bool == true)
    #expect(tlcCompletion["isComplete"] as? Bool == true)
    #expect(try json(at: output.appendingPathComponent("comparison.json"))["result"] as? String == "exact")
  }
}

extension FiniteGraphCheckTests {
  private func fixtureConfiguration(_ request: TLCProcessRequest) -> TLCReferenceConfiguration {
    // These fixtures emit one declaration per line; production uses TLC's parser.
    let lines = request.bundle.cfg.split(separator: "\n").map(String.init)
    return TLCReferenceConfiguration(
      declarations: lines.filter {
        !$0.hasPrefix("INVARIANT ") && !$0.hasPrefix("PROPERTY ") && !$0.hasPrefix("CHECK_DEADLOCK ")
      }.joined(separator: "\n") + "\n",
      invariants: lines.filter { $0.hasPrefix("INVARIANT ") }.map { String($0.dropFirst("INVARIANT ".count)) },
      properties: lines.filter { $0.hasPrefix("PROPERTY ") }.map { String($0.dropFirst("PROPERTY ".count)) },
      checksDeadlock: !lines.contains("CHECK_DEADLOCK FALSE"))
  }
  @Test("failed TLC execution retains partial output and the graph stream", arguments: [true, false])
  func retainsFailedExecution(timedOut: Bool) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("failed-run")
    let checkOutput = FiniteGraphCheck(
      tlcProcess: TLCProcessAdapter(executor: InterruptedTLCExecutor(
        stream: try graphStream(for: request.finiteGraphCase, runID: request.runID), timedOut: timedOut))
    ).run(nativeRun: { try fixtureRun() }, tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: output)
    #expect(checkOutput.exitCode == .failure)
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("graph-events.jsonl").path))
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("logs/tlc.failure.log").path))
    let invocation = try #require(json(at: output.appendingPathComponent("tlc-process.json"))["invocation"] as? [String: Any])
    #expect(invocation["executionError"] as? String != nil)
    #expect(invocation["exitStatus"] == nil)
    if timedOut {
      let stdout = try String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"))
      #expect(stdout.contains("partial stdout"))
      #expect(!stdout.contains("private-secret"))
    }
  }
  @Test("every declared check runs independently, including matching violations", arguments: [false, true])
  func comparesEveryCheck(unavailable: Bool) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root, checks: ["Failed", "Unknown"], checkDeadlock: true)
    let output = root.appendingPathComponent("checks")
    let first = CanonicalState(bindings: ["x": .integer(1)]).key
    let second = CanonicalState(bindings: ["x": .integer(2)]).key
    let failure = GraphTrace(id: "invariant", steps: [.init(state: first, action: nil)])
    let deadlock = GraphTrace(id: "deadlock", steps: [.init(state: first, action: nil), .init(state: second, action: "Next")])
    let result = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: PerCheckExecutor()))
      .run(nativeRun: { try fixtureRun(action: "Next",
        checks: ["Failed": .violated(failure), "Unknown": unavailable ? .unavailable : .satisfied],
        deadlock: .violated(deadlock)) }, tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: output)
    #expect(result.comparison?.matches == true)
    #expect(result.exitCode == (unavailable ? .failure : .exact))
    let comparison = try json(at: output.appendingPathComponent("comparison.json"))
    let checks = try #require(comparison["checks"] as? [String: String])
    #expect(checks == ["properties/Failed": "exact", "properties/Unknown": unavailable ? "unavailable" : "exact", "deadlock": "exact", "reference/deadlock": "exact", "reference/properties/Failed": "exact", "reference/properties/Unknown": unavailable ? "unavailable" : "exact"])
    #expect(comparison["result"] as? String == (unavailable ? "unavailable" : "exact"))
    for path in checks.keys {
      #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(path).appendingPathComponent("property-comparison.json").path))
      #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent(path).appendingPathComponent("swift-graph.jsonl").path))
    }
  }

  @Test("an original-reference property disagreement fails matching generated results")
  func rejectsOriginalPropertyDisagreement() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root, checks: ["Unknown"])
    let output = root.appendingPathComponent("checks")
    let result = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(
      executor: PerCheckExecutor(referenceDisagrees: true))).run(
        nativeRun: { try fixtureRun(action: "Next", checks: ["Unknown": .satisfied]) },
        tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: output)
    #expect(result.exitCode == .semanticDifference)
    let checks = try json(at: output.appendingPathComponent("comparison.json"))["checks"] as? [String: String]
    #expect(checks == ["properties/Unknown": "exact", "reference/properties/Unknown": "propertyOutcomeDifference"])
    let retained = try json(at: output.appendingPathComponent("reference/properties/Unknown/property-comparison.json"))
    #expect((retained["tlcResult"] as? [String: Any])?["status"] as? String == "violated")
  }

  @Test("a batch timeout fails without inventing individual property verdicts")
  func rejectsTimedOutBatch() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root, checks: ["Failed", "Unknown"])
    let output = root.appendingPathComponent("checks")
    let result = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: PerCheckExecutor(failFirst: true)))
      .run(nativeRun: { try fixtureRun(action: "Next", checks: ["Failed": .satisfied, "Unknown": .satisfied]) },
        tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: output)
    #expect(result.exitCode == .failure)
    #expect(result.diagnostic != nil)
    #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("comparison.json").path))
    #expect(FileManager.default.fileExists(atPath:
      output.appendingPathComponent("checked-graph/logs/tlc.failure.log").path))
  }

  @Test("a property verdict difference fails matching complete graphs")
  func rejectsDifferentPropertyVerdicts() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root, checks: ["Failed"])
    let result = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: PerCheckExecutor()))
      .run(nativeRun: { try fixtureRun(action: "Next", checks: ["Failed": .satisfied]) },
        tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: root.appendingPathComponent("checks"))
    #expect(result.comparison?.matches == true)
    #expect(result.exitCode == .semanticDifference)
  }

  @Test("missing native results cannot silently drop declared checks")
  func rejectsMissingCheckResults() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root, checks: ["Failed"])
    let native = try fixtureRun(action: "Next", checks: ["Failed": .satisfied])
    let result = FiniteGraphCheck(tlcProcess: TLCProcessAdapter(executor: PerCheckExecutor()))
      .run(nativeRun: { try NativeModelRun(rendered: native.rendered, graph: native.graph,
        checks: .init(properties: [:], deadlock: nil)) }, tlcRequest: request, referenceConfiguration: fixtureConfiguration(request), outputDirectory: root.appendingPathComponent("checks"))
    #expect(result.exitCode == .failure)
    #expect(result.diagnostic != nil)
  }

  @Test("reference graph selection removes failing checks while preserving the model")
  func selectsReferenceChecksExplicitly() throws {
    let native = try fixtureRun(checks: ["Failed": .satisfied], deadlock: .satisfied)
    let declarations = "CONSTANT Limit = 4\nSPECIFICATION OriginalSpec\nCONSTRAINT Bounded\n"
    let original = TLAModuleBundle.external(root: .init(name: "Original", tla: "original source",
      cfg: declarations + "INVARIANT Failed\nCHECK_DEADLOCK TRUE\n"))
    let configuration = TLCReferenceConfiguration(declarations: declarations,
      invariants: ["Failed"], properties: [], checksDeadlock: true)
    try configuration.validateCoverage(native)
    let graph = try configuration.bundle(from: original, native: native, checking: [], checkDeadlock: false)
    #expect(graph.cfg.hasPrefix(declarations))
    #expect(!graph.cfg.contains("INVARIANT"))
    #expect(!graph.cfg.contains("SYMMETRY"))
    #expect(graph.cfg.contains("CHECK_DEADLOCK FALSE"))
    #expect(graph.tla == original.tla)
    #expect(graph.provenance == original.provenance)
    let property = try configuration.bundle(from: original, native: native, checking: ["Failed"], checkDeadlock: false)
    #expect(property.cfg.contains("INVARIANT Failed"))
    #expect(property.cfg.contains("CHECK_DEADLOCK FALSE"))
  }

  @Test("reference check selection honors upstream properties and deadlock configuration", arguments: [false, true])
  func honorsReferenceCheckSelection(deadlock: Bool) throws {
    let native = try fixtureRun(checks: ["Selected": .satisfied, "Additional": .satisfied], deadlock: .satisfied)
    let original = native.rendered.tlaBundle
    let configuration = TLCReferenceConfiguration(declarations: "SPECIFICATION Spec\n",
      invariants: ["Selected"], properties: [], checksDeadlock: deadlock)
    let source = TLCPropertySource.reference(original, configuration)
    let checks = try source.checks(for: native)
    #expect(checks.properties == ["Selected": .satisfied])
    #expect(checks.deadlock == (deadlock ? .satisfied : nil))
    let checked = try source.bundle(for: native, checkingSatisfied: true)
    #expect(checked.cfg.contains("INVARIANT Selected"))
    #expect(!checked.cfg.contains("INVARIANT Additional"))
    #expect(checked.cfg.contains("CHECK_DEADLOCK \(deadlock ? "TRUE" : "FALSE")"))
    let graph = try source.bundle(for: native, checkingSatisfied: false)
    #expect(!graph.cfg.contains("INVARIANT"))
    #expect(graph.cfg.contains("CHECK_DEADLOCK FALSE"))
    #expect(graph.tla == original.tla)
    #expect(try TLCPropertySource.generated.checks(for: native) == native.checks)
  }

  @Test("reference checks cannot disappear when native coverage is missing", arguments: [false, true])
  func rejectsUncoveredReferenceChecks(deadlock: Bool) throws {
    let native = try fixtureRun()
    let configuration = TLCReferenceConfiguration(declarations: "SPECIFICATION Spec\n",
      invariants: deadlock ? [] : ["Missing"], properties: [], checksDeadlock: deadlock)
    let problems = deadlock ? ["Missing native deadlock result"]
      : ["Missing native result: Missing", "No matching native invariant: Missing"]
    #expect(throws: TLCPropertyCheckError.uncoveredReferenceChecks(problems)) {
      try TLCPropertySource.reference(native.rendered.tlaBundle, configuration).checks(for: native)
    }
  }

  @Test("finite graph check rejects an existing output without touching it")
  func rejectsExistingOutput() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let request = try temporaryRequest(in: root)
    let output = root.appendingPathComponent("existing-evidence")
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: output.appendingPathComponent("existing.txt"))
    let checkOutput = FiniteGraphCheck().run(
      nativeRun: { try fixtureRun() },
      tlcRequest: request, referenceConfiguration: fixtureConfiguration(request),
      outputDirectory: output
    )
    #expect(checkOutput.exitCode == .failure)
    #expect(checkOutput.evidenceDirectory == nil)
    #expect(checkOutput.diagnostic?.code == "output-exists")
    #expect(fileManager.fileExists(atPath: output.appendingPathComponent("existing.txt").path))
  }
}

extension FiniteGraphCheckTests {
  private func fixtureRun(action: String = "SwiftNext", checks: [String: PropertyResult] = [:], deadlock: PropertyResult? = nil) throws -> NativeModelRun {
    let first = CanonicalState(bindings: ["x": .integer(1)])
    let second = CanonicalState(bindings: ["x": .integer(2)])
    let graph = try GraphRun(
      isComplete: true,
      graph: CanonicalGraph(initialStates: [first], states: [first, second],
        edges: [CanonicalEdge(source: first.key, action: action, target: second.key)]),
      observableActions: [action], outcome: .noViolation)
    return try NativeModelRun(rendered: fixtureRendered(checks: Set(checks.keys), checkDeadlock: deadlock != nil), graph: graph,
      checks: .init(properties: checks, deadlock: deadlock))
  }
  private func temporaryRequest(in root: URL, checks: Set<String> = [], checkDeadlock: Bool = false) throws -> TLCProcessRequest {
    let module = root.appendingPathComponent("Fixture.tla")
    let configuration = root.appendingPathComponent("Fixture.cfg")
    let bundle = try fixtureRendered(checks: checks, checkDeadlock: checkDeadlock).tlaBundle
    let originalTLA = bundle.tla + "\n\\* Original reference fixture\n"
    try Data(originalTLA.utf8).write(to: module)
    try Data(bundle.cfg.utf8).write(to: configuration)
    let finiteGraphCase = try FiniteGraphCase(
      id: "fixture",
      exploration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
      moduleSHA256: SHA256.hex(Data(originalTLA.utf8)),
      cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: ["-workers", "1"],
      environment: [:],
      pin: try testReferencePin()
    )
    return TLCProcessRequest(
      javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
      jar: root.appendingPathComponent("tla2tools.jar"),
      bridgeJar: root.appendingPathComponent("bridge"),
      bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
      graphEvents: root.appendingPathComponent("events.jsonl"),
      traceOutput: root.appendingPathComponent("trace.json"),
      workingDirectory: root,
      finiteGraphCase: finiteGraphCase,
      runID: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000005")),
      invocation: .finiteGraph
    )
  }
}
private func fixtureRendered(checks: Set<String>, checkDeadlock: Bool) throws -> RenderedSpecification {
  let x = Var<Int>("x")
  var specification = TLASpec("Fixture") {
    Variable(x, 1)
    SwiftTLA.Action("Next") { x == 1 && x.becomes(2) }
    for name in checks.sorted() {
      Invariant(name) { name == "Failed" ? x > 1 : x > 0 }
    }
  }
  specification.checkDeadlock = checkDeadlock
  return try specification.compile().render()
}

private struct PerCheckExecutor: TLCProcessExecuting {
  var failFirst = false
  var referenceDisagrees = false

  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    if request.invocation == .finiteGraph {
      try graphStream(for: request.finiteGraphCase, runID: request.runID).write(to: request.graphEvents)
    }
    var status: Int32 = 0
    if request.bundle.cfg.contains("INVARIANT") || request.bundle.cfg.contains("CHECK_DEADLOCK TRUE") {
      let first: [Any] = [1, ["x": 1]]
      let second: [Any] = [2, ["x": 2]]
      var states: [Any] = []
      var actions: [Any] = []
      if referenceDisagrees && request.bundle.cfg.contains("INVARIANT Unknown") && request.bundle.tla.contains("Original reference fixture") {
        status = 12
        states = [first]
      } else if request.bundle.cfg.contains("INVARIANT Failed") {
        if failFirst { throw TLCProcessError.timedOut(partialStdout: "timed out", partialStderr: "") }
        status = 12
        states = [first]
      } else if request.bundle.cfg.contains("CHECK_DEADLOCK TRUE") {
        status = 11
        states = [first, second]
        actions = [[first, ["name": "Next"], second]]
      }
      if status != 0 {
        let trace: [String: Any] = ["vars": ["x"], "counterexample": ["state": states, "action": actions]]
        try JSONSerialization.data(withJSONObject: trace).write(to: request.traceOutput)
      }
    }
    return TLCProcessResult(status: status, stdout: "fixture result", stderr: "")
  }
}

private struct FixtureTLCExecutor: TLCProcessExecuting {
  let runID: UUID?
  let status: Int32
  let stdout: String
  init(
    runID: UUID? = nil, status: Int32 = 0,
    stdout: String = "Model checking completed. No error has been found."
  ) {
    self.runID = runID
    self.status = status
    self.stdout = stdout
  }
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try graphStream(for: request.finiteGraphCase, runID: runID ?? request.runID).write(to: request.graphEvents)
    return TLCProcessResult(
      status: status,
      stdout: stdout,
      stderr: ""
    )
  }
}
private struct FailingTLCExecutor: TLCProcessExecuting {
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    throw TLCProcessError.timedOut(
      partialStdout: "partial stdout TOKEN=secret", partialStderr: "partial stderr")
  }
}
private struct InterruptedTLCExecutor: TLCProcessExecuting {
  let stream: Data
  let timedOut: Bool

  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    try stream.write(to: request.graphEvents)
    if timedOut {
      throw TLCProcessError.timedOut(partialStdout: "partial stdout TOKEN=private-secret", partialStderr: "partial stderr")
    }
    throw TLCProcessError.failedToStart("launch validation failed")
  }
}
private func json(at url: URL) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func graphRecords(at url: URL) throws -> [[String: Any]] {
  try Data(contentsOf: url).split(separator: 0x0a).map {
    try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
  }
}

private func graphCompletion(at url: URL) throws -> [String: Any] {
  try #require(graphRecords(at: url).last)
}

private func graphStream(for finiteGraphCase: FiniteGraphCase, runID: UUID) throws -> Data {
  let first = state(fingerprint: "1", value: "1")
  let second = state(fingerprint: "2", value: "2")
  let common: [String: Any] = [
    "schema": "swifttla.tlc.graph-events",
    "version": 3,
    "runId": runID.uuidString.lowercased(),
    "caseId": finiteGraphCase.id
  ]
  let records: [[String: Any]] = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0]) { $1 },
    common.merging(["type": "initial", "callback": "writeState.initial", "seq": 1, "state": first]) { $1 },
    common.merging([
      "type": "transition", "callback": "writeState.action", "seq": 2,
      "source": first, "target": second,
      "action": ["name": "Next", "location": "Fixture:1", "named": true],
      "resolvedActions": [["name": "Next", "location": "Fixture:1", "named": true]],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ]) { $1 }
  ]
  let body = try records.reduce(into: Data()) { data, record in
    data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    data.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 3, "status": "closed",
    "counts": ["header": 1, "initial": 1, "transition": 1], "lastBodySeq": 2,
    "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}
private func state(fingerprint: String, value: String) -> [String: Any] {
  [
    "fingerprint": fingerprint,
    "level": 1,
    "bindings": [
      ["ordinal": 0, "name": "x", "tla": value]
    ]
  ]
}
