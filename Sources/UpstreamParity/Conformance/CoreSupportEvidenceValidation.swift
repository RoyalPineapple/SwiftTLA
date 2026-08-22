import Foundation

extension CoreSupportGate {
  func caseMatches(
    _ object: [String: Any], _ declared: CoreConformanceCasesManifest.Entry,
    _ expected: CoreConformanceCase
  ) -> Bool {
    object["id"] as? String == declared.id
      && object["moduleSHA256"] as? String == declared.moduleSHA256
      && object["cfgSHA256"] as? String == declared.cfgSHA256
      && object["argumentsSHA256"] as? String == declared.argumentsSHA256
      && object["arguments"] as? [String] == declared.arguments
      && object["workers"] as? Int == declared.workers
      && object["fingerprintPolynomial"] as? Int == declared.fingerprintPolynomial
      && object["deadlock"] as? Bool == declared.deadlock
      && object["operatingSystem"] as? String == expected.operatingSystem
      && object["architecture"] as? String == expected.architecture
      && (object["environment"] as? [String: String]) == expected.environment
      && pinMatches(object["pin"] as? [String: Any])
      && governanceMatches(object["governance"] as? [String: Any], declared.governance)
      && invocationMappingsMatch(object["invocationMappings"], declared: expected.invocationMappings)
      && valueNormalizationsMatch(object["valueNormalizations"], declared: expected.valueNormalizations)
  }

  func toolchainMatches(_ object: [String: Any], _ declared: CoreConformanceCasesManifest.Entry) -> Bool {
    !declared.governance.semanticCitations.isEmpty
      && pinMatches(object["declaredPin"] as? [String: Any])
      && pinMatches(object["referencePin"] as? [String: Any])
      && referenceArtifactsMatch(object["referenceArtifacts"] as? [String: Any])
  }

  func pinMatches(_ pin: [String: Any]?) -> Bool {
    guard let pin else { return false }
    return pin["tag"] as? String == "v1.8.0"
      && pin["commit"] as? String == "0894c3407f4717fec7cc18bde3bf3c857fa47333"
      && pin["jarSHA256"] as? String == TLCReferencePin.lockedJarSHA256
      && pin["javaDistribution"] as? String == TLCReferencePin.fixture.javaDistribution
      && pin["javaVersion"] as? String == TLCReferencePin.fixture.javaVersion
      && pin["bridgeClass"] as? String == TLCReferencePin.fixture.bridgeClass
      && pin["bridgeSourceSHA256"] as? String == TLCReferencePin.lockedBridgeSourceSHA256
      && pin["bridgeBinarySHA256"] as? String == TLCReferencePin.lockedBridgeBinarySHA256
      && TLCReferencePin.lockedJavaArchiveSHA256s.values.contains(pin["javaArchiveSHA256"] as? String ?? "")
  }

  func declaredCaseContract(_ declared: CoreConformanceCasesManifest.Entry) throws -> CoreConformanceCase {
    try CoreConformanceCase(
      id: declared.id, moduleSHA256: declared.moduleSHA256, cfgSHA256: declared.cfgSHA256,
      arguments: declared.arguments, argumentsSHA256: declared.argumentsSHA256,
      workers: declared.workers, fingerprintPolynomial: declared.fingerprintPolynomial,
      deadlock: declared.deadlock, operatingSystem: "macos", architecture: "arm64", environment: [:],
      pin: .fixture, governance: declared.governance,
      invocationMappings: try declared.invocationMappings.map { mapping in
        try CoreConformanceInvocationMapping(
          wrapper: mapping.wrapper, action: mapping.action,
          arguments: mapping.arguments, indices: mapping.indices)
      },
      valueNormalizations: try declared.valueNormalizations.map { normalization in
        try CoreConformanceValueNormalization(
          binding: normalization.binding, functionKeys: normalization.functionKeys)
      })
  }

  func invocationMappingsMatch(
    _ object: Any?, declared: [CoreConformanceInvocationMapping]
  ) -> Bool {
    guard let mappings = object as? [[String: Any]], mappings.count == declared.count else {
      return false
    }
    return zip(mappings, declared).allSatisfy { object, declared in
      Set(object.keys) == ["wrapper", "action", "arguments", "indices"]
        && object["wrapper"] as? String == declared.wrapper
        && object["action"] as? String == declared.action
        && object["arguments"] as? [String] == declared.arguments
        && object["indices"] as? [Int] == declared.indices
    }
  }

  func valueNormalizationsMatch(
    _ object: Any?, declared: [CoreConformanceValueNormalization]
  ) -> Bool {
    guard let normalizations = object as? [[String: Any]], normalizations.count == declared.count else {
      return false
    }
    return zip(normalizations, declared).allSatisfy { object, declared in
      Set(object.keys) == ["binding", "functionKeys"]
        && object["binding"] as? String == declared.binding
        && object["functionKeys"] as? [String: String] == declared.functionKeys
    }
  }

  func governanceMatches(_ object: [String: Any]?, _ governance: CoreConformanceCaseGovernance) -> Bool {
    guard let object,
          object["semanticCitations"] as? [String] == governance.semanticCitations,
          let bounds = object["finiteBounds"] as? [String: Any],
          bounds["summary"] as? String == governance.finiteBounds.summary,
          let limits = bounds["limits"] as? [String: Int]
    else { return false }
    return limits == governance.finiteBounds.limits
  }

  func referenceArtifactsMatch(_ object: [String: Any]?) -> Bool {
    guard let object,
          let jar = object["jar"] as? String, !jar.isEmpty,
          let javaArchive = object["javaArchive"] as? String, !javaArchive.isEmpty,
          let bridgeSource = object["bridgeSource"] as? String, !bridgeSource.isEmpty,
          let bridgeBinary = object["bridgeBinary"] as? String, !bridgeBinary.isEmpty,
          let manifest = object["jarManifest"] as? String,
          manifest.contains("Implementation-Title: TLA+ Tools"),
          manifest.contains("X-Git-Revision: 0894c3407f4717fec7cc18bde3bf3c857fa47333"),
          let runtime = object["runtime"] as? [String: Any],
          runtime["version"] as? String == TLCReferencePin.fixture.javaVersion,
          (runtime["vendor"] as? String)?.contains("Eclipse Adoptium") == true,
          runtime["architecture"] as? String == "arm64",
          let properties = runtime["properties"] as? [String: String],
          properties["java.runtime.version"] == TLCReferencePin.fixture.javaVersion,
          properties["java.vendor"]?.contains("Eclipse Adoptium") == true
    else { return false }
    return true
  }

  func canonicalRunsAreComplete(
    _ swift: CanonicalRun, _ tlc: CanonicalRun, requireExhaustiveCompletion: Bool
  ) -> Bool {
    [swift, tlc].allSatisfy { run in
      run.schema == .exactFiniteTLCGraph
        && !run.graph.initialStateKeys.isEmpty
        && !run.graph.states.isEmpty
        && run.errors.isEmpty
        && (!requireExhaustiveCompletion || run.outcome.isExhaustiveSuccess)
    }
  }

  func canonicalRunsAgree(_ swift: CanonicalRun, _ tlc: CanonicalRun) -> Bool {
    exactFiniteTLCGraph(expected: tlc, actual: swift).isConformant
  }

  func rawArtifactManifestIsComplete(
    _ object: [String: Any], in directory: URL, isViolation: Bool
  ) -> Bool {
    let requiredArtifacts: [String: Bool] = isViolation
      ? [
        "graph-events.jsonl": true,
        "graph-events.trace.jsonl": true,
        "graph-events.replay.jsonl": true,
        "counterexample.json": true,
        "replay.json": true
      ]
      : [
        "graph-events.jsonl": true,
        "graph-events.trace.jsonl": false,
        "graph-events.replay.jsonl": false,
        "counterexample.json": false,
        "replay.json": false
      ]
    guard Set(object.keys) == Set(requiredArtifacts.keys) else { return false }
    for (artifact, expectedPresence) in requiredArtifacts {
      guard object[artifact] as? Bool == expectedPresence else { return false }
      let exists = FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(artifact).path)
      guard exists == expectedPresence else { return false }
    }
    return true
  }

  func processLifecycle(
    _ object: [String: Any], caseID: String, gateRunID: UUID
  ) -> Bool? {
    let phases = ["primary", "trace", "replay"]
    guard Set(object.keys) == ["request", "attempted", "primary", "trace", "replay"],
          let request = object["request"] as? [String: Any],
          correlationObjectMatches(request["correlation"] as? [String: Any], caseID: caseID,
                                   engine: "tlc", gateRunID: gateRunID),
          let attempted = object["attempted"] as? [String],
          Set(attempted).count == attempted.count,
          attempted.allSatisfy({ phases.contains($0) }),
          let primary = object["primary"] as? [String: Any]
    else { return nil }

    let recordedPhases = phases.filter { !(object[$0] is NSNull) }
    guard attempted == recordedPhases else { return nil }

    if exactSuccessRecord(primary) {
      guard attempted == ["primary"], object["trace"] is NSNull, object["replay"] is NSNull else {
        return nil
      }
      return false
    }

    guard violationRecord(primary), attempted == phases,
          let trace = object["trace"] as? [String: Any],
          let replay = object["replay"] as? [String: Any],
          violationRecord(trace), violationRecord(replay),
          trace["status"] as? Int == primary["status"] as? Int,
          replay["status"] as? Int == primary["status"] as? Int
    else { return nil }
    return true
  }

  func graphEventStreamIsComplete(at url: URL, expectedCase: CoreConformanceCase, gateRunID: UUID) throws -> Bool {
    let stream = try TLCGraphEventParser(expectedCase: expectedCase).parse(Data(contentsOf: url))
    return stream.runID == gateRunID && !stream.initialStates.isEmpty
  }

  func graphEventStreamMatchesCanonicalTLCGraph(
    at url: URL, expectedCase: CoreConformanceCase, gateRunID: UUID, tlc: CanonicalRun
  ) throws -> Bool {
    let data = try Data(contentsOf: url)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let stream = try parser.parse(data)
    guard stream.runID == gateRunID, !stream.initialStates.isEmpty else { return false }

    let complete = TLCProcessResult(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    let run = try parser.canonicalRun(stream, result: complete)
    return run.schema == tlc.schema
      && run.graph == tlc.graph
      && run.observableActions == tlc.observableActions
  }

  func rawEvidenceMatchesCanonicalOutcome(
    in directory: URL,
    expectedCase: CoreConformanceCase,
    gateRunID: UUID,
    isViolation: Bool,
    tlc: CanonicalRun
  ) throws -> Bool {
    let primaryURL = directory.appendingPathComponent("graph-events.jsonl")
    let primary = try canonicalGraph(at: primaryURL, expectedCase: expectedCase)
    guard primary.runID == gateRunID,
          canonicalOutcomeMatchesProcess(tlc, isViolation: isViolation),
          graphMatchesCanonicalTLC(primary, tlc: tlc)
    else { return false }

    if !isViolation {
      return auxiliaryArtifactsAreAbsent(in: directory)
    }

    let traceURL = directory.appendingPathComponent("graph-events.trace.jsonl")
    let replayURL = directory.appendingPathComponent("graph-events.replay.jsonl")
    let counterexampleURL = directory.appendingPathComponent("counterexample.json")
    let replayJSONURL = directory.appendingPathComponent("replay.json")
    guard [traceURL, replayURL, counterexampleURL, replayJSONURL].allSatisfy(nonEmptyFile) else {
      return false
    }

    let trace = try canonicalGraph(at: traceURL, expectedCase: expectedCase)
    guard trace.runID == gateRunID,
          primary.run.graph == trace.run.graph,
          primary.run.observableActions == trace.run.observableActions
    else { return false }

    let counterexample = try TLCTraceParser().parseCounterexample(Data(contentsOf: counterexampleURL))
    let replay = try TLCTraceParser().parseCounterexample(Data(contentsOf: replayJSONURL))
    guard counterexample.states == replay.states,
          counterexample.transitions == replay.transitions,
          traceBelongsToGraph(counterexample, graph: primary.run.graph),
          traceBelongsToGraph(replay, graph: trace.run.graph)
    else { return false }

    let replayPhase = try replayPhaseTrace(
      at: replayURL, expectedCase: expectedCase, gateRunID: gateRunID)
    return replayPhase.initialState == replay.states.first
      && replayPhase.transitions == counterexample.transitions.map(\.edge)
  }

  private func auxiliaryArtifactsAreAbsent(in directory: URL) -> Bool {
    ["graph-events.trace.jsonl", "graph-events.replay.jsonl", "counterexample.json", "replay.json"]
      .allSatisfy { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
  }

  private func nonEmptyFile(_ url: URL) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber
    else { return false }
    return size.intValue > 0
  }

  private func canonicalOutcomeMatchesProcess(_ tlc: CanonicalRun, isViolation: Bool) -> Bool {
    guard tlc.errors.isEmpty, tlc.traces.isEmpty else { return false }
    if isViolation {
      if case .invariantViolation(let message) = tlc.outcome { return !message.isEmpty }
      return false
    }
    return tlc.outcome.isExhaustiveSuccess
  }

  private func graphMatchesCanonicalTLC(_ graph: ParsedPhaseGraph, tlc: CanonicalRun) -> Bool {
    graph.run.schema == tlc.schema
      && graph.run.graph == tlc.graph
      && graph.run.observableActions == tlc.observableActions
  }

  private func canonicalGraph(at url: URL, expectedCase: CoreConformanceCase) throws -> ParsedPhaseGraph {
    let data = try Data(contentsOf: url)
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let stream = try parser.parse(data)
    let result = TLCProcessResult(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    return ParsedPhaseGraph(runID: stream.runID, run: try parser.canonicalRun(stream, result: result))
  }

  private func traceBelongsToGraph(
    _ trace: TLCCounterexampleEvidence, graph: CanonicalGraph
  ) -> Bool {
    guard let initialState = trace.states.first,
          graph.initialStateKeys.contains(initialState.key),
          trace.transitions.count == trace.states.count - 1
    else { return false }
    let edges = Set(graph.edgeOccurrences.keys)
    for transition in trace.transitions {
      guard edges.contains(transition.edge) else { return false }
    }
    return true
  }

  private func replayPhaseTrace(
    at url: URL, expectedCase: CoreConformanceCase, gateRunID: UUID
  ) throws -> ReplayPhaseTrace {
    let data = try Data(contentsOf: url)
    guard String(data: data, encoding: .utf8) != nil,
          !data.starts(with: [0xEF, 0xBB, 0xBF]), data.last == 10
    else { throw EvidenceValidationError.invalidCanonicalRecord }
    let lines = data.split(separator: 10, omittingEmptySubsequences: false)
    guard lines.last?.isEmpty == true, lines.count > 2 else {
      throw EvidenceValidationError.invalidCanonicalRecord
    }

    var body = Data()
    var counts: [String: Int] = [:]
    var initialState: CanonicalState?
    var transitions: [CanonicalEdge] = []
    for (index, bytes) in lines.dropLast().enumerated() {
      guard let object = try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
            object["schema"] as? String == "swifttla.tlc.graph-events",
            object["version"] as? Int == 1,
            object["seq"] as? Int == index,
            object["runId"] as? String == gateRunID.uuidString.lowercased(),
            object["caseId"] as? String == expectedCase.id,
            let type = object["type"] as? String,
            let callback = object["callback"] as? String
      else { throw EvidenceValidationError.invalidCanonicalRecord }

      if type == "footer" {
        guard index == lines.count - 2,
              Set(object.keys) == [
                "schema", "version", "type", "callback", "seq", "runId", "caseId", "status",
                "counts", "lastBodySeq", "bodySha256"
              ],
              callback == "writer.close",
              object["status"] as? String == "closed",
              object["lastBodySeq"] as? Int == index - 1,
              object["bodySha256"] as? String == SHA256.hex(body),
              let recordedCounts = object["counts"] as? [String: Int], recordedCounts == counts
        else { throw EvidenceValidationError.invalidCanonicalRecord }
        continue
      }

      body.append(Data(bytes))
      body.append(10)
      counts[type, default: 0] += 1
      switch type {
      case "header":
        guard index == 0,
              Set(object.keys) == ["schema", "version", "type", "callback", "seq", "runId", "caseId", "provenance"],
              callback == "writer.header",
              let provenance = object["provenance"] as? [String: Any],
              replayProvenanceMatches(provenance, expectedCase: expectedCase)
        else { throw EvidenceValidationError.invalidCanonicalRecord }
      case "initial":
        guard Set(object.keys) == ["schema", "version", "type", "callback", "seq", "runId", "caseId", "state"],
              callback == "writeState.initial",
              let state = parsePhaseState(object["state"]), initialState == nil
        else { throw EvidenceValidationError.invalidCanonicalRecord }
        initialState = state
      case "transition":
        guard Set(object.keys) == [
          "schema", "version", "type", "callback", "seq", "runId", "caseId", "source", "target",
          "action", "stateFlags", "visualization", "predicateLocation", "reachable"
        ],
              let source = parsePhaseState(object["source"]),
              let target = parsePhaseState(object["target"]),
              let action = object["action"] as? [String: Any],
              Set(action.keys) == ["name", "location", "named"],
              let actionName = action["name"] as? String, !actionName.isEmpty,
              action["location"] as? String != nil, action["named"] as? Bool == true,
              let flags = object["stateFlags"] as? [String: Any],
              Set(flags.keys) == ["raw", "seen", "notInModel"], flags["raw"] as? Int != nil,
              flags["seen"] as? Bool != nil, flags["notInModel"] as? Bool != nil
        else { throw EvidenceValidationError.invalidCanonicalRecord }
        if callback == "writeState.action" {
          guard object["reachable"] as? String == "reachable",
                object["visualization"] as? String == "none", object["predicateLocation"] is NSNull
          else { throw EvidenceValidationError.invalidCanonicalRecord }
          transitions.append(CanonicalEdge(source: source.key, action: actionName, target: target.key))
        } else {
          guard callback == "writeState.actionPredicate",
                object["reachable"] as? String == "excluded",
                object["visualization"] as? String == "none",
                !(object["predicateLocation"] as? String ?? "").isEmpty
          else { throw EvidenceValidationError.invalidCanonicalRecord }
        }
      default:
        throw EvidenceValidationError.invalidCanonicalRecord
      }
    }
    guard counts["header"] == 1, counts["initial"] == 1, counts["transition", default: 0] > 0,
          counts.count == 3, let initialState, !transitions.isEmpty
    else { throw EvidenceValidationError.invalidCanonicalRecord }
    return ReplayPhaseTrace(initialState: initialState, transitions: transitions)
  }

  private func replayProvenanceMatches(
    _ provenance: [String: Any], expectedCase: CoreConformanceCase
  ) -> Bool {
    let keys: Set<String> = [
      "tlcTag", "tlcCommit", "tlcJarSha256", "javaDistribution", "javaVersion", "javaArchiveSha256",
      "bridgeClass", "bridgeSourceSha256", "bridgeBinarySha256", "moduleSha256", "cfgSha256",
      "arguments", "argumentsSha256", "workers", "fingerprintPolynomial", "deadlock", "os", "architecture",
      "environment"
    ]
    return Set(provenance.keys) == keys
      && provenance["moduleSha256"] as? String == expectedCase.moduleSHA256
      && provenance["cfgSha256"] as? String == expectedCase.cfgSHA256
      && provenance["arguments"] as? [String] == expectedCase.arguments
      && provenance["argumentsSha256"] as? String == expectedCase.argumentsSHA256
      && provenance["workers"] as? Int == expectedCase.workers
      && provenance["fingerprintPolynomial"] as? Int == expectedCase.fingerprintPolynomial
      && provenance["deadlock"] as? Bool == expectedCase.deadlock
      && provenance["os"] as? String == expectedCase.operatingSystem
      && provenance["architecture"] as? String == expectedCase.architecture
      && (provenance["environment"] as? [String: String]) == expectedCase.environment
      && provenance["tlcTag"] as? String == expectedCase.pin.tag
      && provenance["tlcCommit"] as? String == expectedCase.pin.commit
      && provenance["tlcJarSha256"] as? String == expectedCase.pin.jarSHA256
      && provenance["javaDistribution"] as? String == expectedCase.pin.javaDistribution
      && provenance["javaVersion"] as? String == expectedCase.pin.javaVersion
      && provenance["javaArchiveSha256"] as? String == expectedCase.pin.javaArchiveSHA256
      && provenance["bridgeClass"] as? String == expectedCase.pin.bridgeClass
      && provenance["bridgeSourceSha256"] as? String == expectedCase.pin.bridgeSourceSHA256
      && provenance["bridgeBinarySha256"] as? String == expectedCase.pin.bridgeBinarySHA256
  }

  private func parsePhaseState(_ value: Any?) -> CanonicalState? {
    guard let state = value as? [String: Any], Set(state.keys) == ["fingerprint", "level", "bindings"],
          state["fingerprint"] as? String != nil, state["level"] as? Int != nil,
          let bindings = state["bindings"] as? [[String: Any]], !bindings.isEmpty
    else { return nil }
    var values: [String: CanonicalValue] = [:]
    for (index, binding) in bindings.enumerated() {
      guard Set(binding.keys) == ["ordinal", "name", "tla", "tlaSha256"],
            binding["ordinal"] as? Int == index,
            let name = binding["name"] as? String, !name.isEmpty,
            let tla = binding["tla"] as? String,
            binding["tlaSha256"] as? String == SHA256.hex(Data(tla.utf8)),
            values[name] == nil,
            let parsed = try? TLCValueParser.parse(tla)
      else { return nil }
      values[name] = parsed
    }
    return CanonicalState(bindings: values)
  }

  private struct ParsedPhaseGraph {
    let runID: UUID
    let run: CanonicalRun
  }

  private struct ReplayPhaseTrace {
    let initialState: CanonicalState
    let transitions: [CanonicalEdge]
  }

  func comparisonMatchesCanonicalTruth(
    swift: CanonicalRunEvidence,
    swiftRun: CanonicalRun,
    tlc: CanonicalRunEvidence,
    tlcRun: CanonicalRun,
    comparison: [String: Any]
  ) throws -> Bool {
    guard swift.receiptContext == tlc.receiptContext else {
      throw EvidenceValidationError.invalidCanonicalRecord
    }
    let context = swift.receiptContext
    let expected = exactFiniteTLCGraph(
      expected: tlcRun, actual: swiftRun,
      compiledModelIdentity: context.compiledModelIdentity,
      configurationIdentity: context.configurationIdentity,
      symmetrySchemaIdentity: context.symmetrySchemaIdentity,
      maximumStateLimit: context.maximumStateLimit,
      observableNameMappingIdentity: context.observableNameMappingIdentity
    )
    var expectedRecord: [String: Any] = [
      "conformant": expected.isConformant,
      "differences": comparisonDifferencesJSON(expected)
    ]
    if let receipt = expected.expectedReceipt { expectedRecord["expectedReceipt"] = canonicalGraphReceiptJSON(receipt) }
    if let receipt = expected.actualReceipt { expectedRecord["actualReceipt"] = canonicalGraphReceiptJSON(receipt) }
    if let expectedReceipt = expected.expectedReceipt,
       let actualReceipt = expected.actualReceipt,
       let firstDifferentChunk = firstDifferentGraphChunkJSON(
        expected: expectedReceipt, actual: actualReceipt
       ) {
      expectedRecord["firstDifferentGraphChunk"] = firstDifferentChunk
    }
    guard Set(comparison.keys) == Set(expectedRecord.keys).union(["correlation"]),
          jsonValue(comparison["conformant"]) == jsonValue(expectedRecord["conformant"]),
          jsonValue(comparison["differences"]) == jsonValue(expectedRecord["differences"]),
          jsonValue(comparison["expectedReceipt"]) == jsonValue(expectedRecord["expectedReceipt"]),
          jsonValue(comparison["actualReceipt"]) == jsonValue(expectedRecord["actualReceipt"]),
          jsonValue(comparison["firstDifferentGraphChunk"])
            == jsonValue(expectedRecord["firstDifferentGraphChunk"])
    else { throw EvidenceValidationError.invalidCanonicalRecord }

    return !expected.isConformant
  }

  private func jsonValue(_ value: Any?) -> Data? {
    guard let value else { return nil }
    return try? JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys])
  }

  private enum EvidenceValidationError: Error { case invalidCanonicalRecord }

  private func exactSuccessRecord(_ object: [String: Any]) -> Bool {
    Set(object.keys) == ["status", "isViolation", "reportedExhaustiveCompletion"]
      && object["status"] as? Int == 0
      && object["isViolation"] as? Bool == false
      && object["reportedExhaustiveCompletion"] as? Bool == true
  }

  private func violationRecord(_ object: [String: Any]) -> Bool {
    Set(object.keys) == ["status", "isViolation", "reportedExhaustiveCompletion"]
      && object["status"] as? Int == 12
      && object["isViolation"] as? Bool == true
      && object["reportedExhaustiveCompletion"] as? Bool == false
  }

  private func correlationObjectMatches(_ object: [String: Any]?, caseID: String, engine: String, gateRunID: UUID) -> Bool {
    guard let object, Set(object.keys) == ["caseID", "engine", "runID"] else { return false }
    return object["caseID"] as? String == caseID && object["engine"] as? String == engine
      && object["runID"] as? String == gateRunID.uuidString.lowercased()
  }
}
