import Foundation
import SwiftTLA

public struct TemporalSymmetryCaseRun: Equatable, Sendable {
  public let caseID: String
  public let outcome: TemporalSymmetryOutcome
  public let diagnostic: String

  public init(
    caseID: String,
    outcome: TemporalSymmetryOutcome,
    diagnostic: String
  ) throws {
    guard !caseID.isEmpty, !diagnostic.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "case run")
    }
    self.caseID = caseID
    self.outcome = outcome
    self.diagnostic = diagnostic
  }
}

public struct TemporalSymmetryConformanceRunnerInput: Sendable {
  public let cases: TemporalSymmetryCases
  public let runID: UUID
  public let projectRoot: URL
  public let outputDirectory: URL
  public let toolRoot: URL
  public let referencePin: TLCReferencePin

  public init(
    cases: TemporalSymmetryCases,
    runID: UUID,
    projectRoot: URL,
    outputDirectory: URL,
    toolRoot: URL,
    referencePin: TLCReferencePin
  ) {
    self.cases = cases
    self.runID = runID
    self.projectRoot = projectRoot
    self.outputDirectory = outputDirectory
    self.toolRoot = toolRoot
    self.referencePin = referencePin
  }
}

public struct TemporalSymmetryConformanceRunner: Sendable {
  public init() {}

  @discardableResult
  public func run(_ input: TemporalSymmetryConformanceRunnerInput) throws -> [TemporalSymmetryCaseRun] {
    let root = try ConformanceEvidence.projectRoot(input.projectRoot)
    let output = try ConformanceEvidence.outputDirectory(input.outputDirectory, beneath: root)
    return try input.cases.cases.map { declaredCase in
      let directory = output.appendingPathComponent(declaredCase.id, isDirectory: true)
      let outcome: TemporalSymmetryOutcome
      let code: String
      let model = try TemporalSymmetryModelCatalog.model(for: declaredCase)
      let compilation = try model.spec.compile()
          let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
          ).explore()
          guard exploration.graph.states.count == model.expectedStateCount else {
            throw ConformanceGovernanceError.invalidField(
              record: declaredCase.id, field: "bounded Swift graph expectation")
          }
          if declaredCase.kind == .temporal {
            do {
              let result = try captureTemporal(
                compilation: compilation, declaredCase: declaredCase,
                model: model,
                exploration: exploration,
                runID: input.runID,
                toolRoot: input.toolRoot,
                referencePin: input.referencePin,
                projectRoot: root,
                evidenceRoot: output,
                outputDirectory: directory)
              outcome = result.comparison?.outcome ?? .unavailable
              code = result.diagnostic?.code ?? "captured"
            } catch {
              outcome = .unavailable
              code = "pinned-tlc-runtime-unavailable: \(String(describing: error))"
            }
          } else {
            do {
              let result = try captureSymmetry(
                compilation: compilation, model: model, declaredCase: declaredCase, runID: input.runID,
                toolRoot: input.toolRoot, referencePin: input.referencePin,
                projectRoot: root, evidenceRoot: output,
                outputDirectory: directory)
              outcome = result
              code = result == .exact ? "exact" : "symmetry-comparison-difference"
            } catch {
              outcome = .unavailable
              code = "pinned-tlc-symmetry-unavailable: \(String(describing: error))"
            }
          }
      let record = try TemporalSymmetryCaseRun(
        caseID: declaredCase.id,
        outcome: outcome,
        diagnostic: code)
      return record
    }
  }

  private func captureTemporal(
    compilation: CompiledSpecification,
    declaredCase: TemporalSymmetryCase,
    model: TemporalSymmetryModelDefinition,
    exploration: ModelExplorationResult,
    runID: UUID,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TLCTemporalCaptureResult {
    let swiftRun = try SwiftGraphAdapter().adapt(exploration)
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: declaredCase.id, runID: runID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let inputs = evidenceRoot.appendingPathComponent("swift-inputs", isDirectory: true)
      .appendingPathComponent(declaredCase.id, isDirectory: true)
    try ConformanceEvidence.createDirectory(inputs, beneath: projectRoot)
    let swiftResult = try temporalResult(
      compilation: compilation, declaredCase: declaredCase, model: model, exploration: exploration, swiftRun: swiftRun,
      correlation: correlation, inputs: inputs, projectRoot: projectRoot)
    let swiftEvidence = try ConformanceEvidence.reference(
      for: inputs.appendingPathComponent("swift-result.json"), beneath: projectRoot)
    let casesURL = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let toolchainURL = projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json")
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id)
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
    guard let sourceInput = declaredCase.sourceInput else {
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "temporal source input")
    }
    let source = try ConformanceEvidence.resolve(
      projectRoot.appendingPathComponent(sourceInput.path), beneath: projectRoot)
    let config = try configurationURL(for: declaredCase, projectRoot: projectRoot)
    let bundle = try TLCProcessRequest.declaredBundle(root: source, configuration: config)
    let arguments = ["-workers", "1", "-fp", "1"]
    let launch = try CoreConformanceCase(
      id: declaredCase.id,
      moduleSHA256: sourceInput.sha256,
      cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: arguments,
      argumentsSHA256: try CoreConformanceCase.argumentsDigest(arguments),
      workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
      architecture: context.architecture, environment: [:], pin: referencePin)
    let request = TLCProcessRequest(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: arguments, expectedCase: launch,
      runID: correlation.tlcRunID, referencePin: referencePin, referenceArtifacts: context.artifacts)
    let completeGraphRequest: TLCProcessRequest?
    if let graphPass = declaredCase.configuration.completeGraphPass {
      let graphConfig = try ConformanceEvidence.resolve(
        projectRoot.appendingPathComponent(graphPass.configuration.path), beneath: projectRoot)
      let graphBundle = try TLCProcessRequest.declaredBundle(root: source, configuration: graphConfig)
      let graphCase = try CoreConformanceCase(
        id: declaredCase.id, moduleSHA256: sourceInput.sha256,
        cfgSHA256: graphPass.configuration.sha256,
        arguments: arguments,
        argumentsSHA256: try CoreConformanceCase.argumentsDigest(arguments),
        workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos",
        architecture: context.architecture, environment: [:], pin: referencePin)
      completeGraphRequest = TLCProcessRequest(
        javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
        bundle: graphBundle,
        graphEvents: work.appendingPathComponent("complete-graph-events.jsonl"),
        traceOutput: work.appendingPathComponent("complete-graph-counterexample.json"),
        replayInput: work.appendingPathComponent("complete-graph-replay.json"), workingDirectory: work,
        arguments: graphCase.arguments, expectedCase: graphCase, runID: UUID(),
        referencePin: referencePin, referenceArtifacts: context.artifacts)
    } else {
      completeGraphRequest = nil
    }
    return TLCTemporalAdapter().capture(TLCTemporalCaptureInput(
      declaredCase: declaredCase, referencePin: referencePin, correlation: correlation, request: request,
      completeGraphRequest: completeGraphRequest, swiftRun: swiftRun, swiftResult: swiftResult,
      swiftEvidence: swiftEvidence,
      allowsImplicitStuttering: declaredCase.configuration.allowsImplicitStuttering,
      manifest: try ConformanceEvidence.reference(for: casesURL, beneath: projectRoot), manifestURL: casesURL,
      toolchain: try ConformanceEvidence.reference(for: toolchainURL, beneath: projectRoot), toolchainURL: toolchainURL,
      sourceInputURL: source, outputDirectory: outputDirectory,
      relativeOutputDirectory: try ConformanceEvidence.relativePath(for: outputDirectory, beneath: projectRoot)))
  }

  private func captureSymmetry(
    compilation: CompiledSpecification,
    model: TemporalSymmetryModelDefinition,
    declaredCase: TemporalSymmetryCase,
    runID: UUID,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TemporalSymmetryOutcome {
    guard let scope = declaredCase.configuration.symmetryScope else {
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "symmetry scope")
    }
    let context = try TLCContext(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    try ConformanceEvidence.createDirectory(outputDirectory, beneath: projectRoot)
    let correlation = try TemporalSymmetryCaseRunCorrelation(
      caseID: declaredCase.id, runID: runID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let reducedRunID = UUID()
    let rawBundle = try compilation.renderedTLAModuleBundle(usesSymmetryReduction: false)
    let reducedBundle = try compilation.renderedTLAModuleBundle(usesSymmetryReduction: true)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(declaredCase.id, isDirectory: true)
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
    let rawCase = try launchCase(
      id: declaredCase.id, bundle: rawBundle, pin: referencePin, architecture: context.architecture)
    let reducedCase = try launchCase(
      id: declaredCase.id, bundle: reducedBundle, pin: referencePin, architecture: context.architecture)
    let rawRequest = try request(
      context: context, bundle: rawBundle, work: work.appendingPathComponent("raw"),
      declared: rawCase, runID: correlation.tlcRunID, projectRoot: projectRoot)
    let reducedRequest = try request(
      context: context, bundle: reducedBundle, work: work.appendingPathComponent("reduced"),
      declared: reducedCase, runID: reducedRunID, projectRoot: projectRoot)
    try validateSymmetryRequests(raw: rawRequest, reduced: reducedRequest)
    let processAdapter = TLCProcessAdapter()
    let rawTLC = try processAdapter.capture(
      rawRequest, replay: .none,
      retainingIn: outputDirectory.appendingPathComponent("tlc-raw", isDirectory: true)).graph
    let reducedTLC = try processAdapter.capture(
      reducedRequest, replay: .none,
      retainingIn: outputDirectory.appendingPathComponent("tlc-reduced", isDirectory: true)).graph
    let explorationConfiguration = try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
    let swiftRaw = try SwiftGraphAdapter().adapt(ModelChecker(
      compilation: compilation,
      configuration: explorationConfiguration,
      usesSymmetryReduction: false
    ).explore())
    let swiftReduced = try SwiftGraphAdapter().adapt(ModelChecker(
      compilation: compilation,
      configuration: explorationConfiguration,
      usesSymmetryReduction: true
    ).explore())
    let permutations = try symmetryPermutations(scope: scope)
    let configurationURL = outputDirectory.appendingPathComponent("symmetry-configuration.json")
    try ConformanceEvidence.writeJSON([
      "raw": SHA256.hex(Data(rawBundle.cfg.utf8)),
      "reduced": SHA256.hex(Data(reducedBundle.cfg.utf8))
    ], to: configurationURL)
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.json")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.json")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.json")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.json")
    let configurationDigest = SHA256.hex(try Data(contentsOf: configurationURL))
    let swiftReducedRunID = UUID()
    try CanonicalRunEvidence.write(
      swiftRaw,
      correlation: .init(caseID: declaredCase.id, runID: correlation.swiftRunID, engine: .swift),
      to: rawSwiftURL)
    try CanonicalRunEvidence.write(
      swiftReduced,
      correlation: .init(caseID: declaredCase.id, runID: swiftReducedRunID, engine: .swift),
      to: reducedSwiftURL)
    try CanonicalRunEvidence.write(
      rawTLC,
      correlation: .init(caseID: declaredCase.id, runID: correlation.tlcRunID, engine: .tlc),
      to: rawTLCURL)
    try CanonicalRunEvidence.write(
      reducedTLC,
      correlation: .init(caseID: declaredCase.id, runID: reducedRunID, engine: .tlc),
      to: reducedTLCURL)
    let input = try SymmetryOrbitComparisonInput(
      caseID: declaredCase.id, configuration: declaredCase.configuration, correlation: correlation,
      swiftRaw: try symmetryExploration(.swift, false, correlation.swiftRunID, swiftRaw, configurationDigest, rawSwiftURL, projectRoot),
      swiftReduced: try symmetryExploration(.swift, true, swiftReducedRunID, swiftReduced, configurationDigest, reducedSwiftURL, projectRoot),
      tlcRaw: try symmetryExploration(.tlc, false, correlation.tlcRunID, rawTLC, configurationDigest, rawTLCURL, projectRoot),
      tlcReduced: try symmetryExploration(.tlc, true, reducedRunID, reducedTLC, configurationDigest, reducedTLCURL, projectRoot),
      swiftRawRun: swiftRaw, swiftReducedRun: swiftReduced, tlcRawRun: rawTLC, tlcReducedRun: reducedTLC,
      configurationEvidence: try ConformanceEvidence.reference(for: configurationURL, beneath: projectRoot),
      quotientEvidence: try ConformanceEvidence.reference(for: reducedSwiftURL, beneath: projectRoot), permutations: permutations)
    switch try SymmetryOrbitComparator().compare(input) {
    case .exact(let comparison):
      try ConformanceEvidence.writeCanonical(
        comparison, to: outputDirectory.appendingPathComponent("symmetry-orbit-comparison.json"))
      return .exact
    case .difference(let differences):
      try ConformanceEvidence.writeCanonical(
        differences, to: outputDirectory.appendingPathComponent("symmetry-differences.json"))
      return .difference
    }
  }

}

extension TemporalSymmetryConformanceRunner {
  private func validateSymmetryRequests(raw: TLCProcessRequest, reduced: TLCProcessRequest) throws {
    guard raw.caseID == reduced.caseID,
          raw.runID != reduced.runID,
          raw.expectedCase.moduleSHA256 == reduced.expectedCase.moduleSHA256,
          raw.expectedCase.pin == reduced.expectedCase.pin,
          raw.bundle.root.name == reduced.bundle.root.name,
          raw.bundle.root.tla == reduced.bundle.root.tla,
          raw.bundle.imports == reduced.bundle.imports,
          raw.bundle.root.cfg != reduced.bundle.root.cfg else {
      throw ConformanceGovernanceError.inconsistentReference(
        record: raw.caseID, field: "pinned TLC raw/reduced pair")
    }
  }

  private func launchCase(
    id: String,
    bundle: TLAModuleBundle,
    pin: TLCReferencePin,
    architecture: String
  ) throws -> CoreConformanceCase {
    let arguments = ["-workers", "1", "-fp", "1"]
    guard let configuration = bundle.root.cfg else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "TLC configuration")
    }
    return try CoreConformanceCase(
      id: id, moduleSHA256: SHA256.hex(Data(bundle.root.tla.utf8)), cfgSHA256: SHA256.hex(Data(configuration.utf8)),
      arguments: arguments, argumentsSHA256: try CoreConformanceCase.argumentsDigest(arguments), workers: 1,
      fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: architecture, environment: [:], pin: pin)
  }

  private func request(
    context: TLCContext,
    bundle: TLAModuleBundle,
    work: URL,
    declared: CoreConformanceCase,
    runID: UUID,
    projectRoot: URL
  ) throws -> TLCProcessRequest {
    try ConformanceEvidence.createDirectory(work, beneath: projectRoot)
    return TLCProcessRequest(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: declared.arguments, expectedCase: declared, runID: runID, referencePin: declared.pin, referenceArtifacts: context.artifacts)
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

  private func symmetryExploration(
    _ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID, _ run: CanonicalRun,
    _ configurationSHA256: String, _ graphURL: URL, _ projectRoot: URL
  ) throws -> SymmetryExploration {
    try SymmetryExploration(
      engine: engine, reduced: reduced, runID: runID,
      graphID: CanonicalGraphRecords.digest(for: run.graph),
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
    try ConformanceEvidence.writeJSON([
      "caseID": declaredCase.id,
      "correlation": correlation.tlcRunID.uuidString.lowercased(),
      "status": String(describing: analysis.status),
      "graphID": CanonicalGraphRecords.digest(for: swiftRun.graph)
    ], to: resultURL)
    let initial = swiftRun.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
    switch analysis.status {
    case .satisfied:
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .satisfied,
        graphID: CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
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
        graphID: CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .available, traceEvidence: try ConformanceEvidence.reference(for: traceURL, beneath: projectRoot), lasso: lasso)
    case .unavailable:
      return try TemporalPropertyResult(
        availability: .unavailable, outcome: nil,
        graphID: CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .unavailable)
    }
  }

  private func stateKeys(_ exploration: ModelExplorationResult) throws -> [StateGraph.StateID: String] {
    try Dictionary(uniqueKeysWithValues: exploration.graph.states.map { id, projection in
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

private struct ConformanceMember: Identifiable, Sendable {
  let id: Int
}

public enum TemporalSymmetryModelCatalog {
  public static func model(for declaredCase: TemporalSymmetryCase) throws -> TemporalSymmetryModelDefinition {
    switch declaredCase.swiftSpec {
    case "TemporalMatrix":
      return try temporalMatrix(configuration: declaredCase.configuration)
    case "SymmetricCollectionScope2":
      return try symmetricCollection(scope: 2)
    case "SymmetricCollectionScope3":
      return try symmetricCollection(scope: 3)
    case "SymmetricCollectionScope4":
      return try symmetricCollection(scope: 4)
    case "SymmetricCollectionScope5":
      return try symmetricCollection(scope: 5)
    default:
      throw ConformanceGovernanceError.invalidField(record: declaredCase.id, field: "Swift model")
    }
  }

  private static func temporalMatrix(
    configuration: TemporalSymmetryConfiguration
  ) throws -> TemporalSymmetryModelDefinition {
    let x = Var<Int>("x")
    let p = x == 2
    let q = x == 1
    let temporal = try temporalProperty(property: configuration.property, p: p, q: q)
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
      temporalProperties: [NamedTemporal(name: temporal.0, expr: temporal.1)],
      fairness: fairness(configuration.fairness))
    return .init(spec: spec, expectedStateCount: 3, maxStates: 10)
  }

  private static func temporalProperty(
    property: String?, p: StateExpr, q: StateExpr
  ) throws -> (String, TemporalExpr) {
    switch property {
    case "AlwaysP": return ("AlwaysP", .always(p))
    case "EventuallyP": return ("EventuallyP", .eventually(p))
    case "AlwaysEventuallyP": return ("AlwaysEventuallyP", .alwaysEventually(p))
    case "EventuallyAlwaysP": return ("EventuallyAlwaysP", .eventuallyAlways(p))
    case "LeadsToPQ": return ("LeadsToPQ", .leadsTo(p, q))
    default:
      throw ConformanceGovernanceError.invalidField(record: property ?? "", field: "temporal property")
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
    let chosen = SymmetricCollectionVar<ConformanceMember, Int>("chosen")
    let spec = TLASpec("SymmetricCollectionScope\(scope)") {
      SymmetricCollection(chosen, verificationScope: scope, initial: 0)
      CollectionAction("Choose", on: chosen) { member in
        chosen[member] == 0 && chosen.update(member, to: 1)
      }
    }
    return .init(spec: spec, expectedStateCount: scope + 1, maxStates: 1 << (scope + 1))
  }
}
