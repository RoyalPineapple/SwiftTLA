import Foundation
import SwiftTLA

public enum TemporalSymmetryCaseRunStatus: String, Codable, Sendable {
  case captured
  case prepared
  case unavailable
}

public struct TemporalSymmetryCaseRun: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryCaseRun"

  public let schema: String
  public let caseID: String
  public let gateRunID: UUID
  public let status: TemporalSymmetryCaseRunStatus
  public let diagnosticCode: String
  public let sourceInput: CoreEvidenceReference
  public let swiftGraphStateCount: Int?

  public init(
    caseID: String,
    gateRunID: UUID,
    status: TemporalSymmetryCaseRunStatus,
    diagnosticCode: String,
    sourceInput: CoreEvidenceReference,
    swiftGraphStateCount: Int? = nil
  ) throws {
    guard !caseID.isEmpty, !diagnosticCode.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "case run")
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

public struct TemporalSymmetryConformanceRunnerInput: Sendable {
  public let cases: TemporalSymmetryCases
  public let gateRunID: UUID
  public let projectRoot: URL
  public let outputDirectory: URL
  public let toolRoot: URL?

  public init(
    cases: TemporalSymmetryCases,
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

public struct TemporalSymmetryConformanceRunner: Sendable {
  public init() {}

  @discardableResult
  public func run(_ input: TemporalSymmetryConformanceRunnerInput) throws -> [TemporalSymmetryCaseRun] {
    let root = try ConformanceEvidence.projectRoot(input.projectRoot)
    let output = try ConformanceEvidence.outputDirectory(input.outputDirectory, beneath: root)
    return try input.cases.cases.map { declaredCase in
      let directory = try ConformanceEvidence.createDirectory(
        output.appendingPathComponent(declaredCase.id, isDirectory: true), beneath: root)
      let status: TemporalSymmetryCaseRunStatus
      let code: String
      let graphStateCount: Int?
      if (try? ConformanceEvidence.data(for: declaredCase.sourceInput, beneath: root)) != nil {
        if let model = try TemporalSymmetryModelCatalog.model(for: declaredCase) {
          let compilation = try model.spec.compile()
          let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
          ).explore()
          guard exploration.graph.states.count == model.expectedStateCount else {
            throw ConformanceGovernanceError.invalidField(
              record: declaredCase.id, field: "bounded Swift graph expectation")
          }
          if declaredCase.kind == .temporal, let toolRoot = input.toolRoot {
            do {
              let result = try captureTemporal(
                compilation: compilation, declaredCase: declaredCase,
                model: model,
                exploration: exploration,
                gateRunID: input.gateRunID,
                toolRoot: toolRoot,
                projectRoot: root,
                evidenceRoot: output,
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
                compilation: compilation, maximumStateLimit: model.maxStates,
                declaredCase: declaredCase, exploration: exploration, gateRunID: input.gateRunID,
                toolRoot: toolRoot, projectRoot: root, evidenceRoot: output,
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
      let record = try TemporalSymmetryCaseRun(
        caseID: declaredCase.id,
        gateRunID: input.gateRunID,
        status: status,
        diagnosticCode: code,
        sourceInput: declaredCase.sourceInput,
        swiftGraphStateCount: graphStateCount)
      try ConformanceEvidence.writeCanonical(record, to: directory.appendingPathComponent("case-run.json"), trailingNewline: true)
      return record
    }
  }

  private func captureTemporal(
    compilation: CompiledSpecification,
    declaredCase: TemporalSymmetryCase,
    model: TemporalSymmetryModelDefinition,
    exploration: ModelExplorationResult,
    gateRunID: UUID,
    toolRoot: URL,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TLCTemporalCaptureResult {
    try FileManager.default.removeItem(at: outputDirectory)
    let swiftRun = try SwiftGraphAdapter().adapt(exploration)
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: declaredCase.id, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let inputs = evidenceRoot.appendingPathComponent("swift-inputs", isDirectory: true)
      .appendingPathComponent(declaredCase.id, isDirectory: true)
    try ConformanceEvidence.createDirectory(inputs, beneath: projectRoot)
    let swiftResult = try temporalResult(
      compilation: compilation, declaredCase: declaredCase, model: model, exploration: exploration, swiftRun: swiftRun,
      correlation: correlation, inputs: inputs, projectRoot: projectRoot)
    let swiftEvidence = try ConformanceEvidence.reference(
      for: inputs.appendingPathComponent("swift-result.json"), beneath: projectRoot)
    let enablednessEvidence = try ConformanceEvidence.reference(
      for: inputs.appendingPathComponent("enabledness.json"), beneath: projectRoot)
    let casesURL = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let toolchainURL = projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json")
    let pin = try declaredCase.provenance.tlcReferencePin()
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: pin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id)
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
    let source = try ConformanceEvidence.resolve(
      projectRoot.appendingPathComponent(declaredCase.sourceInput.path), beneath: projectRoot)
    let config = try configurationURL(for: declaredCase, projectRoot: projectRoot)
    let bundle = try TLCProcessRequest.declaredBundle(root: source, configuration: config)
    let launch = try CoreConformanceCase(
      id: declaredCase.id,
      moduleSHA256: declaredCase.provenance.moduleSHA256,
      cfgSHA256: declaredCase.provenance.cfgSHA256,
      arguments: ["-workers", "1", "-fp", "1"],
      argumentsSHA256: declaredCase.provenance.argumentsSHA256,
      workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
      architecture: context.architecture, environment: [:], pin: pin)
    let request = TLCProcessRequest(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: ["-workers", "1", "-fp", "1"], expectedCase: launch,
      runID: correlation.tlcRunID, referencePin: pin, referenceArtifacts: context.artifacts)
    let completeGraphRequest: TLCProcessRequest?
    if let graphPass = declaredCase.configuration.completeGraphPass {
      let graphConfig = try ConformanceEvidence.resolve(
        projectRoot.appendingPathComponent(graphPass.configuration.path), beneath: projectRoot)
      let graphBundle = try TLCProcessRequest.declaredBundle(root: source, configuration: graphConfig)
      let graphCase = try CoreConformanceCase(
        id: declaredCase.id, moduleSHA256: declaredCase.provenance.moduleSHA256,
        cfgSHA256: graphPass.configuration.sha256,
        arguments: ["-workers", "1", "-fp", "1"],
        argumentsSHA256: declaredCase.provenance.argumentsSHA256,
        workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
        architecture: context.architecture, environment: [:], pin: pin)
      completeGraphRequest = TLCProcessRequest(
        javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
        bundle: graphBundle,
        graphEvents: work.appendingPathComponent("complete-graph-events.jsonl"),
        traceOutput: work.appendingPathComponent("complete-graph-counterexample.json"),
        replayInput: work.appendingPathComponent("complete-graph-replay.json"), workingDirectory: work,
        arguments: graphCase.arguments, expectedCase: graphCase, runID: UUID(),
        referencePin: pin, referenceArtifacts: context.artifacts)
    } else {
      completeGraphRequest = nil
    }
    return TLCTemporalAdapter().capture(TLCTemporalCaptureInput(
      declaredCase: declaredCase, correlation: correlation, request: request,
      completeGraphRequest: completeGraphRequest, swiftResult: swiftResult,
      swiftEvidence: swiftEvidence, enablednessEvidence: enablednessEvidence, fairComponents: [], rejectedComponents: [],
      allowsImplicitStuttering: declaredCase.configuration.allowsImplicitStuttering,
      manifest: try ConformanceEvidence.reference(for: casesURL, beneath: projectRoot), manifestURL: casesURL,
      toolchain: try ConformanceEvidence.reference(for: toolchainURL, beneath: projectRoot), toolchainURL: toolchainURL,
      sourceInputURL: source, outputDirectory: outputDirectory,
      relativeOutputDirectory: try ConformanceEvidence.relativePath(for: outputDirectory, beneath: projectRoot)))
  }

  private func captureSymmetry(
    compilation: CompiledSpecification,
    maximumStateLimit: Int,
    declaredCase: TemporalSymmetryCase,
    exploration: ModelExplorationResult,
    gateRunID: UUID,
    toolRoot: URL,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> Bool {
    guard let scope = declaredCase.configuration.symmetryScope else {
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "symmetry scope")
    }
    let pin = try declaredCase.provenance.tlcReferencePin()
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: pin)
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: declaredCase.id, gateRunID: gateRunID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let pair = try PinnedSymmetryTLCCorrelation(
      caseID: declaredCase.id, gateRunID: gateRunID, comparisonRunID: correlation.comparisonRunID,
      rawRunID: correlation.tlcRunID, reducedRunID: UUID())
    let source = try ConformanceEvidence.resolve(
      projectRoot.appendingPathComponent(declaredCase.sourceInput.path), beneath: projectRoot)
    let rawConfig = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/symmetry/scope-\(scope)-raw.cfg")
    let reducedConfig = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/symmetry/scope-\(scope)-reduced.cfg")
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id, isDirectory: true)
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
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
    let tlc = try PinnedSymmetryTLCAdapter().run(
      correlation: pair, raw: rawRequest, reduced: reducedRequest, replay: .none)
    let swiftRaw = try SwiftGraphAdapter().adapt(exploration)
    let permutations = try symmetryPermutations(scope: scope)
    let swiftReduced = try reducedRun(swiftRaw, permutations: permutations)
    let configurationURL = outputDirectory.appendingPathComponent("symmetry-configuration.json")
    try ConformanceEvidence.writeJSON([
      "raw": ["path": try ConformanceEvidence.relativePath(for: rawConfig, beneath: projectRoot), "sha256": SHA256.hex(Data(contentsOf: rawConfig))],
      "reduced": ["path": try ConformanceEvidence.relativePath(for: reducedConfig, beneath: projectRoot), "sha256": SHA256.hex(Data(contentsOf: reducedConfig))]
    ], to: configurationURL)
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.json")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.json")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.json")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.json")
    let configurationDigest = SHA256.hex(try Data(contentsOf: configurationURL))
    let symmetrySchemaIdentity = SHA256.hex(Data(
      permutations.map {
        $0.constantMapping.sorted { $0.key < $1.key }
          .map { "\($0.key)->\($0.value)" }
          .joined(separator: "|")
      }.sorted().joined(separator: "\n").utf8
    ))
    let receiptContext = CanonicalRunEvidence.ReceiptContext(
      compiledModelIdentity: compilation.identity.value,
      configurationIdentity: configurationDigest,
      symmetrySchemaIdentity: symmetrySchemaIdentity,
      observableNameMappingIdentity: nil,
      maximumStateLimit: maximumStateLimit)
    let swiftReducedRunID = UUID()
    try CanonicalRunEvidence.write(
      swiftRaw,
      correlation: .init(caseID: declaredCase.id, runID: correlation.swiftRunID, engine: .swift),
      receiptContext: receiptContext,
      to: rawSwiftURL)
    try CanonicalRunEvidence.write(
      swiftReduced,
      correlation: .init(caseID: declaredCase.id, runID: swiftReducedRunID, engine: .swift),
      receiptContext: receiptContext,
      to: reducedSwiftURL)
    try CanonicalRunEvidence.write(
      tlc.raw,
      correlation: .init(caseID: declaredCase.id, runID: correlation.tlcRunID, engine: .tlc),
      receiptContext: receiptContext,
      to: rawTLCURL)
    try CanonicalRunEvidence.write(
      tlc.reduced,
      correlation: .init(caseID: declaredCase.id, runID: pair.reducedRunID, engine: .tlc),
      receiptContext: receiptContext,
      to: reducedTLCURL)
    let input = try SymmetryOrbitComparisonInput(
      caseID: declaredCase.id, configuration: declaredCase.configuration, correlation: correlation,
      swiftRaw: try symmetryExploration(.swift, false, correlation.swiftRunID, swiftRaw, configurationDigest, rawSwiftURL, projectRoot),
      swiftReduced: try symmetryExploration(.swift, true, swiftReducedRunID, swiftReduced, configurationDigest, reducedSwiftURL, projectRoot),
      tlcRaw: try symmetryExploration(.tlc, false, correlation.tlcRunID, tlc.raw, configurationDigest, rawTLCURL, projectRoot),
      tlcReduced: try symmetryExploration(.tlc, true, pair.reducedRunID, tlc.reduced, configurationDigest, reducedTLCURL, projectRoot),
      swiftRawRun: swiftRaw, swiftReducedRun: swiftReduced, tlcRawRun: tlc.raw, tlcReducedRun: tlc.reduced,
      configurationEvidence: try ConformanceEvidence.reference(for: configurationURL, beneath: projectRoot),
      quotientEvidence: try ConformanceEvidence.reference(for: reducedSwiftURL, beneath: projectRoot), permutations: permutations)
    guard case .exact(let comparison) = try SymmetryOrbitComparator().compare(input) else { return false }
    try ConformanceEvidence.writeCanonical(comparison, to: outputDirectory.appendingPathComponent("symmetry-orbit-comparison.json"))
    return true
  }

}

extension TemporalSymmetryConformanceRunner {
  private func launchCase(id: String, module: URL, configuration: URL, pin: TLCReferencePin, architecture: String) throws -> CoreConformanceCase {
    let arguments = ["-workers", "1", "-fp", "1"]
    return try CoreConformanceCase(
      id: id, moduleSHA256: SHA256.hex(Data(contentsOf: module)), cfgSHA256: SHA256.hex(Data(contentsOf: configuration)),
      arguments: arguments, argumentsSHA256: try CoreConformanceCase.argumentsDigest(arguments), workers: 1,
      fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: architecture, environment: [:], pin: pin)
  }

  private func request(context: TLCContext, module: URL, configuration: URL, work: URL, declared: CoreConformanceCase, runID: UUID) throws -> TLCProcessRequest {
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
    return TLCProcessRequest(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: declared.arguments, expectedCase: declared, runID: runID, referencePin: declared.pin, referenceArtifacts: context.artifacts)
  }

  private func writeGraphSummary(stateCount: Int, to url: URL) throws {
    try ConformanceEvidence.writeJSON(["stateCount": stateCount], to: url)
  }

  private func symmetryPermutations(scope: Int) throws -> [SymmetryPermutation] {
    let names = try symmetryMemberNames(scope: scope)
    var permutations = [try SymmetryPermutation(constantMapping: Dictionary(uniqueKeysWithValues: names.map { ($0, $0) }))]
    for index in names.indices.dropFirst() {
      var mapping = Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
      mapping[names[0]] = names[index]
      mapping[names[index]] = names[0]
      permutations.append(try SymmetryPermutation(constantMapping: mapping))
    }
    return permutations
  }

  private func reducedRun(_ raw: CanonicalRun, permutations: [SymmetryPermutation]) throws -> CanonicalRun {
    let derivation = try SymmetryOrbitDerivation(states: Array(raw.graph.states.values), permutations: permutations)
    let table = Dictionary(uniqueKeysWithValues: raw.graph.states.map { ($0.key, $0.value) })
    let representatives = try derivation.orbits.map { orbit -> CanonicalState in
      guard let state = table[orbit[0]] else { throw SymmetryOrbitAdapterError.incompleteOrbit(orbit[0].canonicalEncoding) }
      return state
    }
    let initial = try Set(raw.graph.initialStateKeys.compactMap { derivation.representativeForState[$0] }).map { key -> CanonicalState in
      guard let state = table[key] else { throw SymmetryOrbitAdapterError.incompleteOrbit(key.canonicalEncoding) }
      return state
    }
    let edges = Set(raw.graph.edgeOccurrences.keys.compactMap { edge -> CanonicalEdge? in
      guard let source = derivation.representativeForState[edge.source],
            let target = derivation.representativeForState[edge.target] else { return nil }
      return CanonicalEdge(source: source, action: edge.action, target: target)
    })
    guard initial.count == raw.graph.initialStateKeys.count, edges.isEmpty == false else {
      throw ConformanceGovernanceError.invalidField(record: "symmetry quotient", field: "initial state or transitions")
    }
    return try CanonicalRun(
      graph: CanonicalGraph(initialStates: initial, states: representatives, edges: Array(edges)),
      observableActions: Set(edges.map(\.action)), outcome: raw.outcome)
  }

  private func symmetryExploration(
    _ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID, _ run: CanonicalRun,
    _ configurationSHA256: String, _ graphURL: URL, _ projectRoot: URL
  ) throws -> SymmetryExploration {
    try SymmetryExploration(
      engine: engine, reduced: reduced, runID: runID,
      graphID: CanonicalGraphReceipt.graphRecordDigest(for: run.graph),
      initialStateIDs: run.graph.initialStateKeys.map(\.canonicalEncoding), stateIDs: run.graph.states.keys.map(\.canonicalEncoding),
      transitions: try run.graph.edgeOccurrences.map {
        try SymmetryRawTransitionWitness(
          engine: engine,
          sourceStateID: $0.key.source.canonicalEncoding,
          action: $0.key.action,
          targetStateID: $0.key.target.canonicalEncoding,
          occurrences: $0.value
        )
      }, declaredConfigurationSHA256: configurationSHA256, graphEvidence: try ConformanceEvidence.reference(for: graphURL, beneath: projectRoot),
      invariantOutcome: .notApplicable, deadlockOutcome: .notApplicable)
  }

  private func temporalResult(
    compilation: CompiledSpecification,
    declaredCase: TemporalSymmetryCase,
    model: TemporalSymmetryModelDefinition,
    exploration: ModelExplorationResult,
    swiftRun: CanonicalRun,
    correlation: TemporalSymmetryCaseRunCorrelation,
    inputs: URL,
    projectRoot: URL
  ) throws -> TemporalPropertyResult {
    guard model.spec.temporalProperties.isEmpty == false else {
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "temporal property")
    }
    let analyses = LivenessChecker(
      compilation: compilation,
      graph: exploration.graph
    ).analyze(
      initialStateIDs: exploration.initialStateIDs,
      isComplete: exploration.isComplete
    )
    guard let analysis = analyses.first else {
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "compiled temporal property")
    }
    let resultURL = inputs.appendingPathComponent("swift-result.json")
    let enablednessURL = inputs.appendingPathComponent("enabledness.json")
    try ConformanceEvidence.writeJSON([
      "caseID": declaredCase.id,
      "correlation": correlation.tlcRunID.uuidString.lowercased(),
      "status": String(describing: analysis.status),
      "graphID": CanonicalGraphReceipt.graphRecordDigest(for: swiftRun.graph)
    ], to: resultURL)
    try ConformanceEvidence.writeJSON([
      "caseID": declaredCase.id,
      "enabledActions": analysis.enabledActions.mapValues { states in
        states.mapKeys { "s\($0.id)" }.mapValues { $0 }
      }
    ], to: enablednessURL)
    let initial = swiftRun.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
    switch analysis.status {
    case .satisfied:
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .satisfied,
        graphID: CanonicalGraphReceipt.graphRecordDigest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .notApplicable)
    case .violated:
      guard let witness = analysis.witness else {
        throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "Swift lasso")
      }
      let keys = try stateKeys(exploration)
      let cycle = witness.cycle.map { keys[$0] ?? "" }
      guard !cycle.contains("") else {
        throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "Swift lasso state")
      }
      let closedCycle = cycle.first == cycle.last ? cycle : cycle + [cycle[0]]
      let lasso = try TemporalLassoWitness(
        prefixStateIDs: witness.prefix.compactMap { keys[$0] }, cycleStateIDs: closedCycle)
      let traceURL = inputs.appendingPathComponent("swift-lasso.json")
      try ConformanceEvidence.writeCanonical(lasso, to: traceURL)
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .violated,
        graphID: CanonicalGraphReceipt.graphRecordDigest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .available, traceEvidence: try ConformanceEvidence.reference(for: traceURL, beneath: projectRoot), lasso: lasso)
    case .unavailable:
      return try TemporalPropertyResult(
        availability: .unavailable, outcome: nil,
        graphID: CanonicalGraphReceipt.graphRecordDigest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .unavailable)
    }
  }

  private func stateKeys(_ exploration: ModelExplorationResult) throws -> [StateGraph.StateID: String] {
    Dictionary(uniqueKeysWithValues: exploration.graph.states.map { id, projection in
      let bindings = try Dictionary(
        uniqueKeysWithValues: projection.entries.map { entry in
          (entry.token.description, try CanonicalValue(entry.value))
        })
      return (id, CanonicalState(bindings: bindings).key.canonicalEncoding)
    })
  }

  private func configurationURL(for declaredCase: TemporalSymmetryCase, projectRoot: URL) throws -> URL {
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
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "TLC configuration")
    }
    return projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/temporal/\(name)")
  }

}

private struct TLCContext {
  let architecture: String
  let java: URL
  let jar: URL
  let bridgeClasses: URL
  let artifacts: TLCReferenceArtifacts

  init(toolRoot: URL, projectRoot: URL, pin: TLCReferencePin) throws {
    let armJava = toolRoot.appendingPathComponent("java-arm64/Contents/Home/bin/java")
    architecture = FileManager.default.fileExists(atPath: armJava.path) ? "arm64" : "x86_64"
    java = toolRoot.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
    jar = toolRoot.appendingPathComponent("downloads/tla2tools.jar")
    bridgeClasses = toolRoot.appendingPathComponent("bridge-classes")
    let archive = toolRoot.appendingPathComponent("downloads/temurin-\(architecture).tar.gz")
    let source = projectRoot.appendingPathComponent("Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java")
    let binary = bridgeClasses.appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/")).appendingPathExtension("class")
    artifacts = try TLCReferenceInspector.inspect(
      artifacts: TLCReferenceArtifacts(
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

public struct TemporalSymmetryModelDefinition: Sendable {
  public let spec: TLASpec
  public let expectedStateCount: Int
  public let maxStates: Int
}

private func symmetryMemberNames(scope: Int) throws -> [String] {
  let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
  guard (1...alphabet.count).contains(scope) else {
    throw ConformanceGovernanceError.invalidField(
      record: "symmetric collection", field: "scope")
  }
  return alphabet.prefix(scope).map(String.init)
}

public enum TemporalSymmetryModelCatalog {
  public static func model(for declaredCase: TemporalSymmetryCase) throws -> TemporalSymmetryModelDefinition? {
    switch declaredCase.swiftSpec {
    case "TemporalMatrix":
      return temporalMatrix(configuration: declaredCase.configuration)
    case "SymmetricCollectionScope2":
      return try symmetricCollection(scope: 2)
    case "SymmetricCollectionScope3":
      return try symmetricCollection(scope: 3)
    case "SymmetricCollectionScope4":
      return try symmetricCollection(scope: 4)
    default:
      return nil
    }
  }

  private static func temporalMatrix(
    configuration: TemporalSymmetryConfiguration
  ) -> TemporalSymmetryModelDefinition? {
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

  private static func fairness(_ fairness: TemporalFairnessMode?) -> [FairnessCondition] {
    switch fairness {
    case .weak: return [.weakFairness("A")]
    case .strong: return [.strongFairness("A")]
    case .some(.none), nil: return []
    }
  }

  private static func symmetricCollection(scope: Int) throws -> TemporalSymmetryModelDefinition {
    let members = try symmetryMemberNames(scope: scope).map(TLAValue.constant)
    let memberSet = StateExpr.setLiteral(members.map(StateExpr.value))
    let choose = ActionExpr.existsAction(
      "m", memberSet,
      .assign(.named("chosen"), .union(.variable("chosen"), .setLiteral([.variable("m")])))
    )
    let spec = TLASpec(
      name: "SymmetricCollectionScope\(scope)",
      variables: [NamedVar(name: "chosen", initial: .set([]))],
      actions: [NamedAction(name: "Choose", body: choose)],
      invariants: [])
    return .init(spec: spec, expectedStateCount: 1 << scope, maxStates: 1 << (scope + 1))
  }
}
