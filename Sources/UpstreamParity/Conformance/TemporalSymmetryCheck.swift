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
    let temporalOutcomes = try input.manifest.temporalCases.flatMap { temporalCase in
      let modelDirectory = try RetainedFiles.createDirectory(
        output.appendingPathComponent(temporalCase.id), beneath: output)
      let native: NativeModelRun
      do {
        native = try temporalConformanceRun(
          fairness: temporalCase.fairness, maximumStates: temporalCase.exploration.maximumStateLimit)
      } catch {
        return [try retainOutcome(caseID: temporalCase.id, outcome: .unavailable,
          diagnostic: "native-temporal-validation-unavailable: \(error)", in: modelDirectory, beneath: output)]
      }
      try GraphRunRecords.write(native.graph, to: modelDirectory.appendingPathComponent("swift-graph.jsonl"))
      try RetainedFiles.writeText(native.rendered.tlaBundle.tla, to: modelDirectory.appendingPathComponent("source-input"))
      let shared = Result {
        let toolchain = try ResolvedTLCToolchain(toolRoot: input.toolRoot, projectRoot: root, pin: input.referencePin)
        return try captureTemporalGraph(temporalCase: temporalCase, native: native,
          toolchain: toolchain, referencePin: input.referencePin, projectRoot: root, evidenceRoot: output)
      }
      let checks = try TLCPropertyCheck().captureAll(native, completeGraph: shared, in: modelDirectory)
      return try checks.map { check, status in
        let outcome: TemporalSymmetryOutcome = switch status {
        case .exact: .exact
        case .propertyOutcomeDifference, .graphDifference: .difference
        case .unavailable: .unavailable
        }
        let caseID = "\(temporalCase.id)-\(check.artifactPath.replacingOccurrences(of: "/", with: "-"))"
        return try retainOutcome(caseID: caseID, outcome: outcome,
          diagnostic: status.rawValue, in: modelDirectory.appendingPathComponent(check.artifactPath), beneath: output)
      }
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
        in: output.appendingPathComponent(symmetryCase.id),
        beneath: output
      )
    }
    return temporalOutcomes + symmetryOutcomes
  }

  private func retainOutcome(
    caseID: String,
    outcome: TemporalSymmetryOutcome,
    diagnostic: String,
    in directory: URL,
    beneath outputDirectory: URL
  ) throws -> TemporalSymmetryCheckOutcome {
    let value = try TemporalSymmetryCheckOutcome(
      caseID: caseID,
      outcome: outcome,
      diagnostic: diagnostic
    )
    try RetainedFiles.createDirectory(directory, beneath: outputDirectory)
    try RetainedFiles.writeJSON(
      ["caseID": value.caseID, "outcome": value.outcome.rawValue, "diagnostic": value.diagnostic],
      to: directory.appendingPathComponent("case-outcome.json")
    )
    return value
  }

  private func captureTemporalGraph(
    temporalCase: TemporalCase, native: NativeModelRun, toolchain: ResolvedTLCToolchain,
    referencePin: TLCReferencePin, projectRoot: URL, evidenceRoot: URL
  ) throws -> TLCProcessCapture {
    let bundle = try native.rendered.tlaBundle(checking: [], checkDeadlock: false)
    let request = try temporalRequest(temporalCase: temporalCase, bundle: bundle,
      invocation: .finiteGraph, toolchain: toolchain, referencePin: referencePin,
      projectRoot: projectRoot, evidenceRoot: evidenceRoot)
    let directory = evidenceRoot.appendingPathComponent(temporalCase.id).appendingPathComponent("complete-graph")
    let capture = try TLCProcessAdapter().capture(request, retainingIn: directory)
    guard capture.outcome == .completed, capture.graph.isComparable else {
      throw TLCPropertyCheckError.incompleteGraph
    }
    try GraphRunRecords.write(capture.graph, to: directory.appendingPathComponent("tlc-graph.jsonl"))
    return capture
  }

  private func temporalRequest(
    temporalCase: TemporalCase, bundle: TLAModuleBundle, invocation: TLCInvocationKind,
    toolchain: ResolvedTLCToolchain, referencePin: TLCReferencePin,
    projectRoot: URL, evidenceRoot: URL
  ) throws -> TLCProcessRequest {
    let work = evidenceRoot.appendingPathComponent("work").appendingPathComponent(temporalCase.id)
    try RetainedFiles.createDirectory(work, beneath: projectRoot)
    let launch = try FiniteGraphCase(id: temporalCase.id, exploration: temporalCase.exploration,
      moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)), cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
      arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: referencePin)
    return TLCProcessRequest(
      javaExecutable: toolchain.java, jar: toolchain.jar, bridgeClasses: toolchain.bridgeClasses,
      bundle: bundle, graphEvents: work.appendingPathComponent("events.jsonl"),
      traceOutput: work.appendingPathComponent("counterexample.json"), workingDirectory: work,
      finiteGraphCase: launch, runID: UUID(), invocation: invocation, referenceArtifacts: toolchain.artifacts)
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
    let swiftRaw = try FormalGraphExporter().export(ModelChecker(
      compilation: compilation,
      configuration: symmetryCase.rawExploration
    ).explore(), for: rawCase)
    let swiftReduced = try FormalGraphExporter().export(ModelChecker(
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
