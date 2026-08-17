import Foundation
import SwiftTLA

public enum CompilerPipelineEvidenceOutcomeV1: String, Codable, Sendable, Equatable { case exact, difference, unavailable }
public enum CompilerPipelineEvidenceAuthorityV1: String, Codable, Sendable { case diagnosticOnly }

public struct CompilerPipelineDiagnosticCaseV1: Codable, Sendable, Equatable {
  public let id: String
  public let source: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let finiteBounds: CoreFiniteBoundsV1
  public let expectedOutcome: CompilerPipelineEvidenceOutcomeV1

  public init(id: String, source: CoreEvidenceReferenceV1, configuration: CoreEvidenceReferenceV1,
              finiteBounds: CoreFiniteBoundsV1, expectedOutcome: CompilerPipelineEvidenceOutcomeV1) throws {
    self.id = id; self.source = source; self.configuration = configuration; self.finiteBounds = finiteBounds; self.expectedOutcome = expectedOutcome
    try validate()
  }
  public func validate() throws {
    try source.validate(); try configuration.validate(); try finiteBounds.validate()
    guard !id.isEmpty, finiteBounds.limits["maxStates"] != nil else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "compiler pipeline case") }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case id, source, configuration, finiteBounds, expectedOutcome }
  public init(from decoder: Decoder) throws {
    let c = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(id: try c.decode(String.self, forKey: .id), source: try c.decode(CoreEvidenceReferenceV1.self, forKey: .source), configuration: try c.decode(CoreEvidenceReferenceV1.self, forKey: .configuration), finiteBounds: try c.decode(CoreFiniteBoundsV1.self, forKey: .finiteBounds), expectedOutcome: try c.decode(CompilerPipelineEvidenceOutcomeV1.self, forKey: .expectedOutcome))
  }
}

public struct CompilerPipelineDiagnosticManifestV1: Codable, Sendable {
  public static let schema = "CompilerPipelineDiagnosticManifestV1"
  public let schema: String
  public let authority: CompilerPipelineEvidenceAuthorityV1
  public struct ToolchainEntry: Codable, Sendable, Equatable {
    public let role: String
    public let evidence: CoreEvidenceReferenceV1
    public init(role: String, evidence: CoreEvidenceReferenceV1) throws {
      guard !role.isEmpty else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: "compiler pipeline toolchain", field: "role") }
      try evidence.validate()
      self.role = role
      self.evidence = evidence
    }
  }
  public let toolchain: [ToolchainEntry]
  public let cases: [CompilerPipelineDiagnosticCaseV1]
  public init(authority: CompilerPipelineEvidenceAuthorityV1 = .diagnosticOnly, toolchain: [ToolchainEntry], cases: [CompilerPipelineDiagnosticCaseV1]) throws {
    schema = Self.schema; self.authority = authority; self.toolchain = toolchain; self.cases = cases; try validate()
  }
  public func validate() throws {
    try toolchain.forEach { try $0.evidence.validate() }; try cases.forEach { try $0.validate() }
    let required: Set<String> = ["adapter", "compiler", "macro", "runtime", "tlcAdapter", "graphParser", "dependencies", "tlcReference"]
    guard authority == .diagnosticOnly, Set(toolchain.map(\.role)) == required, toolchain.count == required.count,
          Set(toolchain.map { $0.evidence.path }).count == toolchain.count, !cases.isEmpty, Set(cases.map(\.id)).count == cases.count else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "compiler pipeline manifest", field: "authority, toolchain, or cases")
    }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, authority, toolchain, cases }
  public init(from decoder: Decoder) throws {
    let c = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    let schema = try c.decode(String.self, forKey: .schema)
    guard schema == Self.schema else { throw PublicWorkflowGovernanceErrorV1.invalidSchema(schema) }
    try self.init(authority: try c.decode(CompilerPipelineEvidenceAuthorityV1.self, forKey: .authority), toolchain: try c.decode([ToolchainEntry].self, forKey: .toolchain), cases: try c.decode([CompilerPipelineDiagnosticCaseV1].self, forKey: .cases))
  }
}

/// Configuration selects a registered source fixture and can only alter the
/// contract assertion. It cannot construct a formal model.
public struct CompilerPipelineFixtureConfigurationV1: Codable, Sendable {
  public static let schema = "CompilerPipelineFixtureConfigurationV1"
  public enum MetadataMode: String, Codable, Sendable, Equatable { case exact, mismatch }
  public enum RenderedBundleMode: String, Codable, Sendable, Equatable { case exact, semanticMismatch }
  public let schema: String
  public let caseID: String
  public let fixtureID: String
  public let maxStates: Int
  public let metadataMode: MetadataMode
  public let renderedBundleMode: RenderedBundleMode
  public let toolAvailable: Bool
  public init(caseID: String, fixtureID: String, maxStates: Int, metadataMode: MetadataMode = .exact, renderedBundleMode: RenderedBundleMode = .exact, toolAvailable: Bool = true) throws {
    schema = Self.schema; self.caseID = caseID; self.fixtureID = fixtureID; self.maxStates = maxStates; self.metadataMode = metadataMode; self.renderedBundleMode = renderedBundleMode; self.toolAvailable = toolAvailable; try validate()
  }
  public func validate() throws {
    guard !caseID.isEmpty, !fixtureID.isEmpty, maxStates > 0 else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: caseID, field: "compiler pipeline fixture configuration") }
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, caseID, fixtureID, maxStates, metadataMode, renderedBundleMode, toolAvailable }
  public init(from decoder: Decoder) throws {
    let c = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    let schema = try c.decode(String.self, forKey: .schema)
    guard schema == Self.schema else { throw PublicWorkflowGovernanceErrorV1.invalidSchema(schema) }
    try self.init(caseID: try c.decode(String.self, forKey: .caseID), fixtureID: try c.decode(String.self, forKey: .fixtureID), maxStates: try c.decode(Int.self, forKey: .maxStates), metadataMode: try c.decode(MetadataMode.self, forKey: .metadataMode), renderedBundleMode: try c.decode(RenderedBundleMode.self, forKey: .renderedBundleMode), toolAvailable: try c.decode(Bool.self, forKey: .toolAvailable))
  }
}

public struct CompilerPipelineGeneratedContractArtifactV1: Codable, Sendable, Equatable {
  public let status: String
  public let initialStateCount: Int
  public let transitionCount: Int
  public let diagnostic: String?
  init(_ report: GeneratedMachineContractReport) {
    status = report.status.rawValue; initialStateCount = report.initialStateCount; transitionCount = report.transitionCount; diagnostic = report.diagnostic.map(String.init(describing:))
  }
}

public struct CompilerPipelineDiagnosticEvidenceV1: Codable, Sendable {
  public static let schema = "CompilerPipelineDiagnosticEvidenceV1"
  public let schema: String
  public let authority: CompilerPipelineEvidenceAuthorityV1
  public let caseID: String
  public let correlation: PublicWorkflowCaseRunCorrelationV1
  public let source: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let toolchain: [CompilerPipelineDiagnosticManifestV1.ToolchainEntry]
  public let finiteBounds: CoreFiniteBoundsV1
  public let bundle: [CoreEvidenceReferenceV1]
  public let artifacts: [CoreEvidenceReferenceV1]
  public let expectedOutcome: CompilerPipelineEvidenceOutcomeV1
  public let outcome: CompilerPipelineEvidenceOutcomeV1
  public let status: PublicWorkflowDiagnosticCheckStatusV1
  public let compilationDiagnosticCode: String?
  public let compilationDiagnosticStage: String?
  public let diagnostic: String?

  init(case declaration: CompilerPipelineDiagnosticCaseV1, correlation: PublicWorkflowCaseRunCorrelationV1, toolchain: [CompilerPipelineDiagnosticManifestV1.ToolchainEntry], bundle: [CoreEvidenceReferenceV1] = [], artifacts: [CoreEvidenceReferenceV1] = [], outcome: CompilerPipelineEvidenceOutcomeV1, compilationDiagnostic: CompilationDiagnostic? = nil, diagnostic: String? = nil) {
    schema = Self.schema; authority = .diagnosticOnly; caseID = declaration.id; self.correlation = correlation; source = declaration.source; configuration = declaration.configuration; self.toolchain = toolchain; finiteBounds = declaration.finiteBounds; self.bundle = bundle; self.artifacts = artifacts; expectedOutcome = declaration.expectedOutcome; self.outcome = outcome
    status = outcome == declaration.expectedOutcome ? .matched : outcome == .unavailable ? .unavailable : .differed
    compilationDiagnosticCode = compilationDiagnostic?.code.rawValue
    compilationDiagnosticStage = compilationDiagnostic?.stage.rawValue
    self.diagnostic = diagnostic
  }
}

public struct CompilerPipelineDiagnosticRunV1: Codable, Sendable {
  public let evidence: CompilerPipelineDiagnosticEvidenceV1

  public func validateRetainedArtifacts(beneath root: URL) throws {
    let root = root.resolvingSymlinksInPath().standardizedFileURL
    for reference in [evidence.source, evidence.configuration] + evidence.toolchain.map(\.evidence) + evidence.bundle + evidence.artifacts {
      let url = root.appendingPathComponent(reference.path).resolvingSymlinksInPath().standardizedFileURL
      guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path),
            SHA256V1.hex(try Data(contentsOf: url)) == reference.sha256 else {
        throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: reference.path, field: "retained compiler-pipeline artifact SHA-256")
      }
    }
  }
}

private struct CompilerPipelineCompilationArtifactV1: Codable {
  let compilationIdentity: String
  let maxStates: Int
}

public struct CompilerPipelineDiagnosticEvidenceAdapterV1: Sendable {
  private let toolRoot: URL?
  private let toolProjectRoot: URL?
  public init(toolRoot: URL? = nil, toolProjectRoot: URL? = nil) {
    self.toolRoot = toolRoot
    self.toolProjectRoot = toolProjectRoot
  }
  @discardableResult
  public func run(manifestURL: URL, projectRoot: URL, outputDirectory: URL, correlation: PublicWorkflowCaseRunCorrelationV1) throws -> CompilerPipelineDiagnosticRunV1 {
    let root = try validatedDirectory(projectRoot)
    let output = try writableOutputDirectory(outputDirectory, beneath: root)
    let manifest = try JSONDecoder().decode(CompilerPipelineDiagnosticManifestV1.self, from: Data(contentsOf: try resolved(manifestURL, beneath: root)))
    guard let declaration = manifest.cases.first(where: { $0.id == correlation.caseID }) else { throw PublicWorkflowGovernanceErrorV1.unknownCaseID(correlation.caseID) }
    do {
      _ = try verifiedData(for: declaration.source, beneath: root)
      let configuration = try JSONDecoder().decode(CompilerPipelineFixtureConfigurationV1.self, from: verifiedData(for: declaration.configuration, beneath: root))
      for pin in manifest.toolchain { _ = try verifiedData(for: pin.evidence, beneath: root) }
      guard configuration.caseID == declaration.id else { throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: declaration.id, field: "configuration case identity") }
      guard configuration.toolAvailable else { return try finish(declaration, correlation: correlation, toolchain: manifest.toolchain, output: output, outcome: .unavailable, diagnostic: "declared generated-machine tool unavailable") }
      guard let maxStates = declaration.finiteBounds.limits["maxStates"], maxStates > 0,
            configuration.maxStates == maxStates else {
        throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: declaration.id, field: "executed maxStates")
      }
      let fixture = try PublicWorkflowCompilerPipelineFixtureRegistryV1.fixture(id: configuration.fixtureID)
      let compilation = try fixture.compile()
      guard fixture.verificationStateLimit() == maxStates else {
        throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: declaration.id, field: "generated verificationStateLimit")
      }
      let compilationURL = output.appendingPathComponent("compilation.json")
      try writeCanonical(CompilerPipelineCompilationArtifactV1(compilationIdentity: compilation.identity.value, maxStates: maxStates), to: compilationURL)
      let bundle = try renderedBundle(compilation.tlaBundle, mode: configuration.renderedBundleMode)
      try bundle.validateRenderedBundleIntegrity()
      let bundleDirectory = output.appendingPathComponent("bundle")
      try bundle.write(to: bundleDirectory)
      let bundleReferences = try bundle.files.map { try reference(for: bundleDirectory.appendingPathComponent("\($0.name).tla"), beneath: root) } + [try reference(for: bundleDirectory.appendingPathComponent("\(bundle.root.name).cfg"), beneath: root)]
      let generated: GeneratedMachineContractReport
      if configuration.metadataMode == .mismatch {
        let plan = try MachineSurfacePlan(compilation: compilation)
        let drifted = GeneratedMachineMetadata(compilationIdentity: plan.compilationIdentity, schemaIdentifier: plan.schemaIdentifier, variables: plan.variables, actions: [])
        guard fixture.metadata() != drifted else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: declaration.id, field: "metadata mismatch control") }
        generated = fixture.verifyGeneratedMachine(drifted, maxStates)
      } else { generated = fixture.verifyGeneratedMachine(nil, maxStates) }
      let contract = CompilerPipelineGeneratedContractArtifactV1(generated)
      let contractURL = output.appendingPathComponent("generated-contract.json")
      try writeCanonical(contract, to: contractURL)
      let direct = try directGraphEvidence(declaration: declaration, compilation: compilation, bundleDirectory: bundleDirectory,
                                          maxStates: maxStates, root: root, output: output, correlation: correlation)
      let artifactURLs = [compilationURL, contractURL] + direct.artifacts
      let outcome: CompilerPipelineEvidenceOutcomeV1
      if generated.status == .unavailable || direct.outcome == .unavailable { outcome = .unavailable }
      else if generated.status == .difference || direct.outcome == .difference { outcome = .difference }
      else { outcome = .exact }
      return try finish(declaration, correlation: correlation, toolchain: manifest.toolchain, output: output, bundle: bundleReferences,
                        artifacts: try artifactURLs.map { try reference(for: $0, beneath: root) }, outcome: outcome,
                        diagnostic: [contract.diagnostic, direct.diagnostic].compactMap { $0 }.joined(separator: "\n"))
    } catch let diagnostic as CompilationDiagnostic {
      return try finish(declaration, correlation: correlation, toolchain: manifest.toolchain, output: output, outcome: .difference, compilationDiagnostic: diagnostic, diagnostic: diagnostic.description)
    } catch { return try finish(declaration, correlation: correlation, toolchain: manifest.toolchain, output: output, outcome: .unavailable, diagnostic: String(describing: error)) }
  }

  private func renderedBundle(_ bundle: TLAModuleBundle, mode: CompilerPipelineFixtureConfigurationV1.RenderedBundleMode) throws -> TLAModuleBundle {
    guard mode == .semanticMismatch else { return bundle }
    guard bundle.root.tla.contains("Init == count = 0") else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: bundle.root.name, field: "rendered semantic mismatch control")
    }
    let replacement = bundle.root.tla.replacingOccurrences(of: "Init == count = 0", with: "Init == count = 1")
    return TLAModuleBundle(root: .init(name: bundle.root.name, tla: replacement, cfg: bundle.root.cfg), imports: bundle.imports)
  }

  private func directGraphEvidence(declaration: CompilerPipelineDiagnosticCaseV1, compilation: CompiledSpecification,
                                   bundleDirectory: URL, maxStates: Int, root: URL, output: URL,
                                   correlation: PublicWorkflowCaseRunCorrelationV1) throws -> (outcome: CompilerPipelineEvidenceOutcomeV1, artifacts: [URL], diagnostic: String?) {
    let toolRoot = self.toolRoot ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CORE_CONFORMANCE_TOOL_ROOT"] ?? root.appendingPathComponent(".build/core-conformance-tools").path)
    let architecture = FileManager.default.fileExists(atPath: toolRoot.appendingPathComponent("java-arm64/Contents/Home/bin/java").path) ? "arm64" : "x86_64"
    let java = toolRoot.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
    let bridgeClasses = toolRoot.appendingPathComponent("bridge-classes")
    let jar = toolRoot.appendingPathComponent("downloads/tla2tools.jar")
    let archive = toolRoot.appendingPathComponent("downloads/temurin-\(architecture).tar.gz")
    let bridge = bridgeClasses.appendingPathComponent("org/swifttla/conformance/LosslessStateWriter.class")
    let bridgeSource = (toolProjectRoot ?? root).appendingPathComponent("Tools/TLCGraphBridge/src/org/swifttla/conformance/LosslessStateWriter.java")
    let artifacts = try TLCReferenceInspectorV1.inspect(artifacts: .init(jar: jar, javaArchive: archive, bridgeSource: bridgeSource, bridgeBinary: bridge, jarManifest: "", runtime: .init(version: "", vendor: "", architecture: architecture, properties: [:])), javaExecutable: java, directory: root)
    try TLCReferencePinV1.fixture.validate(artifacts)
    let module = bundleDirectory.appendingPathComponent("\(compilation.spec.name).tla")
    let configuration = bundleDirectory.appendingPathComponent("\(compilation.spec.name).cfg")
    let arguments = ["-workers", "1", "-fp", "1", "-deadlock"]
    let launch = try CoreConformanceCaseV1(id: declaration.id, moduleSHA256: SHA256V1.hex(try Data(contentsOf: module)), cfgSHA256: SHA256V1.hex(try Data(contentsOf: configuration)), arguments: arguments, argumentsSHA256: CoreConformanceCaseV1.argumentsDigest(arguments), workers: 1, fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: architecture, environment: [:], pin: .fixture)
    let exploration = try ModelChecker(compilation: compilation, maxStates: maxStates).explore()
    guard exploration.isComplete else { return (.unavailable, [], "formal graph exceeded maxStates \(maxStates)") }
    let directOutput = output.appendingPathComponent("direct-graph")
    let request = TLCProcessRequestV1(javaExecutable: java, jar: jar, bridgeClasses: bridgeClasses, module: module, configuration: configuration,
      graphEvents: output.appendingPathComponent("direct-events.jsonl"), traceOutput: output.appendingPathComponent("direct-trace.json"), replayInput: output.appendingPathComponent("direct-replay.json"), workingDirectory: output, arguments: arguments, expectedCase: launch, runID: correlation.comparisonRunID, referencePin: .fixture, referenceArtifacts: artifacts)
    let swiftActionNames = Dictionary(uniqueKeysWithValues: compilation.spec.actions.map { ($0.name, "Next") })
    let result = CoreConformanceRunnerV1().run(case: launch, swiftExploration: { .init(caseID: declaration.id, exploration: exploration) }, tlcRequest: request, replay: .none, outputDirectory: directOutput, swiftActionNames: swiftActionNames)
    guard let comparison = result.comparison, let evidence = result.evidenceDirectory else {
      return (.unavailable, [], result.diagnostic?.message)
    }
    let retained = try FileManager.default.subpathsOfDirectory(atPath: evidence.path).map { evidence.appendingPathComponent($0) }.filter { ["json", "log"].contains($0.pathExtension) }
    return (comparison.isConformant ? .exact : .difference, retained, result.diagnostic?.message)
  }

  private func finish(_ declaration: CompilerPipelineDiagnosticCaseV1, correlation: PublicWorkflowCaseRunCorrelationV1, toolchain: [CompilerPipelineDiagnosticManifestV1.ToolchainEntry], output: URL, bundle: [CoreEvidenceReferenceV1] = [], artifacts: [CoreEvidenceReferenceV1] = [], outcome: CompilerPipelineEvidenceOutcomeV1, compilationDiagnostic: CompilationDiagnostic? = nil, diagnostic: String) throws -> CompilerPipelineDiagnosticRunV1 {
    let run = CompilerPipelineDiagnosticRunV1(evidence: .init(case: declaration, correlation: correlation, toolchain: toolchain, bundle: bundle, artifacts: artifacts, outcome: outcome, compilationDiagnostic: compilationDiagnostic, diagnostic: diagnostic))
    try writeCanonical(run, to: output.appendingPathComponent("run.json")); return run
  }

  private func verifiedData(for reference: CoreEvidenceReferenceV1, beneath root: URL) throws -> Data {
    let data = try Data(contentsOf: resolved(root.appendingPathComponent(reference.path), beneath: root))
    guard SHA256V1.hex(data) == reference.sha256 else { throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: reference.path, field: "SHA-256") }; return data
  }
  private func validatedDirectory(_ url: URL) throws -> URL {
    let url = url.resolvingSymlinksInPath().standardizedFileURL; var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: url.path, field: "project root") }; return url
  }
  private func resolved(_ url: URL, beneath root: URL) throws -> URL {
    let candidate = (url.path.hasPrefix("/") ? url : root.appendingPathComponent(url.path)).standardizedFileURL.resolvingSymlinksInPath()
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: url.path, field: "path outside project root") }; return candidate
  }
  private func writableOutputDirectory(_ output: URL, beneath root: URL) throws -> URL {
    let output = try resolved(output, beneath: root); guard !FileManager.default.fileExists(atPath: output.path) else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: output.path, field: "output already exists") }; try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true); return output
  }
  private func reference(for url: URL, beneath root: URL) throws -> CoreEvidenceReferenceV1 { let url = try resolved(url, beneath: root); return try .init(path: String(url.path.dropFirst(root.path.count + 1)), sha256: SHA256V1.hex(try Data(contentsOf: url))) }
  private func writeCanonical<T: Encodable>(_ value: T, to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; try encoder.encode(value).write(to: url, options: .atomic) }
}
