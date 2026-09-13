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
    var nativeRuns: [TemporalFairnessMode: [Int: Result<TemporalModelRun, Error>]] = [:]
    let temporalOutcomes = try input.manifest.temporalCases.map { temporalCase in
      let observed: (outcome: TemporalSymmetryOutcome, diagnostic: String)
      do {
        let fairness = temporalCase.configuration.fairness
        let limit = temporalCase.exploration.maximumStateLimit
        let native = nativeRuns[fairness]?[limit] ?? Result {
          try temporalConformanceRun(fairness: fairness, maximumStates: limit)
        }
        nativeRuns[fairness, default: [:]][limit] = native
        let comparison = try captureTemporal(
          temporalCase: temporalCase, native: native.get(), toolRoot: input.toolRoot,
          referencePin: input.referencePin, projectRoot: root, evidenceRoot: output,
          outputDirectory: output.appendingPathComponent(temporalCase.id, isDirectory: true))
        let outcome: TemporalSymmetryOutcome = switch comparison.status {
        case .exact: .exact
        case .propertyOutcomeDifference, .graphDifference: .difference
        case .unavailable: .unavailable
        }
        observed = (outcome, comparison.status.rawValue)
      } catch {
        observed = (
          .unavailable,
          "temporal-validation-unavailable: \(String(describing: error))"
        )
      }
      return try retainOutcome(
        caseID: temporalCase.id,
        outcome: observed.outcome,
        diagnostic: observed.diagnostic,
        beneath: output
      )
    }

    let symmetryOutcomes = try input.manifest.symmetryCases.map { symmetryCase in
      let observed: (outcome: TemporalSymmetryOutcome, diagnostic: String)
      do {
        let compilation = try symmetryConformanceSpec(scope: symmetryCase.scope).compile()
        let outcome = try captureSymmetry(
          compilation: compilation, symmetryCase: symmetryCase,
          toolRoot: input.toolRoot, referencePin: input.referencePin,
          projectRoot: root, evidenceRoot: output,
          outputDirectory: output.appendingPathComponent(symmetryCase.id, isDirectory: true))
        observed = (outcome, outcome == .exact ? "exact" : "symmetry-comparison-difference")
      } catch {
        observed = (
          .unavailable,
          "pinned-tlc-symmetry-unavailable: \(String(describing: error))"
        )
      }
      return try retainOutcome(
        caseID: symmetryCase.id,
        outcome: observed.outcome,
        diagnostic: observed.diagnostic,
        beneath: output
      )
    }
    return temporalOutcomes + symmetryOutcomes
  }

  private func retainOutcome(
    caseID: String,
    outcome: TemporalSymmetryOutcome,
    diagnostic: String,
    beneath outputDirectory: URL
  ) throws -> TemporalSymmetryCheckOutcome {
    let value = try TemporalSymmetryCheckOutcome(
      caseID: caseID,
      outcome: outcome,
      diagnostic: diagnostic
    )
    let directory = outputDirectory.appendingPathComponent(caseID, isDirectory: true)
    try RetainedFiles.createDirectory(directory, beneath: outputDirectory)
    try RetainedFiles.writeJSON(
      ["caseID": value.caseID, "outcome": value.outcome.rawValue, "diagnostic": value.diagnostic],
      to: directory.appendingPathComponent("case-outcome.json")
    )
    return value
  }

  private func captureTemporal(
    temporalCase: TemporalCase,
    native: TemporalModelRun,
    toolRoot: URL,
    referencePin: TLCReferencePin,
    projectRoot: URL,
    evidenceRoot: URL,
    outputDirectory: URL
  ) throws -> TemporalComparison {
    let property = temporalCase.configuration.property.renderedName
    guard let check = native.properties[property] else {
      throw EvidenceFormatError.invalidField(record: property, field: "native temporal checking")
    }
    let toolchain = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(temporalCase.id)
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    let bundle = try native.rendered.tlaBundle(
      checking: [temporalCase.configuration.property.renderedName], checkDeadlock: false)
    let arguments = ["-workers", "1", "-fp", "1"]
    let launch = try FiniteGraphCase(
      id: temporalCase.id,
      exploration: temporalCase.exploration,
      moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)),
      cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: arguments,
      environment: [:], pin: referencePin)
    let request = TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: bundle,
      graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"),
      workingDirectory: work,
      finiteGraphCase: launch,
      runID: UUID(), invocation: .temporalProperty,
      referenceArtifacts: toolchain.artifacts)
    let graphBundle = try native.rendered.tlaBundle(checking: [], checkDeadlock: false)
    let graphCase = try FiniteGraphCase(
      id: temporalCase.id, exploration: temporalCase.exploration,
      moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)),
      cfgSHA256: SHA256.hex(Data(graphBundle.cfg.utf8)),
      arguments: arguments,
      environment: [:], pin: referencePin)
    let completeGraphRequest = TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: graphBundle,
      graphEvents: work.appendingPathComponent("complete-graph-events.jsonl"),
      traceOutput: work.appendingPathComponent("complete-graph-counterexample.json"),
      workingDirectory: work,
      finiteGraphCase: graphCase, runID: UUID(), invocation: .finiteGraph,
      referenceArtifacts: toolchain.artifacts)
    return try TLCTemporalAdapter().capture(TLCTemporalCaptureInput(
      temporalCase: temporalCase, request: request,
      completeGraphRequest: completeGraphRequest, swiftRun: check.graph, swiftResult: check.result,
      rendered: native.rendered, outputDirectory: outputDirectory))
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
    let collections = compilation.layout.variables.filter { $0.declaration.origin == .source }.compactMap(\.collection)
    guard collections.count == 1,
          let collection = collections.first,
          collection.members.count == scope else {
      throw EvidenceFormatError.invalidField(
        record: symmetryCase.id, field: "symmetric collection")
    }
    let generators = try symmetryGenerators(members: try collection.members.map { try $0.rendered(using: compilation.layout) })
    let toolchain = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: projectRoot, pin: referencePin)
    try RetainedFiles.createDirectory(outputDirectory, beneath: projectRoot)
    let rawRunID = UUID()
    let reducedRunID = UUID()
    let rendered = try compilation.render()
    let rawBundle = rendered.tlaBundle(
      symmetryReduction: symmetryCase.rawExploration.symmetryReduction)
    let reducedBundle = rendered.tlaBundle(
      symmetryReduction: symmetryCase.reducedExploration.symmetryReduction)
    let renderedActions = rendered.actions
    let work = evidenceRoot.appendingPathComponent("work", isDirectory: true).appendingPathComponent(symmetryCase.id, isDirectory: true)
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    let rawCase = try makeFiniteGraphCase(
      id: symmetryCase.id, exploration: symmetryCase.rawExploration,
      bundle: rawBundle, pin: referencePin, renderedActions: renderedActions,
      symmetryGenerators: [])
    let reducedCase = try makeFiniteGraphCase(
      id: symmetryCase.id, exploration: symmetryCase.reducedExploration,
      bundle: reducedBundle, pin: referencePin, renderedActions: renderedActions,
      symmetryGenerators: generators)
    let rawRequest = try request(
      toolchain: toolchain, bundle: rawBundle, work: work.appendingPathComponent("raw"),
      finiteGraphCase: rawCase, runID: rawRunID,
      projectRoot: projectRoot)
    let reducedRequest = try request(
      toolchain: toolchain, bundle: reducedBundle, work: work.appendingPathComponent("reduced"),
      finiteGraphCase: reducedCase, runID: reducedRunID,
      projectRoot: projectRoot)
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
    ).explore(), for: rawCase)
    let swiftReduced = try SwiftGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: symmetryCase.reducedExploration
    ).explore(), for: reducedCase)
    guard case .enabled(let maximumPermutationCount) = symmetryCase.reducedExploration.symmetryReduction else {
      throw EvidenceFormatError.invalidField(
        record: symmetryCase.id, field: "reduced symmetry policy")
    }
    let rawSwiftURL = outputDirectory.appendingPathComponent("swift-raw-graph.jsonl")
    let reducedSwiftURL = outputDirectory.appendingPathComponent("swift-reduced-graph.jsonl")
    let rawTLCURL = outputDirectory.appendingPathComponent("tlc-raw-graph.jsonl")
    let reducedTLCURL = outputDirectory.appendingPathComponent("tlc-reduced-graph.jsonl")
    try GraphRunRecords.write(swiftRaw, to: rawSwiftURL)
    try GraphRunRecords.write(swiftReduced, to: reducedSwiftURL)
    try GraphRunRecords.write(rawTLC, to: rawTLCURL)
    try GraphRunRecords.write(reducedTLC, to: reducedTLCURL)
    let input = try SymmetryOrbitComparisonInput(
      caseID: symmetryCase.id,
      swiftRaw: swiftRaw,
      swiftReduced: swiftReduced,
      tlcRaw: rawTLC,
      tlcReduced: reducedTLC,
      renderedActions: renderedActions,
      permutations: generators,
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
  private func makeFiniteGraphCase(
    id: String,
    exploration: FiniteExplorationConfiguration,
    bundle: TLAModuleBundle,
    pin: TLCReferencePin,
    renderedActions: [RenderedAction],
    symmetryGenerators: [SymmetryPermutation]
  ) throws -> FiniteGraphCase {
    let arguments = ["-workers", "1", "-fp", "1"]
    guard let configuration = bundle.root.cfg else {
      throw EvidenceFormatError.invalidField(record: id, field: "TLC configuration")
    }
    return try FiniteGraphCase(
      id: id, exploration: exploration,
      moduleSHA256: SHA256.hex(Data(bundle.root.tla.utf8)), cfgSHA256: SHA256.hex(Data(configuration.utf8)),
      arguments: arguments, environment: [:], pin: pin, renderedActions: renderedActions,
      symmetryGenerators: symmetryGenerators)
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
      finiteGraphCase: finiteGraphCase,
      runID: runID,
      invocation: .finiteGraph,
      referenceArtifacts: toolchain.artifacts)
  }

  private func symmetryGenerators(members: [TLAValue]) throws -> [SymmetryPermutation] {
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


}

private struct ResolvedTLCToolchain {
  let java: URL
  let jar: URL
  let bridgeClasses: URL
  let artifacts: TLCReferenceArtifacts

  init(toolRoot: URL, projectRoot: URL, pin: TLCReferencePin) throws {
    let armJava = toolRoot.appendingPathComponent("java-arm64/Contents/Home/bin/java")
    let architecture = FileManager.default.fileExists(atPath: armJava.path) ? "arm64" : "x86_64"
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

private struct ConformanceMember: Identifiable, Sendable {
  let id: Int
}

package func symmetryConformanceSpec(scope: Int) -> TLASpec {
  let chosen = CollectionVar<ConformanceMember, Int>("chosen")
  return TLASpec("ModelCollection\(scope)") {
    ModelCollection(chosen, verificationScope: scope, initial: 0)
    Symmetry(chosen)
    CollectionAction("Choose", on: chosen) { member in
      chosen[member] == 0 && chosen.update(member, to: 1)
    }
  }
}
