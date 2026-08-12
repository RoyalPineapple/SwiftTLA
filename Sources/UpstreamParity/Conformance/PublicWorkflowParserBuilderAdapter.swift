import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA

/// The exportable, source-controlled parser/builder fixture contract.
///
/// A validation corpus can retain this manifest and its referenced inputs without
/// importing implementation sources. All paths are project-relative and every
/// input is pinned by its SHA-256 digest.
public struct PublicWorkflowParserBuilderManifestV1: Decodable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderManifestV1"

  public let schema: String
  public let declaredCase: PublicWorkflowConformanceCaseV1
  public let source: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let parserObservation: CoreEvidenceReferenceV1
  public let builderObservation: CoreEvidenceReferenceV1
  public let toolchain: PublicWorkflowParserBuilderToolchainV1

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, declaredCase, source, configuration, parserObservation, builderObservation, toolchain
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    declaredCase = try container.decode(PublicWorkflowConformanceCaseV1.self, forKey: .declaredCase)
    source = try container.decode(CoreEvidenceReferenceV1.self, forKey: .source)
    configuration = try container.decode(CoreEvidenceReferenceV1.self, forKey: .configuration)
    parserObservation = try container.decode(CoreEvidenceReferenceV1.self, forKey: .parserObservation)
    builderObservation = try container.decode(CoreEvidenceReferenceV1.self, forKey: .builderObservation)
    toolchain = try container.decode(PublicWorkflowParserBuilderToolchainV1.self, forKey: .toolchain)
    try validate()
  }

  public func validate() throws {
    try declaredCase.validate()
    try source.validate()
    try configuration.validate()
    try parserObservation.validate()
    try builderObservation.validate()
    try toolchain.validate()
    guard schema == Self.schema,
          declaredCase.category == .parserBuilder,
          declaredCase.sourceInput == source,
          declaredCase.configuration == configuration else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(
        record: declaredCase.id, field: "parser-builder manifest")
    }
  }
}

/// Records every applicable implementation identity as a portable file pin.
/// `notApplicable` deliberately describes tools that this comparison does not
/// execute; their digest fields point to the retained declaration rather than a
/// fabricated tool hash.
public struct PublicWorkflowParserBuilderToolchainV1: Decodable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderToolchainV1"
  public let schema: String
  public let dependencies: [Dependency]
  public let notApplicable: [NotApplicable]

  public struct Dependency: Decodable, Sendable {
    public let id: String
    public let evidence: CoreEvidenceReferenceV1
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, evidence }
    public init(from decoder: Decoder) throws {
      let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      evidence = try container.decode(CoreEvidenceReferenceV1.self, forKey: .evidence)
      try evidence.validate()
    }
  }

  public struct NotApplicable: Decodable, Sendable {
    public let id: String
    public let reason: CoreEvidenceReferenceV1
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, reason }
    public init(from decoder: Decoder) throws {
      let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      reason = try container.decode(CoreEvidenceReferenceV1.self, forKey: .reason)
      try reason.validate()
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, dependencies, notApplicable }
  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    dependencies = try container.decode([Dependency].self, forKey: .dependencies)
    notApplicable = try container.decode([NotApplicable].self, forKey: .notApplicable)
    try validate()
  }

  public func validate() throws {
    guard schema == Self.schema,
          Set(dependencies.map(\.id)) == ["swiftSyntaxResolution", "swiftTLAPackage", "adapterSource"],
          dependencies.count == 3,
          Set(notApplicable.map(\.id)) == ["tlc", "java", "bridgeBinary"],
          notApplicable.count == 3 else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "parser-builder toolchain", field: "identity coverage")
    }
  }

  func dependency(_ id: String) -> CoreEvidenceReferenceV1 { dependencies.first(where: { $0.id == id })!.evidence }
  func nonApplicable(_ id: String) -> CoreEvidenceReferenceV1 { notApplicable.first(where: { $0.id == id })!.reason }
}

/// A deliberately narrow builder description. It prevents a caller from
/// substituting arbitrary source or a hand-constructed `TLASpec` at comparison
/// time while keeping the fixture portable to a separate validation repository.
public struct PublicWorkflowBoundedCounterConfigurationV1: Decodable, Sendable {
  public static let schema = "PublicWorkflowBoundedCounterConfigurationV1"

  public let schema: String
  public let model: String
  public let specificationName: String
  public let variable: String
  public let initialValue: Int
  public let nextValue: Int
  public let upperBound: Int

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, model, specificationName, variable, initialValue, nextValue, upperBound
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    model = try container.decode(String.self, forKey: .model)
    specificationName = try container.decode(String.self, forKey: .specificationName)
    variable = try container.decode(String.self, forKey: .variable)
    initialValue = try container.decode(Int.self, forKey: .initialValue)
    nextValue = try container.decode(Int.self, forKey: .nextValue)
    upperBound = try container.decode(Int.self, forKey: .upperBound)
    try validate()
  }

  public func validate() throws {
    guard schema == Self.schema, model == "boundedCounterV1", !specificationName.isEmpty,
          variable == "x", initialValue == 0, nextValue > 0, upperBound >= nextValue else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(
        record: "parser-builder configuration", field: "bounded counter")
    }
  }

  func makeSpec() -> TLASpec {
    let x = Var<Int>(variable, initialValue)
    return TLASpec(specificationName) {
      Variable(x)
      Action("advance") { x.becomes(nextValue) }
      Invariant("withinBounds") { x <= upperBound }
    }
  }
}

public struct PublicWorkflowParserBuilderRunV1: Codable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderRunV1"

  public let schema: String
  public let manifest: CoreEvidenceReferenceV1
  public let comparison: PublicWorkflowComparisonV1
  public let parserObservation: CoreEvidenceReferenceV1
  public let builderObservation: CoreEvidenceReferenceV1

  public init(manifest: CoreEvidenceReferenceV1, comparison: PublicWorkflowComparisonV1,
              parserObservation: CoreEvidenceReferenceV1, builderObservation: CoreEvidenceReferenceV1) {
    self.schema = Self.schema
    self.manifest = manifest
    self.comparison = comparison
    self.parserObservation = parserObservation
    self.builderObservation = builderObservation
  }
}

public struct PublicWorkflowParserBuilderAdapterV1: Sendable {
  public init() {}

  /// Runs one exported manifest. `projectRoot` is explicit so callers can move
  /// the corpus to SwiftTLA-Validation without relying on this repository's path.
  /// The result is diagnostic until a hosted-CI artifact receipt admits it.
  @discardableResult
  public func run(
    manifestURL: URL,
    projectRoot: URL,
    outputDirectory: URL,
    correlation: PublicWorkflowCaseRunCorrelationV1
  ) throws -> PublicWorkflowParserBuilderRunV1 {
    let root = try validatedDirectory(projectRoot)
    let manifestURL = try resolved(manifestURL, beneath: root)
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(PublicWorkflowParserBuilderManifestV1.self, from: manifestData)
    guard correlation.caseID == manifest.declaredCase.id else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: manifest.declaredCase.id, field: "run correlation")
    }

    let sourceData = try verifiedData(for: manifest.source, beneath: root)
    let configurationData = try verifiedData(for: manifest.configuration, beneath: root)
    let expectedParserData = try verifiedData(for: manifest.parserObservation, beneath: root)
    let expectedBuilderData = try verifiedData(for: manifest.builderObservation, beneath: root)
    try validateToolchain(manifest.toolchain, provenance: manifest.declaredCase.provenance, beneath: root)
    let configuration = try JSONDecoder().decode(PublicWorkflowBoundedCounterConfigurationV1.self, from: configurationData)
    try validateProvenance(manifest.declaredCase.provenance, source: sourceData, configuration: configurationData,
                           toolchain: manifest.toolchain)

    let parserObservation = try observeParser(source: String(decoding: sourceData, as: UTF8.self), name: configuration.specificationName)
    let builderObservation = try observe(spec: configuration.makeSpec(), diagnostics: [])
    try verifyObservation(parserObservation, equals: expectedParserData, reference: manifest.parserObservation)
    try verifyObservation(builderObservation, equals: expectedBuilderData, reference: manifest.builderObservation)

    let outcome: PublicWorkflowExpectedOutcomeV1 = parserObservation == builderObservation ? .exact : .difference
    let diagnosticCode: PublicWorkflowDiagnosticCodeV1 = outcome == .exact ? .exactAgreement : .observationDifference
    let bindings = try evidenceBinding(for: manifest.declaredCase, correlation: correlation,
                                       parserEvidence: manifest.parserObservation, builderEvidence: manifest.builderObservation)
    let comparison = try PublicWorkflowComparisonV1(
      caseID: manifest.declaredCase.id, correlation: correlation, left: parserObservation, right: builderObservation,
      outcome: outcome, diagnosticCode: diagnosticCode, leftBinding: bindings.parser, rightBinding: bindings.builder)

    let output = try writableOutputDirectory(outputDirectory, beneath: root)
    try writeCanonical(parserObservation, to: output.appendingPathComponent("parser-observation.json"))
    try writeCanonical(builderObservation, to: output.appendingPathComponent("builder-observation.json"))
    try writeCanonical(comparison, to: output.appendingPathComponent("comparison.json"))
    let run = PublicWorkflowParserBuilderRunV1(
      manifest: try reference(for: manifestURL, beneath: root, data: manifestData), comparison: comparison,
      parserObservation: try reference(for: output.appendingPathComponent("parser-observation.json"), beneath: root),
      builderObservation: try reference(for: output.appendingPathComponent("builder-observation.json"), beneath: root))
    try writeCanonical(run, to: output.appendingPathComponent("run.json"))
    return run
  }

  private func validateProvenance(_ provenance: CoreDivergenceProvenanceV1, source: Data, configuration: Data,
                                  toolchain: PublicWorkflowParserBuilderToolchainV1) throws {
    guard provenance.moduleSHA256 == SHA256V1.hex(source), provenance.cfgSHA256 == SHA256V1.hex(configuration),
          provenance.argumentsSHA256 == SHA256V1.hex(configuration),
          provenance.tlcTag == "not-applicable-parser-builder-v1",
          provenance.tlcCommit == "not-applicable-parser-builder-v1",
          provenance.tlcJarSHA256 == toolchain.nonApplicable("tlc").sha256,
          provenance.javaDistribution == "not-applicable-parser-builder-v1",
          provenance.javaVersion == "not-applicable-parser-builder-v1",
          provenance.javaArchiveSHA256 == toolchain.nonApplicable("java").sha256,
          provenance.bridgeSourceSHA256 == toolchain.dependency("adapterSource").sha256,
          provenance.bridgeBinarySHA256 == toolchain.nonApplicable("bridgeBinary").sha256 else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: provenance.caseID, field: "source/configuration provenance")
    }
  }

  private func validateToolchain(_ toolchain: PublicWorkflowParserBuilderToolchainV1,
                                 provenance: CoreDivergenceProvenanceV1, beneath root: URL) throws {
    for dependency in toolchain.dependencies { _ = try verifiedData(for: dependency.evidence, beneath: root) }
    for nonApplicable in toolchain.notApplicable { _ = try verifiedData(for: nonApplicable.reason, beneath: root) }
    guard provenance.bridgeClass == "SwiftTLA.PublicWorkflowParserBuilderAdapterV1" else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: provenance.caseID, field: "bridge identity")
    }
  }

  private func verifyObservation(_ observation: PublicWorkflowCanonicalObservationV1, equals expected: Data,
                                 reference: CoreEvidenceReferenceV1) throws {
    let actual = try canonicalData(observation)
    guard actual == expected, SHA256V1.hex(actual) == reference.sha256 else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: reference.path, field: "generated observation")
    }
  }

  private func evidenceBinding(for declaredCase: PublicWorkflowConformanceCaseV1,
                               correlation: PublicWorkflowCaseRunCorrelationV1,
                               parserEvidence: CoreEvidenceReferenceV1,
                               builderEvidence: CoreEvidenceReferenceV1) throws -> (parser: PublicWorkflowEvidenceBindingV1, builder: PublicWorkflowEvidenceBindingV1) {
    let makeBinding: (CoreEvidenceReferenceV1) throws -> PublicWorkflowEvidenceBindingV1 = { evidence in
      try PublicWorkflowEvidenceBindingV1(caseID: declaredCase.id, gateRunID: correlation.gateRunID,
        evidenceRunID: correlation.comparisonRunID, sourceInput: declaredCase.sourceInput,
        configuration: declaredCase.configuration, provenance: declaredCase.provenance, evidence: evidence)
    }
    return (try makeBinding(parserEvidence), try makeBinding(builderEvidence))
  }

  private func observeParser(source: String, name: String) throws -> PublicWorkflowCanonicalObservationV1 {
    let syntax = Parser.parse(source: source)
    guard let closure = syntax.statements.first?.item.as(ClosureExprSyntax.self) else {
      return try unavailableObservation("parser:no top-level specification closure")
    }
    let parsed = SpecParser.parseSpecClosure(closure)
    let diagnostics = parsed.diagnostics.map { "parser:\($0.message)" }
    let parsedSpec = TLASpec(name: name,
      variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
      constants: parsed.constants,
      actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body, binding: $0.binding) },
      invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
      temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) }, fairness: parsed.fairness)
    return try observe(spec: parsedSpec, diagnostics: diagnostics)
  }

  private func observe(spec: TLASpec, diagnostics: [String]) throws -> PublicWorkflowCanonicalObservationV1 {
    do {
      return try canonicalObservation(spec: spec, run: try SwiftGraphAdapterV1().adapt(ModelChecker(spec: spec).explore()), diagnostics: diagnostics)
    } catch {
      return try unavailableObservation("evaluation:\(String(describing: error))", diagnostics: diagnostics)
    }
  }

  private func canonicalObservation(spec: TLASpec, run: CanonicalRunV1, diagnostics: [String]) throws -> PublicWorkflowCanonicalObservationV1 {
    let graph = run.graph
    let result = outcomeDetails(run.outcome)
    return try PublicWorkflowCanonicalObservationV1(
      initialStates: graph.initialStateKeys.sorted().map(\.canonicalEncoding).isEmpty ? ["unavailable:no initial state"] : graph.initialStateKeys.sorted().map(\.canonicalEncoding),
      reachableStates: graph.states.keys.sorted().map(\.canonicalEncoding),
      labeledTransitions: graph.edgeOccurrences.flatMap { edge, occurrences in Array(repeating: edge.canonicalEncoding, count: occurrences) }.sorted(),
      enabledTransitions: graph.observations.flatMap { state, observation in observation.enabledActions.map { "enabled:\(state.canonicalEncoding):\($0)" } }.sorted(),
      properties: structuralProperties(spec: spec) + ["outcome:\(result.outcome)"],
      deadlocks: graph.observations.compactMap { state, observation in observation.isTerminal ? state.canonicalEncoding : nil }.sorted(),
      failures: result.failure.map { [$0] } ?? [], diagnostics: (diagnostics + result.diagnostic).sorted(),
      trace: run.traces.flatMap { trace in trace.steps.map { "\(trace.id):\($0.state.canonicalEncoding):\($0.action)" } }.sorted().nilIfEmpty)
  }

  private func structuralProperties(spec: TLASpec) -> [String] {
    let variables = spec.variables.map { "\($0.name)=\(CanonicalValueV1($0.initial).canonicalEncoding)" }.sorted()
    return [
      "variables:\(variables.joined(separator: ","))",
      "actions:\(spec.actions.map { "\($0.name):\($0.body)" }.sorted().joined(separator: ","))",
      "invariants:\(spec.invariants.map { "\($0.name):\($0.body)" }.sorted().joined(separator: ","))",
      "temporal:\(spec.temporalProperties.map(\.description).sorted().joined(separator: ","))",
      "fairness:\(spec.fairness.map(\.description).sorted().joined(separator: ","))",
      "deadlockCheck:\(spec.checkDeadlock)"
    ]
  }

  private func outcomeDetails(_ outcome: CanonicalOutcomeV1) -> (outcome: String, failure: String?, diagnostic: [String]) {
    switch outcome {
    case .exhaustiveSuccess: return ("exhaustiveSuccess", nil, [])
    case .invariantViolation(let invariant): return ("invariantViolation", "invariant:\(invariant)", ["checker:invariant violation"])
    case .deadlock(let state): return ("deadlock", "deadlock:\(state.canonicalEncoding)", ["checker:deadlock"])
    case .incomplete(let reason): return ("incomplete", "incomplete:\(reason)", ["checker:incomplete"])
    case .executionError(let message): return ("executionError", "evaluation:\(message)", ["checker:execution error"])
    }
  }

  private func unavailableObservation(_ failure: String, diagnostics: [String] = []) throws -> PublicWorkflowCanonicalObservationV1 {
    try PublicWorkflowCanonicalObservationV1(initialStates: ["unavailable"], reachableStates: [], labeledTransitions: [],
      enabledTransitions: [], properties: ["outcome:unavailable"], deadlocks: [], failures: [failure], diagnostics: (diagnostics + [failure]).sorted())
  }

  private func verifiedData(for reference: CoreEvidenceReferenceV1, beneath root: URL) throws -> Data {
    let url = try resolved(root.appendingPathComponent(reference.path), beneath: root)
    let data = try Data(contentsOf: url)
    guard SHA256V1.hex(data) == reference.sha256 else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: reference.path, field: "SHA-256")
    }
    return data
  }

  private func validatedDirectory(_ url: URL) throws -> URL {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: url.path, field: "project root")
    }
    return resolved
  }

  private func resolved(_ url: URL, beneath root: URL) throws -> URL {
    guard !url.path.hasPrefix("/") || url.path.hasPrefix(root.path + "/") || url == root else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: url.path, field: "path outside project root")
    }
    let candidate = url.path.hasPrefix("/") ? url : root.appendingPathComponent(url.path)
    let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
    guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: url.path, field: "path escape")
    }
    return resolved
  }

  private func writableOutputDirectory(_ output: URL, beneath root: URL) throws -> URL {
    let path = try resolved(output, beneath: root)
    guard !FileManager.default.fileExists(atPath: path.path) else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: path.path, field: "output already exists")
    }
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return path
  }

  private func reference(for url: URL, beneath root: URL, data: Data? = nil) throws -> CoreEvidenceReferenceV1 {
    let url = try resolved(url, beneath: root)
    let relative = String(url.path.dropFirst(root.path.count + (url.path == root.path ? 0 : 1)))
    return try CoreEvidenceReferenceV1(path: relative, sha256: SHA256V1.hex(try data ?? Data(contentsOf: url)))
  }

  private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value) + Data([0x0A])
  }

  private func writeCanonical<T: Encodable>(_ value: T, to url: URL) throws { try canonicalData(value).write(to: url, options: .atomic) }
}

private extension Array where Element == String { var nilIfEmpty: [String]? { isEmpty ? nil : self } }
