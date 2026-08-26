import Foundation
import SwiftTLA

package struct TemporalSymmetryCaseOutcome: Equatable, Sendable {
  package let caseID: String
  package let outcome: TemporalSymmetryOutcome
  package let diagnostic: String

  package init(
    caseID: String,
    outcome: TemporalSymmetryOutcome,
    diagnostic: String
  ) throws {
    guard !caseID.isEmpty, !diagnostic.isEmpty else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "case run")
    }
    self.caseID = caseID
    self.outcome = outcome
    self.diagnostic = diagnostic
  }
}

package struct TemporalSymmetryCheckRequest: Sendable {
  package let cases: TemporalSymmetryCases
  package let runID: UUID
  package let projectRoot: URL
  package let outputDirectory: URL
  package let toolRoot: URL
  package let referencePin: TLCReferencePin

  package init(
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

package struct TemporalSymmetryCheck: Sendable {
  package init() {}

  @discardableResult
  package func run(_ input: TemporalSymmetryCheckRequest) throws -> [TemporalSymmetryCaseOutcome] {
    let root = try RetainedEvidence.projectRoot(input.projectRoot)
    let output = try RetainedEvidence.outputDirectory(input.outputDirectory, beneath: root)
    return try input.cases.cases.map { temporalCase in
      let directory = output.appendingPathComponent(temporalCase.id, isDirectory: true)
      let outcome: TemporalSymmetryOutcome
      let code: String
      let model = try TemporalSymmetryModelCatalog.model(for: temporalCase)
      let compilation = try model.spec.compile()
          let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: model.maxStates)
          ).explore()
          guard exploration.graph.states.count == model.expectedStateCount else {
            throw EvidenceFormatError.invalidField(
              record: temporalCase.id, field: "bounded Swift graph expectation")
          }
          if temporalCase.kind == .temporal {
            do {
              let result = try captureTemporal(
                compilation: compilation, temporalCase: temporalCase,
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
                compilation: compilation, model: model, temporalCase: temporalCase, runID: input.runID,
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
      let record = try TemporalSymmetryCaseOutcome(
        caseID: temporalCase.id,
        outcome: outcome,
        diagnostic: code)
      return record
    }
  }

  private func captureTemporal(
    compilation: CompiledSpecification,
    temporalCase: TemporalSymmetryCase,
    model: TemporalSymmetryModelDefinition,
    exploration: ModelExplorationResult,
    runID: UUID,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TLCTemporalCaptureResult {
    let swiftRun = try SwiftGraphExporter().export(exploration)
    let correlation = try TemporalSymmetryRunReferences(
      caseID: temporalCase.id, runID: runID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let inputs = evidenceRoot.appendingPathComponent("swift-inputs", isDirectory: true)
      .appendingPathComponent(temporalCase.id, isDirectory: true)
    try RetainedEvidence.createDirectory(inputs, beneath: projectRoot)
    let swiftResult = try temporalResult(
      compilation: compilation, temporalCase: temporalCase, model: model, exploration: exploration, swiftRun: swiftRun,
      correlation: correlation, inputs: inputs, projectRoot: projectRoot)
    let swiftEvidence = try RetainedEvidence.reference(
      for: inputs.appendingPathComponent("swift-result.json"), beneath: projectRoot)
    let casesURL = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let toolchainURL = projectRoot.appendingPathComponent("Verification/FiniteGraph/toolchain.json")
    let context = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(temporalCase.id)
    try RetainedEvidence.createDirectory(work, beneath: projectRoot)
    guard let sourceInput = temporalCase.sourceInput else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "temporal source input")
    }
    let source = try RetainedEvidence.resolve(
      projectRoot.appendingPathComponent(sourceInput.path), beneath: projectRoot)
    let config = try configurationURL(for: temporalCase, projectRoot: projectRoot)
    let bundle = try TLCProcessRequest.declaredBundle(root: source, configuration: config)
    let arguments = ["-workers", "1", "-fp", "1"]
    let launch = try FiniteGraphCase(
      id: temporalCase.id,
      moduleSHA256: sourceInput.sha256,
      cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: arguments,
      argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
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
    if let graphPass = temporalCase.configuration.completeGraphPass {
      let graphConfig = try RetainedEvidence.resolve(
        projectRoot.appendingPathComponent(graphPass.configuration.path), beneath: projectRoot)
      let graphBundle = try TLCProcessRequest.declaredBundle(root: source, configuration: graphConfig)
      let graphCase = try FiniteGraphCase(
        id: temporalCase.id, moduleSHA256: sourceInput.sha256,
        cfgSHA256: graphPass.configuration.sha256,
        arguments: arguments,
        argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
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
      temporalCase: temporalCase, referencePin: referencePin, correlation: correlation, request: request,
      completeGraphRequest: completeGraphRequest, swiftRun: swiftRun, swiftResult: swiftResult,
      swiftEvidence: swiftEvidence,
      allowsImplicitStuttering: temporalCase.configuration.allowsImplicitStuttering,
      manifest: try RetainedEvidence.reference(for: casesURL, beneath: projectRoot), manifestURL: casesURL,
      toolchain: try RetainedEvidence.reference(for: toolchainURL, beneath: projectRoot), toolchainURL: toolchainURL,
      sourceInputURL: source, outputDirectory: outputDirectory,
      relativeOutputDirectory: try RetainedEvidence.relativePath(for: outputDirectory, beneath: projectRoot)))
  }

  private func captureSymmetry(
    compilation: CompiledSpecification,
    model: TemporalSymmetryModelDefinition,
    temporalCase: TemporalSymmetryCase,
    runID: UUID,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TemporalSymmetryOutcome {
    guard let scope = temporalCase.configuration.symmetryScope else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "symmetry scope")
    }
    let context = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    try RetainedEvidence.createDirectory(outputDirectory, beneath: projectRoot)
    let correlation = try TemporalSymmetryRunReferences(
      caseID: temporalCase.id, runID: runID, swiftRunID: UUID(), tlcRunID: UUID(), comparisonRunID: UUID())
    let reducedRunID = UUID()
    let rawBundle = try compilation.renderedTLAModuleBundle(usesSymmetryReduction: false)
    let reducedBundle = try compilation.renderedTLAModuleBundle(usesSymmetryReduction: true)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(temporalCase.id, isDirectory: true)
    try RetainedEvidence.createDirectory(work, beneath: projectRoot)
    let rawCase = try launchCase(
      id: temporalCase.id, bundle: rawBundle, pin: referencePin, architecture: context.architecture)
    let reducedCase = try launchCase(
      id: temporalCase.id, bundle: reducedBundle, pin: referencePin, architecture: context.architecture)
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
    let swiftRaw = try SwiftGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: explorationConfiguration,
      usesSymmetryReduction: false
    ).explore())
    let swiftReduced = try SwiftGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: explorationConfiguration,
      usesSymmetryReduction: true
    ).explore())
    guard model.spec.symmetricCollections.count == 1,
          let collection = model.spec.symmetricCollections.first,
          collection.verificationScope == scope else {
      throw EvidenceFormatError.invalidField(
        record: temporalCase.id, field: "symmetric collection")
    }
    let permutations = try symmetryPermutations(members: collection.metadata.members)
    let configurationURL = outputDirectory.appendingPathComponent("symmetry-configuration.json")
    try RetainedEvidence.writeJSON([
      "raw": SHA256.hex(Data(rawBundle.cfg.utf8)),
      "reduced": SHA256.hex(Data(reducedBundle.cfg.utf8))
    ], to: configurationURL)
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.jsonl")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.jsonl")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.jsonl")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.jsonl")
    let configurationDigest = SHA256.hex(try Data(contentsOf: configurationURL))
    let swiftReducedRunID = UUID()
    try CanonicalGraphRecords.write(swiftRaw, to: rawSwiftURL)
    try CanonicalGraphRecords.write(swiftReduced, to: reducedSwiftURL)
    try CanonicalGraphRecords.write(rawTLC, to: rawTLCURL)
    try CanonicalGraphRecords.write(reducedTLC, to: reducedTLCURL)
    let input = try SymmetryOrbitComparisonInput(
      caseID: temporalCase.id, configuration: temporalCase.configuration, correlation: correlation,
      swiftRaw: try symmetryExploration(.swift, false, correlation.swiftRunID, swiftRaw, configurationDigest, rawSwiftURL, projectRoot),
      swiftReduced: try symmetryExploration(.swift, true, swiftReducedRunID, swiftReduced, configurationDigest, reducedSwiftURL, projectRoot),
      tlcRaw: try symmetryExploration(.tlc, false, correlation.tlcRunID, rawTLC, configurationDigest, rawTLCURL, projectRoot),
      tlcReduced: try symmetryExploration(.tlc, true, reducedRunID, reducedTLC, configurationDigest, reducedTLCURL, projectRoot),
      swiftRawRun: swiftRaw, swiftReducedRun: swiftReduced, tlcRawRun: rawTLC, tlcReducedRun: reducedTLC,
      configurationEvidence: try RetainedEvidence.reference(for: configurationURL, beneath: projectRoot),
      quotientEvidence: try RetainedEvidence.reference(for: reducedSwiftURL, beneath: projectRoot), permutations: permutations)
    switch try SymmetryOrbitComparator().compare(input) {
    case .exact(let comparison):
      try RetainedEvidence.writeCanonical(
        comparison, to: outputDirectory.appendingPathComponent("symmetry-orbit-comparison.json"))
      return .exact
    case .difference(let differences):
      try RetainedEvidence.writeCanonical(
        differences, to: outputDirectory.appendingPathComponent("symmetry-differences.json"))
      return .difference
    }
  }

}

extension TemporalSymmetryCheck {
  private func validateSymmetryRequests(raw: TLCProcessRequest, reduced: TLCProcessRequest) throws {
    guard raw.caseID == reduced.caseID,
          raw.runID != reduced.runID,
          raw.expectedCase.moduleSHA256 == reduced.expectedCase.moduleSHA256,
          raw.expectedCase.pin == reduced.expectedCase.pin,
          raw.bundle.root.name == reduced.bundle.root.name,
          raw.bundle.root.tla == reduced.bundle.root.tla,
          raw.bundle.imports == reduced.bundle.imports,
          raw.bundle.root.cfg != reduced.bundle.root.cfg else {
      throw EvidenceFormatError.inconsistentReference(
        record: raw.caseID, field: "pinned TLC raw/reduced pair")
    }
  }

  private func launchCase(
    id: String,
    bundle: TLAModuleBundle,
    pin: TLCReferencePin,
    architecture: String
  ) throws -> FiniteGraphCase {
    let arguments = ["-workers", "1", "-fp", "1"]
    guard let configuration = bundle.root.cfg else {
      throw EvidenceFormatError.invalidField(record: id, field: "TLC configuration")
    }
    return try FiniteGraphCase(
      id: id, moduleSHA256: SHA256.hex(Data(bundle.root.tla.utf8)), cfgSHA256: SHA256.hex(Data(configuration.utf8)),
      arguments: arguments, argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments), workers: 1,
      fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: architecture, environment: [:], pin: pin)
  }

  private func request(
    context: ResolvedTLCToolchain,
    bundle: TLAModuleBundle,
    work: URL,
    declared: FiniteGraphCase,
    runID: UUID,
    projectRoot: URL
  ) throws -> TLCProcessRequest {
    try RetainedEvidence.createDirectory(work, beneath: projectRoot)
    return TLCProcessRequest(
      javaExecutable: context.java, jar: context.jar, bridgeClasses: context.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      replayInput: work.appendingPathComponent("replay-input.json"), workingDirectory: work,
      arguments: declared.arguments, expectedCase: declared, runID: runID, referencePin: declared.pin, referenceArtifacts: context.artifacts)
  }

  private func symmetryPermutations(members: [TLAValue]) throws -> [SymmetryPermutation] {
    let names = try members.map { member in
      guard case .constant(let name) = member else {
        throw EvidenceFormatError.invalidField(
          record: "symmetric collection", field: "member")
      }
      return name
    }
    guard names.isEmpty == false else {
      throw EvidenceFormatError.invalidField(
        record: "symmetric collection", field: "members")
    }
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
    _ engine: SymmetryExplorationEngine, _ reduced: Bool, _ runID: UUID, _ run: CompletedGraphRun,
    _ configurationSHA256: String, _ graphURL: URL, _ projectRoot: URL
  ) throws -> SymmetryExploration {
    try SymmetryExploration(
      engine: engine, reduced: reduced, runID: runID,
      graphID: try CanonicalGraphRecords.digest(for: run.graph),
      initialStateIDs: run.graph.initialStateKeys.map(\.canonicalEncoding), stateIDs: run.graph.states.keys.map(\.canonicalEncoding),
      transitions: try run.graph.edgeOccurrences.map {
        try SymmetryRawTransitionWitness(
          engine: engine,
          sourceStateID: $0.key.source.canonicalEncoding,
          action: $0.key.action,
          targetStateID: $0.key.target.canonicalEncoding,
          occurrences: $0.value
        )
      }, declaredConfigurationSHA256: configurationSHA256, graphEvidence: try RetainedEvidence.reference(for: graphURL, beneath: projectRoot),
      invariantOutcome: .notApplicable, deadlockOutcome: .notApplicable)
  }

  private func temporalResult(
    compilation: CompiledSpecification,
    temporalCase: TemporalSymmetryCase,
    model: TemporalSymmetryModelDefinition,
    exploration: ModelExplorationResult,
    swiftRun: CompletedGraphRun,
    correlation: TemporalSymmetryRunReferences,
    inputs: URL,
    projectRoot: URL
  ) throws -> TemporalPropertyResult {
    guard model.spec.temporalProperties.isEmpty == false else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "temporal property")
    }
    let analyses = exploration.analyzeTemporalProperties(in: compilation)
    guard let analysis = analyses.first else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "compiled temporal property")
    }
    let resultURL = inputs.appendingPathComponent("swift-result.json")
    try RetainedEvidence.writeJSON([
      "caseID": temporalCase.id,
      "correlation": correlation.tlcRunID.uuidString.lowercased(),
      "status": String(describing: analysis.status),
      "graphID": try CanonicalGraphRecords.digest(for: swiftRun.graph)
    ], to: resultURL)
    let initial = swiftRun.graph.initialStateKeys.sorted().map(\.canonicalEncoding)
    switch analysis.status {
    case .satisfied:
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .satisfied,
        graphID: try CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .notApplicable)
    case .violated:
      guard let witness = analysis.witness else {
        throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "Swift lasso")
      }
      let keys = try stateKeys(exploration)
      let cycle = witness.cycle.map { keys[$0] ?? "" }
      guard !cycle.contains("") else {
        throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "Swift lasso state")
      }
      let closedCycle = cycle.first == cycle.last ? cycle : cycle + [cycle[0]]
      let lasso = try TemporalLassoWitness(
        prefixStateIDs: witness.prefix.compactMap { keys[$0] }, cycleStateIDs: closedCycle)
      let traceURL = inputs.appendingPathComponent("swift-lasso.json")
      try RetainedEvidence.writeCanonical(lasso, to: traceURL)
      return try TemporalPropertyResult(
        availability: .evaluated, outcome: .violated,
        graphID: try CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
        traceAvailability: .available, traceEvidence: try RetainedEvidence.reference(for: traceURL, beneath: projectRoot), lasso: lasso)
    case .unavailable:
      return try TemporalPropertyResult(
        availability: .unavailable, outcome: nil,
        graphID: try CanonicalGraphRecords.digest(for: swiftRun.graph), initialStateIDs: initial,
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

  private func configurationURL(for temporalCase: TemporalSymmetryCase, projectRoot: URL) throws -> URL {
    let names = [
      "temporal-always-none": "always-none.cfg",
      "temporal-eventually-none": "eventually-none.cfg",
      "temporal-always-eventually-none": "always-eventually-none.cfg",
      "temporal-eventually-always-weak": "eventually-always-weak.cfg",
      "temporal-leads-to-strong": "leads-to-strong.cfg",
      "temporal-weak-fairness-boundary": "weak-boundary.cfg",
      "temporal-strong-fairness-boundary": "strong-boundary.cfg"
    ]
    guard let name = names[temporalCase.id] else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "TLC configuration")
    }
    return projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/fixtures/temporal/\(name)")
  }

}

private struct ResolvedTLCToolchain {
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

package struct TemporalSymmetryModelDefinition: Sendable {
  package let spec: TLASpec
  package let expectedStateCount: Int
  package let maxStates: Int
}

private struct ConformanceMember: Identifiable, Sendable {
  let id: Int
}

package enum TemporalSymmetryModelCatalog {
  package static func model(for temporalCase: TemporalSymmetryCase) throws -> TemporalSymmetryModelDefinition {
    switch temporalCase.swiftSpec {
    case "TemporalMatrix":
      return try temporalMatrix(configuration: temporalCase.configuration)
    case "SymmetricCollectionScope2":
      return try symmetricCollection(scope: 2)
    case "SymmetricCollectionScope3":
      return try symmetricCollection(scope: 3)
    case "SymmetricCollectionScope4":
      return try symmetricCollection(scope: 4)
    case "SymmetricCollectionScope5":
      return try symmetricCollection(scope: 5)
    default:
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "Swift model")
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
      throw EvidenceFormatError.invalidField(record: property ?? "", field: "temporal property")
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
