import Foundation
import SwiftTLA

package struct TemporalSymmetryCheckOutcome: Equatable, Sendable {
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
  package let manifest: TemporalSymmetryManifest
  package let projectRoot: URL
  package let outputDirectory: URL
  package let toolRoot: URL
  package let referencePin: TLCReferencePin

  package init(
    manifest: TemporalSymmetryManifest,
    projectRoot: URL,
    outputDirectory: URL,
    toolRoot: URL,
    referencePin: TLCReferencePin
  ) {
    self.manifest = manifest
    self.projectRoot = projectRoot
    self.outputDirectory = outputDirectory
    self.toolRoot = toolRoot
    self.referencePin = referencePin
  }
}

package struct TemporalSymmetryCheck: Sendable {
  package init() {}

  @discardableResult
  package func run(_ input: TemporalSymmetryCheckRequest) throws -> [TemporalSymmetryCheckOutcome] {
    let root = try RetainedFiles.projectRoot(input.projectRoot)
    let output = try RetainedFiles.outputDirectory(input.outputDirectory, beneath: root)
    let temporalOutcomes = try input.manifest.temporalCases.map { temporalCase in
      let compilation = try temporalConformanceSpec(configuration: temporalCase.configuration).compile()
      let exploration = try ModelChecker(
        compilation: compilation,
        configuration: temporalCase.exploration
      ).explore()
      let outcome: TemporalSymmetryOutcome
      let code: String
      do {
        let capture = try captureTemporal(
          compilation: compilation, temporalCase: temporalCase,
          exploration: exploration, toolRoot: input.toolRoot,
          referencePin: input.referencePin, projectRoot: root, evidenceRoot: output,
          outputDirectory: output.appendingPathComponent(temporalCase.id, isDirectory: true))
        switch capture {
        case .comparison(let comparison):
          switch comparison.status {
          case .exact: outcome = .exact
          case .propertyOutcomeDifference, .graphDifference: outcome = .difference
          case .unavailable: outcome = .unavailable
          }
          code = comparison.status.rawValue
        case .failure(let diagnostic):
          outcome = .unavailable
          code = diagnostic.code
        }
      } catch {
        outcome = .unavailable
        code = "pinned-tlc-runtime-unavailable: \(String(describing: error))"
      }
      return try TemporalSymmetryCheckOutcome(
        caseID: temporalCase.id, outcome: outcome, diagnostic: code)
    }

    let symmetryOutcomes = try input.manifest.symmetryCases.map { symmetryCase in
      let spec = symmetryConformanceSpec(scope: symmetryCase.scope)
      let compilation = try spec.compile()
      let outcome: TemporalSymmetryOutcome
      let code: String
      do {
        let result = try captureSymmetry(
          compilation: compilation, symmetryCase: symmetryCase,
          toolRoot: input.toolRoot, referencePin: input.referencePin,
          projectRoot: root, evidenceRoot: output,
          outputDirectory: output.appendingPathComponent(symmetryCase.id, isDirectory: true))
        outcome = result
        code = result == .exact ? "exact" : "symmetry-comparison-difference"
      } catch {
        outcome = .unavailable
        code = "pinned-tlc-symmetry-unavailable: \(String(describing: error))"
      }
      return try TemporalSymmetryCheckOutcome(
        caseID: symmetryCase.id, outcome: outcome, diagnostic: code)
    }
    return temporalOutcomes + symmetryOutcomes
  }

  private func captureTemporal(
    compilation: CompiledSpecification,
    temporalCase: TemporalCase,
    exploration: ModelExplorationResult,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TLCTemporalCapture {
    let swiftRun = try SwiftGraphExporter().export(exploration)
    let swiftResult = try temporalResult(
      compilation: compilation, temporalCase: temporalCase, exploration: exploration)
    let casesURL = projectRoot.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let toolchainURL = projectRoot.appendingPathComponent("Verification/FiniteGraph/toolchain.json")
    let toolchain = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(temporalCase.id)
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    let sourceInput = temporalCase.sourceInput
    let source = try RetainedFiles.resolve(
      projectRoot.appendingPathComponent(sourceInput.path), beneath: projectRoot)
    let bundle = try externalBundle(
      source: source,
      renderedConfiguration: temporalCase.configuration.renderedPropertyConfiguration)
    let arguments = ["-workers", "1", "-fp", "1"]
    let launch = try FiniteGraphCase(
      id: temporalCase.id,
      exploration: temporalCase.exploration,
      moduleSHA256: sourceInput.sha256,
      cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: arguments,
      argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
      operatingSystem: "macos",
      architecture: toolchain.architecture, environment: [:], pin: referencePin)
    let request = TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"),
      workingDirectory: work,
      finiteGraphCase: launch,
      runID: UUID(), referencePin: referencePin, referenceArtifacts: toolchain.artifacts)
    let graphBundle = try externalBundle(
      source: source,
      renderedConfiguration: TemporalCaseConfiguration.renderedGraphConfiguration)
    let graphCase = try FiniteGraphCase(
      id: temporalCase.id, exploration: temporalCase.exploration,
      moduleSHA256: sourceInput.sha256,
      cfgSHA256: SHA256.hex(Data(graphBundle.cfg.utf8)),
      arguments: arguments,
      argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
      operatingSystem: "macos",
      architecture: toolchain.architecture, environment: [:], pin: referencePin)
    let completeGraphRequest = TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: graphBundle,
      graphEvents: work.appendingPathComponent("complete-graph-events.jsonl"),
      traceOutput: work.appendingPathComponent("complete-graph-counterexample.json"),
      workingDirectory: work,
      finiteGraphCase: graphCase, runID: UUID(),
      referencePin: referencePin, referenceArtifacts: toolchain.artifacts)
    return TLCTemporalAdapter().capture(TLCTemporalCaptureInput(
      temporalCase: temporalCase, request: request,
      completeGraphRequest: completeGraphRequest, swiftRun: swiftRun, swiftResult: swiftResult,
      manifestURL: casesURL, toolchainURL: toolchainURL,
      sourceInputURL: source, outputDirectory: outputDirectory))
  }

  private func externalBundle(
    source: URL,
    renderedConfiguration: String
  ) throws -> TLAModuleBundle {
    TLAModuleBundle.external(root: TLAModuleFile(
      name: source.deletingPathExtension().lastPathComponent,
      tla: try String(contentsOf: source, encoding: .utf8),
      cfg: renderedConfiguration))
  }

  private func captureSymmetry(
    compilation: CompiledSpecification,
    symmetryCase: SymmetryCase,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TemporalSymmetryOutcome {
    let scope = symmetryCase.scope
    let toolchain = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    try RetainedFiles.createDirectory(outputDirectory, beneath: projectRoot)
    let rawRunID = UUID()
    let reducedRunID = UUID()
    let rawBundle = compilation.renderedTLAModuleBundle(
      symmetryReduction: symmetryCase.rawExploration.symmetryReduction)
    let reducedBundle = compilation.renderedTLAModuleBundle(
      symmetryReduction: symmetryCase.reducedExploration.symmetryReduction)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(symmetryCase.id, isDirectory: true)
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    let rawCase = try makeFiniteGraphCase(
      id: symmetryCase.id, exploration: symmetryCase.rawExploration,
      bundle: rawBundle, pin: referencePin, architecture: toolchain.architecture)
    let reducedCase = try makeFiniteGraphCase(
      id: symmetryCase.id, exploration: symmetryCase.reducedExploration,
      bundle: reducedBundle, pin: referencePin, architecture: toolchain.architecture)
    let rawRequest = try request(
      toolchain: toolchain, bundle: rawBundle, work: work.appendingPathComponent("raw"),
      finiteGraphCase: rawCase, runID: rawRunID, projectRoot: projectRoot)
    let reducedRequest = try request(
      toolchain: toolchain, bundle: reducedBundle, work: work.appendingPathComponent("reduced"),
      finiteGraphCase: reducedCase, runID: reducedRunID, projectRoot: projectRoot)
    try validateSymmetryRequests(raw: rawRequest, reduced: reducedRequest)
    let processAdapter = TLCProcessAdapter()
    let rawTLC = try processAdapter.capture(
      rawRequest,
      retainingIn: outputDirectory.appendingPathComponent("tlc-raw", isDirectory: true)).graph
    let reducedTLC = try processAdapter.capture(
      reducedRequest,
      retainingIn: outputDirectory.appendingPathComponent("tlc-reduced", isDirectory: true)).graph
    let swiftRaw = try SwiftGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: symmetryCase.rawExploration
    ).explore())
    let swiftReduced = try SwiftGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: symmetryCase.reducedExploration
    ).explore())
    guard compilation.machineSurfacePlan.symmetricCollections.count == 1,
          let collection = compilation.machineSurfacePlan.symmetricCollections.first,
          collection.members.count == scope else {
      throw EvidenceFormatError.invalidField(
        record: symmetryCase.id, field: "symmetric collection")
    }
    let permutations = try symmetryPermutations(members: collection.members)
    guard case .enabled(let maximumPermutationCount) = symmetryCase.reducedExploration.symmetryReduction else {
      throw EvidenceFormatError.invalidField(
        record: symmetryCase.id, field: "reduced symmetry policy")
    }
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.jsonl")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.jsonl")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.jsonl")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.jsonl")
    try CompletedGraphRunRecords.write(swiftRaw, to: rawSwiftURL)
    try CompletedGraphRunRecords.write(swiftReduced, to: reducedSwiftURL)
    try CompletedGraphRunRecords.write(rawTLC, to: rawTLCURL)
    try CompletedGraphRunRecords.write(reducedTLC, to: reducedTLCURL)
    let input = try SymmetryOrbitComparisonInput(
      caseID: symmetryCase.id,
      swiftRaw: swiftRaw,
      swiftReduced: swiftReduced,
      tlcRaw: rawTLC,
      tlcReduced: reducedTLC,
      permutations: permutations,
      maximumPermutationCount: maximumPermutationCount
    )
    switch try compareSymmetryOrbits(input) {
    case .exact(let comparison):
      try RetainedFiles.writeCanonical(
        comparison, to: outputDirectory.appendingPathComponent("symmetry-orbit-comparison.json"))
      return .exact
    case .difference(let differences):
      try RetainedFiles.writeCanonical(
        differences, to: outputDirectory.appendingPathComponent("symmetry-differences.json"))
      return .difference
    }
  }

}

extension TemporalSymmetryCheck {
  private func validateSymmetryRequests(raw: TLCProcessRequest, reduced: TLCProcessRequest) throws {
    guard raw.caseID == reduced.caseID,
          raw.runID != reduced.runID,
          raw.finiteGraphCase.moduleSHA256 == reduced.finiteGraphCase.moduleSHA256,
          raw.finiteGraphCase.pin == reduced.finiteGraphCase.pin,
          raw.bundle.root.name == reduced.bundle.root.name,
          raw.bundle.root.tla == reduced.bundle.root.tla,
          raw.bundle.imports == reduced.bundle.imports,
          raw.bundle.root.cfg != reduced.bundle.root.cfg else {
      throw EvidenceFormatError.inconsistentReference(
        record: raw.caseID, field: "pinned TLC raw/reduced pair")
    }
  }

  private func makeFiniteGraphCase(
    id: String,
    exploration: FiniteExplorationConfiguration,
    bundle: TLAModuleBundle,
    pin: TLCReferencePin,
    architecture: String
  ) throws -> FiniteGraphCase {
    let arguments = ["-workers", "1", "-fp", "1"]
    guard let configuration = bundle.root.cfg else {
      throw EvidenceFormatError.invalidField(record: id, field: "TLC configuration")
    }
    return try FiniteGraphCase(
      id: id, exploration: exploration,
      moduleSHA256: SHA256.hex(Data(bundle.root.tla.utf8)), cfgSHA256: SHA256.hex(Data(configuration.utf8)),
      arguments: arguments, argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
      operatingSystem: "macos", architecture: architecture, environment: [:], pin: pin)
  }

  private func request(
    toolchain: ResolvedTLCToolchain,
    bundle: TLAModuleBundle,
    work: URL,
    finiteGraphCase: FiniteGraphCase,
    runID: UUID,
    projectRoot: URL
  ) throws -> TLCProcessRequest {
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    return TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"), traceOutput: work.appendingPathComponent("counterexample.json"),
      workingDirectory: work,
      finiteGraphCase: finiteGraphCase, runID: runID,
      referencePin: finiteGraphCase.pin, referenceArtifacts: toolchain.artifacts)
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

  private func temporalResult(
    compilation: CompiledSpecification,
    temporalCase: TemporalCase,
    exploration: ModelExplorationResult
  ) throws -> TemporalPropertyResult {
    let analyses = exploration.analyzeTemporalProperties(in: compilation)
    guard let analysis = analyses.first else {
      throw EvidenceFormatError.invalidField(record: temporalCase.id, field: "compiled temporal property")
    }
    switch analysis.status {
    case .satisfied:
      return .satisfied
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
      return .violated(lasso)
    case .unavailable:
      return .unavailable
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

private struct ConformanceMember: Identifiable, Sendable {
  let id: Int
}

package func temporalConformanceSpec(configuration: TemporalCaseConfiguration) -> TLASpec {
  let x = Var<Int>("x")
  let p = x == 2
  let q = x == 1
  let temporal = temporalProperty(property: configuration.property, p: p, q: q)
  return TLASpec(
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
}

private func temporalProperty(
  property: TemporalPropertyKind, p: StateExpr, q: StateExpr
) -> (String, TemporalExpr) {
  switch property {
  case .always: return ("AlwaysP", .always(p))
  case .eventually: return ("EventuallyP", .eventually(p))
  case .alwaysEventually: return ("AlwaysEventuallyP", .alwaysEventually(p))
  case .eventuallyAlways: return ("EventuallyAlwaysP", .eventuallyAlways(p))
  case .leadsTo: return ("LeadsToPQ", .leadsTo(p, q))
  }
}

private func fairness(_ fairness: TemporalFairnessMode) -> [FairnessCondition] {
  switch fairness {
  case .weak: return [.weakFairness("A")]
  case .strong: return [.strongFairness("A")]
  case .none: return []
  }
}

package func symmetryConformanceSpec(scope: Int) -> TLASpec {
  let chosen = SymmetricCollectionVar<ConformanceMember, Int>("chosen")
  return TLASpec("SymmetricCollection\(scope)") {
    SymmetricCollection(chosen, verificationScope: scope, initial: 0)
    CollectionAction("Choose", on: chosen) { member in
      chosen[member] == 0 && chosen.update(member, to: 1)
    }
  }
}
