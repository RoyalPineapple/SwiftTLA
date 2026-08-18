import Foundation
import SwiftTLA

public enum TemporalSymmetryConformanceRunnerErrorV1: Error, Equatable, Sendable {
  case outputAlreadyExists(String)
  case sourceOutsideProject(String)
}

public enum TemporalSymmetryCaseRunStatusV1: String, Codable, Sendable {
  case captured
  case prepared
  case unavailable
}

public struct TemporalSymmetryCaseRunV1: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryCaseRunV1"

  public let schema: String
  public let caseID: String
  public let gateRunID: UUID
  public let status: TemporalSymmetryCaseRunStatusV1
  public let diagnosticCode: String
  public let sourceInput: CoreEvidenceReferenceV1
  public let swiftGraphStateCount: Int?

  public init(
    caseID: String,
    gateRunID: UUID,
    status: TemporalSymmetryCaseRunStatusV1,
    diagnosticCode: String,
    sourceInput: CoreEvidenceReferenceV1,
    swiftGraphStateCount: Int? = nil
  ) throws {
    guard !caseID.isEmpty, !diagnosticCode.isEmpty else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: caseID, field: "case run")
    }
    try sourceInput.validate()
    self.schema = Self.schema
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.status = status
    self.diagnosticCode = diagnosticCode
    self.sourceInput = sourceInput
    self.swiftGraphStateCount = swiftGraphStateCount
  }
}

public struct TemporalSymmetryConformanceRunnerInputV1: Sendable {
  public let cases: TemporalSymmetryCasesV1
  public let gateRunID: UUID
  public let projectRoot: URL
  public let outputDirectory: URL
  public let toolRoot: URL?

  public init(
    cases: TemporalSymmetryCasesV1,
    gateRunID: UUID,
    projectRoot: URL,
    outputDirectory: URL,
    toolRoot: URL? = nil
  ) {
    self.cases = cases
    self.gateRunID = gateRunID
    self.projectRoot = projectRoot
    self.outputDirectory = outputDirectory
    self.toolRoot = toolRoot
  }
}

public struct TemporalSymmetryConformanceRunnerV1: Sendable {
  public init() {}

  @discardableResult
  public func run(_ input: TemporalSymmetryConformanceRunnerInputV1) throws -> [TemporalSymmetryCaseRunV1] {
    _ = try relativePath(input.outputDirectory, projectRoot: input.projectRoot)
    guard !FileManager.default.fileExists(atPath: input.outputDirectory.path) else {
      throw TemporalSymmetryConformanceRunnerErrorV1.outputAlreadyExists(input.outputDirectory.path)
    }
    try FileManager.default.createDirectory(at: input.outputDirectory, withIntermediateDirectories: true)
    return try input.cases.cases.map { declaredCase in
      let directory = input.outputDirectory.appendingPathComponent(declaredCase.id, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let source = try sourceURL(for: declaredCase.sourceInput, projectRoot: input.projectRoot)
      let status: TemporalSymmetryCaseRunStatusV1
      let code: String
      let graphStateCount: Int?
      if FileManager.default.fileExists(atPath: source.path),
         SHA256V1.hex(try Data(contentsOf: source)) == declaredCase.sourceInput.sha256 {
        if let model = TemporalSymmetryModelCatalogV1.model(for: declaredCase) {
          let exploration = try ModelChecker(compilation: try model.spec.compile(), maxStates: model.maxStates).explore()
          guard exploration.graph.states.count == model.expectedStateCount else {
            throw TemporalSymmetryGovernanceErrorV1.invalidField(
              record: declaredCase.id, field: "bounded Swift graph expectation")
          }
          if declaredCase.kind == .temporal, let toolRoot = input.toolRoot {
            do {
              let result = try captureTemporal(
                declaredCase: declaredCase,
                model: model,
                exploration: exploration,
                gateRunID: input.gateRunID,
                toolRoot: toolRoot,
                projectRoot: input.projectRoot,
                evidenceRoot: input.outputDirectory,
                outputDirectory: directory)
              status = result.status == .captured ? .captured : .unavailable
              code = result.diagnostic?.code ?? "captured"
            } catch {
              status = .unavailable
              code = "pinned-tlc-runtime-unavailable: \(String(describing: error))"
            }
          } else if declaredCase.kind == .symmetry, let toolRoot = input.toolRoot {
            do {
              let result = try captureSymmetry(
                declaredCase: declaredCase, exploration: exploration, gateRunID: input.gateRunID,
                toolRoot: toolRoot, projectRoot: input.projectRoot, evidenceRoot: input.outputDirectory,
                outputDirectory: directory)
              status = result ? .captured : .unavailable
              code = result ? "captured" : "symmetry-comparison-difference"
            } catch {
              status = .unavailable
              code = "pinned-tlc-symmetry-unavailable: \(String(describing: error))"
            }
          } else {
            status = .prepared
            code = "awaiting-pinned-tlc-comparison"
          }
          graphStateCount = exploration.graph.states.count
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try writeGraphSummary(
            stateCount: exploration.graph.states.count,
            to: directory.appendingPathComponent("swift-graph.json"))
        } else {
          status = .unavailable
          code = "swift-model-mapping-unavailable"
          graphStateCount = nil
        }
      } else {
        status = .unavailable
        code = "source-input-unavailable"
        graphStateCount = nil
      }
      let record = try TemporalSymmetryCaseRunV1(
        caseID: declaredCase.id,
        gateRunID: input.gateRunID,
        status: status,
        diagnosticCode: code,
        sourceInput: declaredCase.sourceInput,
        swiftGraphStateCount: graphStateCount)
      try write(record, to: directory.appendingPathComponent("case-run.json"))
      return record
    }
  }

  private func sourceURL(for reference: CoreEvidenceReferenceV1, projectRoot: URL) throws -> URL {
    let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
    let source = root.appendingPathComponent(reference.path).resolvingSymlinksInPath().standardizedFileURL
    guard source.path.hasPrefix(root.path + "/") else {
      throw TemporalSymmetryConformanceRunnerErrorV1.sourceOutsideProject(reference.path)
    }
    return source
  }

  private func captureTemporal(
    declaredCase: TemporalSymmetryCaseV1,
    model: TemporalSymmetryModelDefinitionV1,
    exploration: ModelExplorationResult,
    gateRunID: UUID,
    toolRoot: URL,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TLCTemporalCaptureResultV1 {
    try FileManager.default.removeItem(at: outputDirectory)
    let swiftRun = try SwiftGraphAdapterV1().adapt(exploration)
    let correlation = try TemporalSymmetryCaseRunCorrelationV1(
      caseID: declaredCase.id, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let inputs = evidenceRoot.appendingPathComponent("swift-inputs", isDirectory: true)
      .appendingPathComponent(declaredCase.id, isDirectory: true)
    try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
    let swiftResult = try temporalResult(
      declaredCase: declaredCase, model: model, exploration: exploration, swiftRun: swiftRun,
      correlation: correlation, inputs: inputs, projectRoot: projectRoot)
    let swiftEvidence = try reference(
      inputs.appendingPathComponent("swift-result.json"), projectRoot: projectRoot)
    let enablednessEvidence = try reference(
      inputs.appendingPathComponent("enabledness.json"), projectRoot: projectRoot)
    let casesURL = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let toolchainURL = projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json")
    let pin = try pin(from: declaredCase.provenance)
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: pin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let source = try sourceURL(for: declaredCase.sourceInput, projectRoot: projectRoot)
    let config = try configurationURL(for: declaredCase, projectRoot: projectRoot)
    let launch = try CoreConformanceCaseV1(
      id: declaredCase.id,
      moduleSHA256: declaredCase.provenance.moduleSHA256,
      cfgSHA256: declaredCase.provenance.cfgSHA256,
      arguments: ["-workers", "1", "-fp", "1"],
      argumentsSHA256: declaredCase.provenance.argumentsSHA256,
      workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
      architecture: context.architecture, environment: [:], pin: pin)
    let request = TLCProcessRequestV1(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      module: source, configuration: config,
      graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: ["-workers", "1", "-fp", "1"], expectedCase: launch,
      runID: correlation.tlcRunID, referencePin: pin, referenceArtifacts: context.artifacts)
    let completeGraphRequest: TLCProcessRequestV1?
    if let graphPass = declaredCase.configuration.completeGraphPass {
      let graphConfig = try sourceURL(for: graphPass.configuration, projectRoot: projectRoot)
      let graphCase = try CoreConformanceCaseV1(
        id: declaredCase.id, moduleSHA256: declaredCase.provenance.moduleSHA256,
        cfgSHA256: graphPass.configuration.sha256,
        arguments: ["-workers", "1", "-fp", "1"],
        argumentsSHA256: declaredCase.provenance.argumentsSHA256,
        workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
        architecture: context.architecture, environment: [:], pin: pin)
      completeGraphRequest = TLCProcessRequestV1(
        javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
        module: source, configuration: graphConfig,
        graphEvents: work.appendingPathComponent("complete-graph-events.jsonl"),
        traceOutput: work.appendingPathComponent("complete-graph-counterexample.json"),
        replayInput: work.appendingPathComponent("complete-graph-replay.json"), workingDirectory: work,
        arguments: graphCase.arguments, expectedCase: graphCase, runID: UUID(),
        referencePin: pin, referenceArtifacts: context.artifacts)
    } else {
      completeGraphRequest = nil
    }
    return TLCTemporalAdapterV1().capture(TLCTemporalCaptureInputV1(
      declaredCase: declaredCase, correlation: correlation, request: request,
      completeGraphRequest: completeGraphRequest, swiftResult: swiftResult,
      swiftEvidence: swiftEvidence, enablednessEvidence: enablednessEvidence, fairComponents: [], rejectedComponents: [],
      allowsImplicitStuttering: declaredCase.configuration.allowsImplicitStuttering,
      manifest: try reference(casesURL, projectRoot: projectRoot), manifestURL: casesURL,
      toolchain: try reference(toolchainURL, projectRoot: projectRoot), toolchainURL: toolchainURL,
      sourceInputURL: source, outputDirectory: outputDirectory,
      relativeOutputDirectory: try relativePath(outputDirectory, projectRoot: projectRoot)))
  }

  private func captureSymmetry(
    declaredCase: TemporalSymmetryCaseV1,
    exploration: ModelExplorationResult,
    gateRunID: UUID,
    toolRoot: URL,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> Bool {
    guard let scope = declaredCase.configuration.symmetryScope else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: declaredCase.id, field: "symmetry scope")
    }
    let pin = try pin(from: declaredCase.provenance)
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: pin)
    let correlation = try TemporalSymmetryCaseRunCorrelationV1(
      caseID: declaredCase.id, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let pair = try PinnedSymmetryTLCCorrelationV1(
      caseID: declaredCase.id, gateRunID: gateRunID, comparisonRunID: correlation.comparisonRunID,
      rawRunID: correlation.tlcRunID, reducedRunID: UUID())
    let source = try sourceURL(for: declaredCase.sourceInput, projectRoot: projectRoot)
    let rawConfig = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/symmetry/scope-\(scope)-raw.cfg")
    let reducedConfig = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/symmetry/scope-\(scope)-reduced.cfg")
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id, isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let rawCase = try launchCase(
      id: declaredCase.id, module: source, configuration: rawConfig, pin: pin, architecture: context.architecture)
    let reducedCase = try launchCase(
      id: declaredCase.id, module: source, configuration: reducedConfig, pin: pin, architecture: context.architecture)
    let rawRequest = try request(
      context: context, module: source, configuration: rawConfig, work: work.appendingPathComponent("raw"),
      declared: rawCase, runID: pair.rawRunID)
    let reducedRequest = try request(
      context: context, module: source, configuration: reducedConfig, work: work.appendingPathComponent("reduced"),
      declared: reducedCase, runID: pair.reducedRunID)
    let tlc = try PinnedSymmetryTLCAdapterV1().run(
      correlation: pair, raw: rawRequest, reduced: reducedRequest, replay: .none)
    let swiftRaw = try SwiftGraphAdapterV1().adapt(exploration)
    let permutations = try symmetryPermutations(scope: scope)
    let swiftReduced = try reducedRun(swiftRaw, permutations: permutations)
    let configurationURL = outputDirectory.appendingPathComponent("symmetry-configuration.json")
    try writeJSON([
      "raw": ["path": try relativePath(rawConfig, projectRoot: projectRoot), "sha256": SHA256V1.hex(Data(contentsOf: rawConfig))],
      "reduced": ["path": try relativePath(reducedConfig, projectRoot: projectRoot), "sha256": SHA256V1.hex(Data(contentsOf: reducedConfig))]
    ], to: configurationURL)
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.json")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.json")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.json")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.json")
    try writeGraph(swiftRaw, to: rawSwiftURL)
    try writeGraph(swiftReduced, to: reducedSwiftURL)
    try writeGraph(tlc.raw, to: rawTLCURL)
    try writeGraph(tlc.reduced, to: reducedTLCURL)
    let configurationDigest = SHA256V1.hex(try Data(contentsOf: configurationURL))
    let quotientURL = outputDirectory.appendingPathComponent("swift-quotient.json")
    try writeGraph(swiftReduced, to: quotientURL)
    let input = try SymmetryOrbitComparisonInputV1(
      caseID: declaredCase.id, configuration: declaredCase.configuration, correlation: correlation,
      swiftRaw: try symmetryExploration(.swift, false, correlation.swiftRunID, swiftRaw, configurationDigest, rawSwiftURL, projectRoot),
      swiftReduced: try symmetryExploration(.swift, true, UUID(), swiftReduced, configurationDigest, reducedSwiftURL, projectRoot),
      tlcRaw: try symmetryExploration(.tlc, false, correlation.tlcRunID, tlc.raw, configurationDigest, rawTLCURL, projectRoot),
      tlcReduced: try symmetryExploration(.tlc, true, pair.reducedRunID, tlc.reduced, configurationDigest, reducedTLCURL, projectRoot),
      swiftRawRun: swiftRaw, swiftReducedRun: swiftReduced, tlcRawRun: tlc.raw, tlcReducedRun: tlc.reduced,
      configurationEvidence: try reference(configurationURL, projectRoot: projectRoot),
      quotientEvidence: try reference(quotientURL, projectRoot: projectRoot), permutations: permutations)
    guard case .exact(let comparison) = try SymmetryOrbitComparatorV1().compare(input) else { return false }
    try write(comparison, to: outputDirectory.appendingPathComponent("symmetry-orbit-comparison.json"))
    return true
  }

}

extension TemporalSymmetryConformanceRunnerV1 {
  private func launchCase(id: String, module: URL, configuration: URL, pin: TLCReferencePinV1, architecture: String) throws -> CoreConformanceCaseV1 {
    let arguments = ["-workers", "1", "-fp", "1"]
    return try CoreConformanceCaseV1(
      id: id, moduleSHA256: SHA256V1.hex(Data(contentsOf: module)), cfgSHA256: SHA256V1.hex(Data(contentsOf: configuration)),
      arguments: arguments, argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(arguments), workers: 1,
      fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: architecture, environment: [:], pin: pin)
  }

  private func request(context: TLCContext, module: URL, configuration: URL, work: URL, declared: CoreConformanceCaseV1, runID: UUID) throws -> TLCProcessRequestV1 {
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    return TLCProcessRequestV1(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses, module: module, configuration: configuration,
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: declared.arguments, expectedCase: declared, runID: runID, referencePin: declared.pin, referenceArtifacts: context.artifacts)
  }

  private func write(_ record: TemporalSymmetryCaseRunV1, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(record)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }

  private func writeGraphSummary(stateCount: Int, to url: URL) throws {
    try JSONSerialization.data(
      withJSONObject: ["stateCount": stateCount], options: [.prettyPrinted, .sortedKeys]
    ).write(to: url, options: .atomic)
  }

  private func symmetryPermutations(scope: Int) throws -> [SymmetryPermutationV1] {
    let names = (0..<scope).map { String(UnicodeScalar(97 + $0)!) }
    var permutations = [try SymmetryPermutationV1(constantMapping: Dictionary(uniqueKeysWithValues: names.map { ($0, $0) }))]
    for index in names.indices.dropFirst() {
      var mapping = Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
      mapping[names[0]] = names[index]
      mapping[names[index]] = names[0]
      permutations.append(try SymmetryPermutationV1(constantMapping: mapping))
    }
    return permutations
  }

  private func reducedRun(_ raw: CanonicalRunV1, permutations: [SymmetryPermutationV1]) throws -> CanonicalRunV1 {
    let derivation = try SymmetryOrbitDerivationV1(states: Array(raw.graph.states.values), permutations: permutations)
    let table = Dictionary(uniqueKeysWithValues: raw.graph.states.map { ($0.key, $0.value) })
    let representatives = try derivation.orbits.map { orbit -> CanonicalStateV1 in
      guard let state = table[orbit[0]] else { throw SymmetryOrbitAdapterErrorV1.incompleteOrbit(orbit[0].canonicalEncoding) }
      return state
    }
    let initial = try Set(raw.graph.initialStateKeys.compactMap { derivation.representativeForState[$0] }).map { key -> CanonicalStateV1 in
      guard let state = table[key] else { throw SymmetryOrbitAdapterErrorV1.incompleteOrbit(key.canonicalEncoding) }
      return state
    }
    let edges = Set(raw.graph.edgeOccurrences.keys.compactMap { edge -> CanonicalEdgeV1? in
      guard let source = derivation.representativeForState[edge.source],
            let target = derivation.representativeForState[edge.target] else { return nil }
      return CanonicalEdgeV1(source: source, action: edge.action, target: target)
    })
    guard initial.count == raw.graph.initialStateKeys.count, edges.isEmpty == false else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "symmetry quotient", field: "initial state or transitions")
    }
    return try CanonicalRunV1(
      graph: CanonicalGraphV1(initialStates: initial, states: representatives, edges: Array(edges)),
      observableActions: Set(edges.map(\.action)), outcome: raw.outcome)
  }

  private func writeGraph(_ run: CanonicalRunV1, to url: URL) throws {
    try writeJSON([
      "graphID": TLCTemporalAdapterV1.graphID(run),
      "initialStateIDs": run.graph.initialStateKeys.sorted().map(\.canonicalEncoding),
      "stateIDs": run.graph.states.keys.sorted().map(\.canonicalEncoding),
      "transitions": run.graph.edgeOccurrences.keys.sorted().map {
        ["source": $0.source.canonicalEncoding, "action": $0.action, "target": $0.target.canonicalEncoding]
      }
    ], to: url)
  }

  private func symmetryExploration(
    _ engine: SymmetryExplorationEngineV1, _ reduced: Bool, _ runID: UUID, _ run: CanonicalRunV1,
    _ configurationSHA256: String, _ graphURL: URL, _ projectRoot: URL
  ) throws -> SymmetryExplorationV1 {
    try SymmetryExplorationV1(
      engine: engine, reduced: reduced, runID: runID, graphID: TLCTemporalAdapterV1.graphID(run),
      initialStateIDs: run.graph.initialStateKeys.map(\.canonicalEncoding), stateIDs: run.graph.states.keys.map(\.canonicalEncoding),
      transitions: try run.graph.edgeOccurrences.keys.map {
        try SymmetryRawTransitionWitnessV1(
          engine: engine,
          sourceStateID: $0.source.canonicalEncoding,
          action: $0.action,
          targetStateID: $0.target.canonicalEncoding
        )
      }, declaredConfigurationSHA256: configurationSHA256, graphEvidence: try reference(graphURL, projectRoot: projectRoot),
      invariantOutcome: .notApplicable, deadlockOutcome: .notApplicable)
  }

  private func temporalResult(
    declaredCase: TemporalSymmetryCaseV1,
    model: TemporalSymmetryModelDefinitionV1,
    exploration: ModelExplorationResult,
    swiftRun: CanonicalRunV1,
    correlation: TemporalSymmetryCaseRunCorrelationV1,
    inputs: URL,
    projectRoot: URL
  ) throws -> TemporalPropertyResultV1 {
    guard let property = model.spec.temporalProperties.first else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: declaredCase.id, field: "temporal property")
    }
    let analysis = LivenessChecker(graph: exploration.graph).analyze(
      property.expr, fairness: model.spec.fairness, actions: model.spec.actions,
      initialStateIDs: exploration.initialStateIDs, isComplete: exploration.isComplete)
    let resultURL = inputs.appendingPathComponent("swift-result.json")
    let enablednessURL = inputs.appendingPathComponent("enabledness.json")
    try writeJSON([
      "caseID": declaredCase.id,
      "correlation": correlation.tlcRunID.uuidString.lowercased(),
      "status": String(describing: analysis.status),
      "graphID": TLCTemporalAdapterV1.graphID(swiftRun)
    ], to: resultURL)
    try writeJSON([
      "caseID": declaredCase.id,
      "enabledActions": analysis.enabledActions.mapValues { states in
        states.mapKeys { "s\($0.id)" }.mapValues { $0 }
      }
    ], to: enablednessURL)
    let initial = swiftRun.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
    switch analysis.status {
    case .satisfied:
      return try TemporalPropertyResultV1(
        availability: .evaluated, outcome: .satisfied,
        graphID: TLCTemporalAdapterV1.graphID(swiftRun), initialStateIDs: initial,
        traceAvailability: .notApplicable)
    case .violated:
      guard let witness = analysis.witness else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: declaredCase.id, field: "Swift lasso")
      }
      let keys = try stateKeys(exploration)
      let cycle = witness.cycle.map { keys[$0] ?? "" }
      guard !cycle.contains("") else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: declaredCase.id, field: "Swift lasso state")
      }
      let closedCycle = cycle.first == cycle.last ? cycle : cycle + [cycle[0]]
      let lasso = try TemporalLassoWitnessV1(
        prefixStateIDs: witness.prefix.compactMap { keys[$0] }, cycleStateIDs: closedCycle)
      let traceURL = inputs.appendingPathComponent("swift-lasso.json")
      try write(lasso, to: traceURL)
      return try TemporalPropertyResultV1(
        availability: .evaluated, outcome: .violated,
        graphID: TLCTemporalAdapterV1.graphID(swiftRun), initialStateIDs: initial,
        traceAvailability: .available, traceEvidence: try reference(traceURL, projectRoot: projectRoot), lasso: lasso)
    case .unavailable:
      return try TemporalPropertyResultV1(
        availability: .unavailable, outcome: nil,
        graphID: TLCTemporalAdapterV1.graphID(swiftRun), initialStateIDs: initial,
        traceAvailability: .unavailable)
    }
  }

  private func stateKeys(_ exploration: ModelExplorationResult) throws -> [StateGraph.StateID: String] {
    Dictionary(uniqueKeysWithValues: exploration.graph.states.map { id, bindings in
      (id, CanonicalStateV1(bindings: bindings.mapValues(CanonicalValueV1.init)).key.canonicalEncoding)
    })
  }

  private func configurationURL(for declaredCase: TemporalSymmetryCaseV1, projectRoot: URL) throws -> URL {
    let names = [
      "temporal-always-none": "always-none.cfg",
      "temporal-eventually-none": "eventually-none.cfg",
      "temporal-always-eventually-none": "always-eventually-none.cfg",
      "temporal-eventually-always-weak": "eventually-always-weak.cfg",
      "temporal-leads-to-strong": "leads-to-strong.cfg",
      "temporal-weak-fairness-boundary": "weak-boundary.cfg",
      "temporal-strong-fairness-boundary": "strong-boundary.cfg"
    ]
    guard let name = names[declaredCase.id] else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: declaredCase.id, field: "TLC configuration")
    }
    return projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/temporal/\(name)")
  }

  private func pin(from provenance: CoreDivergenceProvenanceV1) throws -> TLCReferencePinV1 {
    try TLCReferencePinV1(
      tag: provenance.tlcTag, commit: provenance.tlcCommit, jarSHA256: provenance.tlcJarSHA256,
      javaDistribution: provenance.javaDistribution, javaVersion: provenance.javaVersion,
      javaArchiveSHA256: provenance.javaArchiveSHA256, bridgeClass: provenance.bridgeClass,
      bridgeSourceSHA256: provenance.bridgeSourceSHA256, bridgeBinarySHA256: provenance.bridgeBinarySHA256)
  }

  private func reference(_ url: URL, projectRoot: URL) throws -> CoreEvidenceReferenceV1 {
    try CoreEvidenceReferenceV1(
      path: try relativePath(url, projectRoot: projectRoot), sha256: SHA256V1.hex(Data(contentsOf: url)))
  }

  func relativePath(_ url: URL, projectRoot: URL) throws -> String {
    let root = normalizedProjectPath(projectRoot)
    let value = normalizedProjectPath(url)
    guard value.hasPrefix(root + "/") else {
      throw TemporalSymmetryConformanceRunnerErrorV1.sourceOutsideProject(value)
    }
    return String(value.dropFirst(root.count + 1))
  }

  private func normalizedProjectPath(_ url: URL) -> String {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    guard path == "/tmp" || path.hasPrefix("/tmp/") else { return path }
    return "/private" + path
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }

  private func writeJSON(_ value: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
  }
}

private struct TLCContext {
  let architecture: String
  let java: URL
  let jar: URL
  let bridgeClasses: URL
  let artifacts: TLCReferenceArtifactsV1

  init(toolRoot: URL, projectRoot: URL, pin: TLCReferencePinV1) throws {
    let armJava = toolRoot.appendingPathComponent("java-arm64/Contents/Home/bin/java")
    architecture = FileManager.default.fileExists(atPath: armJava.path) ? "arm64" : "x86_64"
    java = toolRoot.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
    jar = toolRoot.appendingPathComponent("downloads/tla2tools.jar")
    bridgeClasses = toolRoot.appendingPathComponent("bridge-classes")
    let archive = toolRoot.appendingPathComponent("downloads/temurin-\(architecture).tar.gz")
    let source = projectRoot.appendingPathComponent("Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java")
    let binary = bridgeClasses.appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/")).appendingPathExtension("class")
    artifacts = try TLCReferenceInspectorV1.inspect(
      artifacts: TLCReferenceArtifactsV1(
        jar: jar, javaArchive: archive, bridgeSource: source, bridgeBinary: binary,
        jarManifest: "", runtime: .init(version: "", vendor: "", architecture: architecture, properties: [:])),
      javaExecutable: java, directory: projectRoot)
    try pin.validate(artifacts)
  }
}

private extension Dictionary where Key == StateGraph.StateID, Value == Bool {
  func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Bool] {[T: Bool](uniqueKeysWithValues: map { (transform($0.key), $0.value) })
  }
}

public struct TemporalSymmetryModelDefinitionV1: Sendable {
  public let spec: TLASpec
  public let expectedStateCount: Int
  public let maxStates: Int
}

public enum TemporalSymmetryModelCatalogV1 {
  public static func model(for declaredCase: TemporalSymmetryCaseV1) -> TemporalSymmetryModelDefinitionV1? {
    switch declaredCase.swiftSpec {
    case "TemporalMatrix":
      return temporalMatrix(configuration: declaredCase.configuration)
    case "SymmetricCollectionScope2":
      return symmetricCollection(scope: 2)
    case "SymmetricCollectionScope3":
      return symmetricCollection(scope: 3)
    case "SymmetricCollectionScope4":
      return symmetricCollection(scope: 4)
    default:
      return nil
    }
  }

  private static func temporalMatrix(
    configuration: TemporalSymmetryConfigurationV1
  ) -> TemporalSymmetryModelDefinitionV1? {
    let x = Var<Int>("x")
    let p = x == 2
    let q = x == 1
    let temporal = temporalProperty(property: configuration.property, p: p, q: q)
    let spec = TLASpec(
      name: "TemporalMatrix",
      variables: [NamedVar(name: x.name, initial: 0)],
      actions: [
        NamedAction(name: "A", body: .and(.guard_(x == 0), x.becomes(2))),
        NamedAction(name: "B", body: .and(.guard_(x == 0), x.becomes(1))),
        NamedAction(name: "C", body: .and(.guard_(x == 1), x.becomes(0))),
        NamedAction(name: "Stay", body: .and(.guard_(x == 2), x.becomes(2)))
      ],
      invariants: [],
      temporalProperties: temporal.map { [NamedTemporal(name: $0.0, expr: $0.1)] } ?? [],
      fairness: fairness(configuration.fairness))
    return .init(spec: spec, expectedStateCount: 3, maxStates: 10)
  }

  private static func temporalProperty(
    property: String?, p: StateExpr, q: StateExpr
  ) -> (String, TemporalExpr)? {
    switch property {
    case "AlwaysP": return ("AlwaysP", .always(p))
    case "EventuallyP": return ("EventuallyP", .eventually(p))
    case "AlwaysEventuallyP": return ("AlwaysEventuallyP", .alwaysEventually(p))
    case "EventuallyAlwaysP": return ("EventuallyAlwaysP", .eventuallyAlways(p))
    case "LeadsToPQ": return ("LeadsToPQ", .leadsTo(p, q))
    default: return nil
    }
  }

  private static func fairness(_ fairness: TemporalFairnessModeV1?) -> [FairnessCondition] {
    switch fairness {
    case .weak: return [.weakFairness("A")]
    case .strong: return [.strongFairness("A")]
    case .some(.none), nil: return []
    }
  }

  private static func symmetricCollection(scope: Int) -> TemporalSymmetryModelDefinitionV1 {
    let members = (0..<scope).map { TLAValue.constant(String(UnicodeScalar(97 + $0)!)) }
    let memberSet = StateExpr.setLiteral(members.map(StateExpr.value))
    let choose = ActionExpr.existsAction(
      "m", memberSet,
      .assign("chosen", .union(.variable("chosen"), .setLiteral([.variable("m")])))
    )
    let spec = TLASpec(
      name: "SymmetricCollectionScope\(scope)",
      variables: [NamedVar(name: "chosen", initial: .set([]))],
      actions: [NamedAction(name: "Choose", body: choose)],
      invariants: [])
    return .init(spec: spec, expectedStateCount: 1 << scope, maxStates: 1 << (scope + 1))
  }
}
