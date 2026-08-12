import Foundation

extension CoreSupportGateV1 {
  func caseMatches(
    _ object: [String: Any], _ declared: CoreConformanceCasesManifestV1.Entry,
    _ expected: CoreConformanceCaseV1
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
  }

  func argumentsMatch(_ object: [String: Any], _ declared: CoreConformanceCasesManifestV1.Entry) -> Bool {
    object["arguments"] as? [String] == declared.arguments
  }

  func toolchainMatches(_ object: [String: Any], _ declared: CoreConformanceCasesManifestV1.Entry) -> Bool {
    !declared.governance.semanticCitations.isEmpty
      && pinMatches(object["declaredPin"] as? [String: Any])
      && pinMatches(object["referencePin"] as? [String: Any])
      && referenceArtifactsMatch(object["referenceArtifacts"] as? [String: Any])
  }

  func pinMatches(_ pin: [String: Any]?) -> Bool {
    guard let pin else { return false }
    return pin["tag"] as? String == "v1.8.0"
      && pin["commit"] as? String == "30cc3601321c3fc02e044d0ecb5c58d8921e18df"
      && pin["jarSHA256"] as? String == TLCReferencePinV1.lockedJarSHA256
      && pin["javaDistribution"] as? String == TLCReferencePinV1.fixture.javaDistribution
      && pin["javaVersion"] as? String == TLCReferencePinV1.fixture.javaVersion
      && pin["bridgeClass"] as? String == TLCReferencePinV1.fixture.bridgeClass
      && pin["bridgeSourceSHA256"] as? String == TLCReferencePinV1.lockedBridgeSourceSHA256
      && pin["bridgeBinarySHA256"] as? String == TLCReferencePinV1.lockedBridgeBinarySHA256
      && TLCReferencePinV1.lockedJavaArchiveSHA256s.values.contains(pin["javaArchiveSHA256"] as? String ?? "")
  }

  func declaredCaseContract(_ declared: CoreConformanceCasesManifestV1.Entry) throws -> CoreConformanceCaseV1 {
    try CoreConformanceCaseV1(
      id: declared.id, moduleSHA256: declared.moduleSHA256, cfgSHA256: declared.cfgSHA256,
      arguments: declared.arguments, argumentsSHA256: declared.argumentsSHA256,
      workers: declared.workers, fingerprintPolynomial: declared.fingerprintPolynomial,
      deadlock: declared.deadlock, operatingSystem: "macos", architecture: "arm64", environment: [:],
      pin: .fixture, governance: declared.governance)
  }

  func governanceMatches(_ object: [String: Any]?, _ governance: CoreConformanceCaseGovernanceV1) -> Bool {
    guard let object, object["role"] as? String == governance.role.rawValue,
          object["semanticCitations"] as? [String] == governance.semanticCitations,
          object["expectedRegressionOutcome"] as? String == governance.expectedRegressionOutcome.rawValue,
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
          manifest.contains("X-Git-Tag: "), manifest.contains("v1.8.0"),
          manifest.contains("X-Git-Revision: 30cc3601321c3fc02e044d0ecb5c58d8921e18df"),
          let runtime = object["runtime"] as? [String: Any],
          runtime["version"] as? String == TLCReferencePinV1.fixture.javaVersion,
          (runtime["vendor"] as? String)?.contains("Eclipse Adoptium") == true,
          runtime["architecture"] as? String == "arm64",
          let properties = runtime["properties"] as? [String: String],
          properties["java.runtime.version"] == TLCReferencePinV1.fixture.javaVersion,
          properties["java.vendor"]?.contains("Eclipse Adoptium") == true
    else { return false }
    return true
  }

  func canonicalGraphsAreComplete(
    _ swift: [String: Any], _ tlc: [String: Any], requireExhaustiveCompletion: Bool
  ) -> Bool {
    [swift, tlc].allSatisfy { graph in
      let outcome = graph["outcome"] as? [String: Any]
      let outcomeIsComplete = requireExhaustiveCompletion
        ? outcome?["kind"] as? String == "exhaustiveSuccess"
        : outcome?["kind"] as? String != nil
      return graph["schema"] as? String == CanonicalSchemaV1.exactFiniteTLCGraphV1.rawValue
        && graph["initialStates"] as? [String] != nil
        && graph["states"] as? [String] != nil
        && graph["edges"] as? [[String: Any]] != nil
        && graph["observations"] as? [[String: Any]] != nil
        && graph["observableActions"] as? [String] != nil
        && (graph["errors"] as? [[String: Any]])?.isEmpty == true
        && (graph["traces"] as? [[String: Any]]) != nil
        && outcomeIsComplete
    }
  }

  func canonicalGraphsAgree(_ swift: [String: Any], _ tlc: [String: Any]) -> Bool {
    let fields = ["schema", "initialStates", "states", "edges", "observations", "observableActions", "outcome", "errors", "traces"]
    return fields.allSatisfy { field in canonicalValue(swift[field]) == canonicalValue(tlc[field]) }
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
    guard Set(object.keys) == ["correlation", "attempted", "primary", "trace", "replay"],
          correlationObjectMatches(object["correlation"] as? [String: Any], caseID: caseID,
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

  func graphEventStreamIsComplete(at url: URL, expectedCase: CoreConformanceCaseV1, gateRunID: UUID) throws -> Bool {
    let stream = try TLCGraphEventParserV1(expectedCase: expectedCase).parse(Data(contentsOf: url))
    return stream.runID == gateRunID && !stream.initialStates.isEmpty
  }

  func graphEventStreamMatchesCanonicalTLCGraph(
    at url: URL, expectedCase: CoreConformanceCaseV1, gateRunID: UUID, tlc: [String: Any]
  ) throws -> Bool {
    let data = try Data(contentsOf: url)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let stream = try parser.parse(data)
    guard stream.runID == gateRunID, !stream.initialStates.isEmpty else { return false }

    // The event stream is the primary TLC graph record. Rebuild its canonical
    // graph and require every graph field in tlc.json to be the same record.
    let complete = TLCProcessResultV1(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    let run = try parser.parseCanonicalRun(data, result: complete)
    let expected = canonicalGraphProjection(run)
    let fields = ["schema", "initialStates", "states", "edges", "observations", "observableActions"]
    for field in fields where canonicalValue(tlc[field]) != canonicalValue(expected[field]) {
      return false
    }
    return true
  }

  func rawEvidenceMatchesCanonicalOutcome(
    in directory: URL,
    expectedCase: CoreConformanceCaseV1,
    gateRunID: UUID,
    isViolation: Bool,
    tlc: [String: Any]
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
          canonicalValue(canonicalGraphProjection(primary.run))
            == canonicalValue(canonicalGraphProjection(trace.run))
    else { return false }

    let counterexample = try TLCTraceParserV1().parseCounterexample(Data(contentsOf: counterexampleURL))
    let replay = try TLCTraceParserV1().parseCounterexample(Data(contentsOf: replayJSONURL))
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

  private func canonicalOutcomeMatchesProcess(_ tlc: [String: Any], isViolation: Bool) -> Bool {
    guard let outcome = tlc["outcome"] as? [String: Any],
          (tlc["errors"] as? [[String: Any]])?.isEmpty == true,
          (tlc["traces"] as? [[String: Any]])?.isEmpty == true
    else { return false }
    if isViolation {
      return Set(outcome.keys) == ["kind", "message"]
        && outcome["kind"] as? String == "invariantViolation"
        && !(outcome["message"] as? String ?? "").isEmpty
    }
    return Set(outcome.keys) == ["kind"] && outcome["kind"] as? String == "exhaustiveSuccess"
  }

  private func graphMatchesCanonicalTLC(_ graph: ParsedPhaseGraph, tlc: [String: Any]) -> Bool {
    let projection = canonicalGraphProjection(graph.run)
    let fields = ["schema", "initialStates", "states", "edges", "observations", "observableActions"]
    return fields.allSatisfy { canonicalValue(projection[$0]) == canonicalValue(tlc[$0]) }
  }

  private func canonicalGraph(at url: URL, expectedCase: CoreConformanceCaseV1) throws -> ParsedPhaseGraph {
    let data = try Data(contentsOf: url)
    let parser = TLCGraphEventParserV1(expectedCase: expectedCase)
    let stream = try parser.parse(data)
    let result = TLCProcessResultV1(
      status: 0, stdout: "Model checking completed. No error has been found.", stderr: "")
    return ParsedPhaseGraph(runID: stream.runID, run: try parser.parseCanonicalRun(data, result: result))
  }

  private func traceBelongsToGraph(
    _ trace: TLCCounterexampleEvidenceV1, graph: CanonicalGraphV1
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
    at url: URL, expectedCase: CoreConformanceCaseV1, gateRunID: UUID
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
    var initialState: CanonicalStateV1?
    var transitions: [CanonicalEdgeV1] = []
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
              object["bodySha256"] as? String == SHA256V1.hex(body),
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
          transitions.append(CanonicalEdgeV1(source: source.key, action: actionName, target: target.key))
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
    _ provenance: [String: Any], expectedCase: CoreConformanceCaseV1
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

  private func parsePhaseState(_ value: Any?) -> CanonicalStateV1? {
    guard let state = value as? [String: Any], Set(state.keys) == ["fingerprint", "level", "bindings"],
          state["fingerprint"] as? String != nil, state["level"] as? Int != nil,
          let bindings = state["bindings"] as? [[String: Any]], !bindings.isEmpty
    else { return nil }
    var values: [String: CanonicalValueV1] = [:]
    for (index, binding) in bindings.enumerated() {
      guard Set(binding.keys) == ["ordinal", "name", "tla", "tlaSha256"],
            binding["ordinal"] as? Int == index,
            let name = binding["name"] as? String, !name.isEmpty,
            let tla = binding["tla"] as? String,
            binding["tlaSha256"] as? String == SHA256V1.hex(Data(tla.utf8)),
            values[name] == nil,
            let parsed = try? TLCValueParserV1.parse(tla)
      else { return nil }
      values[name] = parsed
    }
    return CanonicalStateV1(bindings: values)
  }

  private struct ParsedPhaseGraph {
    let runID: UUID
    let run: CanonicalRunV1
  }

  private struct ReplayPhaseTrace {
    let initialState: CanonicalStateV1
    let transitions: [CanonicalEdgeV1]
  }

  func comparisonMatchesCanonicalTruth(
    swift: [String: Any], tlc: [String: Any], comparison: [String: Any]
  ) throws -> (isDifference: Bool, fingerprint: String?) {
    let expected = try computedComparison(swift: swift, tlc: tlc)
    guard Set(comparison.keys) == ["correlation", "conformant", "differences"],
          canonicalValue(comparison["conformant"]) == canonicalValue(expected["conformant"]),
          canonicalValue(comparison["differences"]) == canonicalValue(expected["differences"])
    else { throw EvidenceValidationError.invalidCanonicalRecord }

    let isDifference = !(expected["conformant"] as! Bool)
    let fingerprint = isDifference
      ? try CoreDivergenceLedgerV1.normalizedDifferenceFingerprint(
        from: JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]))
      : nil
    return (isDifference, fingerprint)
  }

  private func computedComparison(swift: [String: Any], tlc: [String: Any]) throws -> [String: Any] {
    let expected = try validatedCanonicalProjection(tlc)
    let actual = try validatedCanonicalProjection(swift)
    var differences: [[String: Any]] = []

    if canonicalValue(expected["observableActions"]) != canonicalValue(actual["observableActions"]) {
      differences.append([
        "category": "mapping", "expected": [], "actual": [],
        "details": ["observable names differ without a declared total bijection"]
      ])
    }
    for field in ["initialStates", "states", "edges", "observations"] where
      canonicalValue(expected[field]) != canonicalValue(actual[field]) {
      differences.append(["category": field, "expected": expected[field]!, "actual": actual[field]!])
    }
    for field in ["outcome", "errors", "traces"] where
      canonicalValue(expected[field]) != canonicalValue(actual[field]) {
      differences.append(["category": field, "expected": expected[field]!, "actual": actual[field]!])
    }
    return ["conformant": differences.isEmpty, "differences": differences]
  }

  private func validatedCanonicalProjection(_ graph: [String: Any]) throws -> [String: Any] {
    let keys: Set<String> = [
      "schema", "correlation", "initialStates", "states", "edges", "observations", "observableActions",
      "outcome", "errors", "traces"
    ]
    guard Set(graph.keys) == keys,
          graph["schema"] as? String == CanonicalSchemaV1.exactFiniteTLCGraphV1.rawValue,
          let initialStates = graph["initialStates"] as? [String], !initialStates.isEmpty,
          let states = graph["states"] as? [String], !states.isEmpty,
          let edges = graph["edges"] as? [[String: Any]],
          let observations = graph["observations"] as? [[String: Any]],
          let actions = graph["observableActions"] as? [String],
          let outcome = graph["outcome"] as? [String: Any],
          let errors = graph["errors"] as? [[String: Any]],
          let traces = graph["traces"] as? [[String: Any]]
    else { throw EvidenceValidationError.invalidCanonicalRecord }
    guard Set(initialStates).count == initialStates.count, Set(states).count == states.count,
          Set(initialStates).isSubset(of: Set(states)), Set(actions).count == actions.count,
          !actions.contains(where: \.isEmpty), errors.allSatisfy(validDiagnostic),
          traces.allSatisfy({ validTrace($0, states: Set(states)) }), validOutcome(outcome)
    else { throw EvidenceValidationError.invalidCanonicalRecord }

    let occurrenceRows = try edgeOccurrences(edges, states: Set(states))
    let expectedObservations = observationRows(states: states, occurrences: occurrenceRows)
    guard canonicalValue(observations) == canonicalValue(expectedObservations) else {
      throw EvidenceValidationError.invalidCanonicalRecord
    }
    let edgeActions = Set(occurrenceRows.map { $0.action })
    guard edgeActions == Set(actions) else { throw EvidenceValidationError.invalidCanonicalRecord }
    return graph
  }

  private func canonicalGraphProjection(_ run: CanonicalRunV1) -> [String: Any] {
    let occurrences = run.graph.edgeOccurrences.keys.sorted().map { edge in
      ["edge": edge.canonicalEncoding, "count": run.graph.edgeOccurrences[edge]!] as [String: Any]
    }
    return [
      "schema": run.schema.rawValue,
      "initialStates": run.graph.initialStateKeys.sorted().map(\.canonicalEncoding),
      "states": run.graph.states.keys.sorted().map(\.canonicalEncoding),
      "edges": occurrences,
      "observations": run.graph.observations.keys.sorted().map { state in
        let observation = run.graph.observations[state]!
        return [
          "state": state.canonicalEncoding,
          "enabledActions": observation.enabledActions.sorted(),
          "isTerminal": observation.isTerminal
        ] as [String: Any]
      },
      "observableActions": run.observableActions.sorted()
    ]
  }

  private func edgeOccurrences(_ rows: [[String: Any]], states: Set<String>) throws -> [GraphEdgeOccurrence] {
    var seen = Set<String>()
    let occurrences = try rows.map { row -> GraphEdgeOccurrence in
      guard Set(row.keys) == ["edge", "count"], let edge = row["edge"] as? String,
            let count = row["count"] as? Int, count > 0, seen.insert(edge).inserted,
            let occurrence = GraphEdgeOccurrence(encoded: edge, count: count, states: states)
      else { throw EvidenceValidationError.invalidCanonicalRecord }
      return occurrence
    }
    return occurrences
  }

  private func occurrenceRows(_ rows: [[String: Any]]) -> [GraphEdgeOccurrence] {
    // This helper only receives rows produced by canonicalGraphProjection.
    rows.compactMap { row in
      guard let edge = row["edge"] as? String, let count = row["count"] as? Int,
            let separator = edge.range(of: "--"),
            let targetSeparator = edge.range(of: "-->", options: .backwards) else { return nil }
      let source = String(edge.dropFirst("edge:".count)[..<separator.lowerBound])
      let target = String(edge[targetSeparator.upperBound...])
      let action = String(edge[separator.upperBound..<targetSeparator.lowerBound]).decodedHexUTF8 ?? ""
      return GraphEdgeOccurrence(source: source, action: action, target: target, count: count)
    }
  }

  private func observationRows(states: [String], occurrences: [GraphEdgeOccurrence]) -> [[String: Any]] {
    let enabled = Dictionary(grouping: occurrences, by: \.source).mapValues { Set($0.map(\.action)).sorted() }
    return states.sorted().map { state in
      let actions = enabled[state] ?? []
      return ["state": state, "enabledActions": actions, "isTerminal": actions.isEmpty]
    }
  }

  private func validOutcome(_ outcome: [String: Any]) -> Bool {
    guard let kind = outcome["kind"] as? String else { return false }
    switch kind {
    case "exhaustiveSuccess": return Set(outcome.keys) == ["kind"]
    case "invariantViolation", "incomplete", "executionError":
      return Set(outcome.keys) == ["kind", "message"] && !(outcome["message"] as? String ?? "").isEmpty
    case "deadlock": return Set(outcome.keys) == ["kind", "state"] && !(outcome["state"] as? String ?? "").isEmpty
    default: return false
    }
  }

  private func validDiagnostic(_ diagnostic: [String: Any]) -> Bool {
    Set(diagnostic.keys) == ["code", "message"]
      && !(diagnostic["code"] as? String ?? "").isEmpty
      && !(diagnostic["message"] as? String ?? "").isEmpty
  }

  private func validTrace(_ trace: [String: Any], states: Set<String>) -> Bool {
    guard Set(trace.keys) == ["id", "steps"], !(trace["id"] as? String ?? "").isEmpty,
          let steps = trace["steps"] as? [[String: Any]] else { return false }
    return steps.allSatisfy {
      Set($0.keys) == ["state", "action"]
        && states.contains($0["state"] as? String ?? "")
        && !($0["action"] as? String ?? "").isEmpty
    }
  }

  private func canonicalValue(_ value: Any?) -> Data? {
    guard let value else { return nil }
    return try? JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys])
  }

  private struct GraphEdgeOccurrence {
    let source: String
    let action: String
    let target: String
    let count: Int

    init?(encoded: String, count: Int, states: Set<String>) {
      guard encoded.hasPrefix("edge:"), let first = encoded.range(of: "--"),
            let second = encoded.range(of: "-->", options: .backwards) else { return nil }
      let source = String(encoded.dropFirst("edge:".count)[..<first.lowerBound])
      let action = String(encoded[first.upperBound..<second.lowerBound]).decodedHexUTF8 ?? ""
      let target = String(encoded[second.upperBound...])
      guard states.contains(source), states.contains(target), !action.isEmpty else { return nil }
      self.init(source: source, action: action, target: target, count: count)
    }

    init(source: String, action: String, target: String, count: Int) {
      self.source = source
      self.action = action
      self.target = target
      self.count = count
    }
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

private extension String {
  var decodedHexUTF8: String? {
    guard count.isMultiple(of: 2) else { return nil }
    var bytes: [UInt8] = []
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: 2)
      guard let byte = UInt8(self[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    return String(bytes: bytes, encoding: .utf8)
  }
}
