import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA

/// The exportable, source-controlled parser/builder fixture contract.
///
/// A validation corpus can retain this manifest and its referenced inputs without
/// importing implementation sources. All paths are project-relative and every
/// input is pinned by its SHA-256 digest.
public struct PublicWorkflowParserBuilderManifest: Decodable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderManifest"

  public let schema: String
  public let declaredCase: PublicWorkflowConformanceCase
  public let source: CoreEvidenceReference
  public let configuration: CoreEvidenceReference
  public let parserObservation: CoreEvidenceReference
  public let builderObservation: CoreEvidenceReference
  public let toolchain: PublicWorkflowParserBuilderToolchain

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, declaredCase, source, configuration, parserObservation, builderObservation, toolchain
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    declaredCase = try container.decode(PublicWorkflowConformanceCase.self, forKey: .declaredCase)
    source = try container.decode(CoreEvidenceReference.self, forKey: .source)
    configuration = try container.decode(CoreEvidenceReference.self, forKey: .configuration)
    parserObservation = try container.decode(CoreEvidenceReference.self, forKey: .parserObservation)
    builderObservation = try container.decode(CoreEvidenceReference.self, forKey: .builderObservation)
    toolchain = try container.decode(PublicWorkflowParserBuilderToolchain.self, forKey: .toolchain)
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
      throw ConformanceGovernanceError.inconsistentReference(
        record: declaredCase.id, field: "parser-builder manifest")
    }
  }
}

/// Records every applicable implementation identity as a portable file pin.
/// `notApplicable` deliberately describes tools that this comparison does not
/// execute; their digest fields point to the retained declaration rather than a
/// fabricated tool hash.
public struct PublicWorkflowParserBuilderToolchain: Decodable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderToolchain"
  public let schema: String
  public let dependencies: [Dependency]
  public let notApplicable: [NotApplicable]

  public struct Dependency: Decodable, Sendable {
    public let id: String
    public let evidence: CoreEvidenceReference
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, evidence }
    public init(from decoder: Decoder) throws {
      let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      evidence = try container.decode(CoreEvidenceReference.self, forKey: .evidence)
      try evidence.validate()
    }
  }

  public struct NotApplicable: Decodable, Sendable {
    public let id: String
    public let reason: CoreEvidenceReference
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, reason }
    public init(from decoder: Decoder) throws {
      let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      reason = try container.decode(CoreEvidenceReference.self, forKey: .reason)
      try reason.validate()
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, dependencies, notApplicable }
  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    dependencies = try container.decode([Dependency].self, forKey: .dependencies)
    notApplicable = try container.decode([NotApplicable].self, forKey: .notApplicable)
    try validate()
  }

  public func validate() throws {
    guard schema == Self.schema,
          Set(dependencies.map(\.id)) == ["swiftSyntaxResolution", "swiftTLAPackage", "adapterSource", "evidenceSource"],
          dependencies.count == 4,
          Set(notApplicable.map(\.id)) == ["tlc", "java", "bridgeBinary"],
          notApplicable.count == 3 else {
      throw ConformanceGovernanceError.invalidField(record: "parser-builder toolchain", field: "identity coverage")
    }
  }

  func dependency(_ id: String) throws -> CoreEvidenceReference {
    guard let reference = dependencies.first(where: { $0.id == id })?.evidence else {
      throw ConformanceGovernanceError.invalidField(record: "parser-builder toolchain", field: id)
    }
    return reference
  }

  func nonApplicable(_ id: String) throws -> CoreEvidenceReference {
    guard let reference = notApplicable.first(where: { $0.id == id })?.reason else {
      throw ConformanceGovernanceError.invalidField(record: "parser-builder toolchain", field: id)
    }
    return reference
  }
}

/// A deliberately narrow builder description. It prevents a caller from
/// substituting arbitrary source or a hand-constructed `TLASpec` at comparison
/// time while keeping the fixture portable to a separate validation repository.
public struct PublicWorkflowBoundedCounterConfiguration: Decodable, Sendable {
  public static let schema = "PublicWorkflowBoundedCounterConfiguration"

  public let schema: String
  public let model: String
  public let specificationName: String
  public let variable: String
  public let initialValue: Int
  public let nextValue: Int
  public let upperBound: Int
  public let maximumStateLimit: Int

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, model, specificationName, variable, initialValue, nextValue, upperBound, maximumStateLimit
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    model = try container.decode(String.self, forKey: .model)
    specificationName = try container.decode(String.self, forKey: .specificationName)
    variable = try container.decode(String.self, forKey: .variable)
    initialValue = try container.decode(Int.self, forKey: .initialValue)
    nextValue = try container.decode(Int.self, forKey: .nextValue)
    upperBound = try container.decode(Int.self, forKey: .upperBound)
    maximumStateLimit = try container.decode(Int.self, forKey: .maximumStateLimit)
    try validate()
  }

  public func validate() throws {
    guard schema == Self.schema, model == "boundedCounter", !specificationName.isEmpty,
          variable == "x", initialValue == 0, nextValue > 0, upperBound >= nextValue,
          maximumStateLimit > 0 else {
      throw ConformanceGovernanceError.invalidField(
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

public struct PublicWorkflowParserBuilderRun: Codable, Sendable {
  public static let schema = "PublicWorkflowParserBuilderRun"

  public let schema: String
  public let manifest: CoreEvidenceReference
  public let comparison: PublicWorkflowComparison
  public let parserObservation: CoreEvidenceReference
  public let builderObservation: CoreEvidenceReference

  public init(manifest: CoreEvidenceReference, comparison: PublicWorkflowComparison,
              parserObservation: CoreEvidenceReference, builderObservation: CoreEvidenceReference) {
    self.schema = Self.schema
    self.manifest = manifest
    self.comparison = comparison
    self.parserObservation = parserObservation
    self.builderObservation = builderObservation
  }
}

public struct PublicWorkflowParserBuilderAdapter: Sendable {
  public init() {}

  /// Runs one exported manifest. `projectRoot` is explicit so callers can move
  /// the corpus to SwiftTLA-Validation without relying on this repository's path.
  /// The result is diagnostic until a hosted-CI artifact receipt admits it.
  @discardableResult
  public func run(
    manifestURL: URL,
    projectRoot: URL,
    outputDirectory: URL,
    correlation: PublicWorkflowCaseRunCorrelation
  ) throws -> PublicWorkflowParserBuilderRun {
    let root = try ConformanceEvidence.projectRoot(projectRoot)
    let manifestURL = try ConformanceEvidence.resolve(manifestURL, beneath: root)
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(PublicWorkflowParserBuilderManifest.self, from: manifestData)
    guard correlation.caseID == manifest.declaredCase.id else {
      throw ConformanceGovernanceError.inconsistentReference(record: manifest.declaredCase.id, field: "run correlation")
    }

    let sourceData = try ConformanceEvidence.data(for: manifest.source, beneath: root)
    let configurationData = try ConformanceEvidence.data(for: manifest.configuration, beneath: root)
    let expectedParserData = try ConformanceEvidence.data(for: manifest.parserObservation, beneath: root)
    let expectedBuilderData = try ConformanceEvidence.data(for: manifest.builderObservation, beneath: root)
    try validateToolchain(manifest.toolchain, provenance: manifest.declaredCase.provenance, beneath: root)
    let configuration = try JSONDecoder().decode(PublicWorkflowBoundedCounterConfiguration.self, from: configurationData)
    try validateProvenance(manifest.declaredCase.provenance, source: sourceData, configuration: configurationData,
                           toolchain: manifest.toolchain)

    let parserObservation = try observeParser(
      source: String(decoding: sourceData, as: UTF8.self), configuration: configuration
    )
    let builderObservation = try observe(spec: configuration.makeSpec(), maximumStateLimit: configuration.maximumStateLimit, diagnostics: [])
    try verifyObservation(parserObservation, equals: expectedParserData, reference: manifest.parserObservation)
    try verifyObservation(builderObservation, equals: expectedBuilderData, reference: manifest.builderObservation)

    let outcome: PublicWorkflowExpectedOutcome = parserObservation == builderObservation ? .exact : .difference
    let diagnosticCode: PublicWorkflowDiagnosticCode = outcome == .exact ? .exactAgreement : .observationDifference
    let bindings = try evidenceBinding(for: manifest.declaredCase, correlation: correlation,
                                       parserEvidence: manifest.parserObservation, builderEvidence: manifest.builderObservation)
    let comparison = try PublicWorkflowComparison(
      caseID: manifest.declaredCase.id, correlation: correlation, left: parserObservation, right: builderObservation,
      outcome: outcome, diagnosticCode: diagnosticCode, leftBinding: bindings.parser, rightBinding: bindings.builder)

    let output = try ConformanceEvidence.outputDirectory(outputDirectory, beneath: root)
    try ConformanceEvidence.writeCanonical(parserObservation, to: output.appendingPathComponent("parser-observation.json"), trailingNewline: true)
    try ConformanceEvidence.writeCanonical(builderObservation, to: output.appendingPathComponent("builder-observation.json"), trailingNewline: true)
    try ConformanceEvidence.writeCanonical(comparison, to: output.appendingPathComponent("comparison.json"), trailingNewline: true)
    let run = PublicWorkflowParserBuilderRun(
      manifest: try ConformanceEvidence.reference(for: manifestURL, beneath: root, data: manifestData), comparison: comparison,
      parserObservation: try ConformanceEvidence.reference(for: output.appendingPathComponent("parser-observation.json"), beneath: root),
      builderObservation: try ConformanceEvidence.reference(for: output.appendingPathComponent("builder-observation.json"), beneath: root))
    try ConformanceEvidence.writeCanonical(run, to: output.appendingPathComponent("run.json"), trailingNewline: true)
    return run
  }

  private func validateProvenance(_ provenance: CoreEvidenceProvenance, source: Data, configuration: Data,
                                  toolchain: PublicWorkflowParserBuilderToolchain) throws {
    let tlc = try toolchain.nonApplicable("tlc")
    let java = try toolchain.nonApplicable("java")
    let adapterSource = try toolchain.dependency("adapterSource")
    let bridgeBinary = try toolchain.nonApplicable("bridgeBinary")
    guard provenance.moduleSHA256 == SHA256.hex(source), provenance.cfgSHA256 == SHA256.hex(configuration),
          provenance.argumentsSHA256 == SHA256.hex(configuration),
          provenance.tlcTag == "not-applicable-parser-builder",
          provenance.tlcCommit == "not-applicable-parser-builder",
          provenance.tlcJarSHA256 == tlc.sha256,
          provenance.javaDistribution == "not-applicable-parser-builder",
          provenance.javaVersion == "not-applicable-parser-builder",
          provenance.javaArchiveSHA256 == java.sha256,
          provenance.bridgeSourceSHA256 == adapterSource.sha256,
          provenance.bridgeBinarySHA256 == bridgeBinary.sha256 else {
      throw ConformanceGovernanceError.inconsistentReference(record: provenance.caseID, field: "source/configuration provenance")
    }
  }

  private func validateToolchain(_ toolchain: PublicWorkflowParserBuilderToolchain,
                                 provenance: CoreEvidenceProvenance, beneath root: URL) throws {
    for dependency in toolchain.dependencies { _ = try ConformanceEvidence.data(for: dependency.evidence, beneath: root) }
    for nonApplicable in toolchain.notApplicable { _ = try ConformanceEvidence.data(for: nonApplicable.reason, beneath: root) }
    guard provenance.bridgeClass == "SwiftTLA.PublicWorkflowParserBuilderAdapter" else {
      throw ConformanceGovernanceError.inconsistentReference(record: provenance.caseID, field: "bridge identity")
    }
  }

  private func verifyObservation(_ observation: PublicWorkflowCanonicalObservation, equals expected: Data,
                                 reference: CoreEvidenceReference) throws {
    let actual = try ConformanceEvidence.canonicalData(observation, trailingNewline: true)
    guard actual == expected, SHA256.hex(actual) == reference.sha256 else {
      throw ConformanceGovernanceError.inconsistentReference(record: reference.path, field: "generated observation")
    }
  }

  private func evidenceBinding(for declaredCase: PublicWorkflowConformanceCase,
                               correlation: PublicWorkflowCaseRunCorrelation,
                               parserEvidence: CoreEvidenceReference,
                               builderEvidence: CoreEvidenceReference) throws -> (parser: PublicWorkflowEvidenceBinding, builder: PublicWorkflowEvidenceBinding) {
    let makeBinding: (CoreEvidenceReference) throws -> PublicWorkflowEvidenceBinding = { evidence in
      try PublicWorkflowEvidenceBinding(caseID: declaredCase.id, gateRunID: correlation.gateRunID,
        evidenceRunID: correlation.comparisonRunID, sourceInput: declaredCase.sourceInput,
        configuration: declaredCase.configuration, provenance: declaredCase.provenance, evidence: evidence)
    }
    return (try makeBinding(parserEvidence), try makeBinding(builderEvidence))
  }

  private func observeParser(
    source: String,
    configuration: PublicWorkflowBoundedCounterConfiguration
  ) throws -> PublicWorkflowCanonicalObservation {
    let syntax = Parser.parse(source: source)
    guard let closure = syntax.statements.first?.item.as(ClosureExprSyntax.self) else {
      return try unavailableObservation("parser:no top-level specification closure")
    }
    let parsed = SpecParser.parseSpecClosure(closure)
    let diagnostics = parsed.diagnostics.map { "parser:\($0.message)" }
    let parsedSpec = TLASpec(name: configuration.specificationName,
      variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
      constants: parsed.constants,
      actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body, bindings: $0.bindings) },
      invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
      temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) }, fairness: parsed.fairness)
    return try observe(spec: parsedSpec, maximumStateLimit: configuration.maximumStateLimit, diagnostics: diagnostics)
  }

  private func observe(
    spec: TLASpec,
    maximumStateLimit: Int,
    diagnostics: [String]
  ) throws -> PublicWorkflowCanonicalObservation {
    do {
      return try canonicalObservation(spec: spec, run: try SwiftGraphAdapter().adapt(ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: maximumStateLimit)).explore()), diagnostics: diagnostics)
    } catch {
      return try unavailableObservation("evaluation:\(String(describing: error))", diagnostics: diagnostics)
    }
  }

  private func canonicalObservation(spec: TLASpec, run: CanonicalRun, diagnostics: [String]) throws -> PublicWorkflowCanonicalObservation {
    let graph = run.graph
    let result = outcomeDetails(run.outcome)
    return try PublicWorkflowCanonicalObservation(
      initialStates: graph.initialStateKeys.sorted().map(\.canonicalEncoding).isEmpty ? ["unavailable:no initial state"] : graph.initialStateKeys.sorted().map(\.canonicalEncoding),
      reachableStates: graph.states.keys.sorted().map(\.canonicalEncoding),
      labeledTransitions: graph.edgeOccurrences.flatMap { edge, occurrences in Array(repeating: edge.canonicalEncoding, count: occurrences) }.sorted(),
      enabledTransitions: graph.observations.flatMap { state, observation in observation.enabledActions.map { "enabled:\(state.canonicalEncoding):\($0)" } }.sorted(),
      properties: try structuralProperties(spec: spec) + ["outcome:\(result.outcome)"],
      deadlocks: graph.observations.compactMap { state, observation in observation.isTerminal ? state.canonicalEncoding : nil }.sorted(),
      failures: result.failure.map { [$0] } ?? [], diagnostics: (diagnostics + result.diagnostic).sorted(),
      trace: run.traces.flatMap { trace in trace.steps.map { "\(trace.id):\($0.state.canonicalEncoding):\($0.action)" } }.sorted().nilIfEmpty)
  }

  private func structuralProperties(spec: TLASpec) throws -> [String] {
    let variables = try spec.variables.map { "\($0.name)=\(try CanonicalValue($0.initial).canonicalEncoding)" }.sorted()
    return [
      "variables:\(variables.joined(separator: ","))",
      "actions:\(spec.actions.map { "\($0.name):\($0.body)" }.sorted().joined(separator: ","))",
      "invariants:\(spec.invariants.map { "\($0.name):\($0.body)" }.sorted().joined(separator: ","))",
      "temporal:\(spec.temporalProperties.map(\.description).sorted().joined(separator: ","))",
      "fairness:\(spec.fairness.map(\.description).sorted().joined(separator: ","))",
      "deadlockCheck:\(spec.checkDeadlock)"
    ]
  }

  private func outcomeDetails(_ outcome: CanonicalOutcome) -> (outcome: String, failure: String?, diagnostic: [String]) {
    switch outcome {
    case .exhaustiveSuccess: return ("exhaustiveSuccess", nil, [])
    case .invariantViolation(let invariant): return ("invariantViolation", "invariant:\(invariant)", ["checker:invariant violation"])
    case .deadlock(let state): return ("deadlock", "deadlock:\(state.canonicalEncoding)", ["checker:deadlock"])
    case .incomplete(let reason): return ("incomplete", "incomplete:\(reason)", ["checker:incomplete"])
    case .executionError(let message): return ("executionError", "evaluation:\(message)", ["checker:execution error"])
    }
  }

  private func unavailableObservation(_ failure: String, diagnostics: [String] = []) throws -> PublicWorkflowCanonicalObservation {
    try PublicWorkflowCanonicalObservation(initialStates: ["unavailable"], reachableStates: [], labeledTransitions: [],
      enabledTransitions: [], properties: ["outcome:unavailable"], deadlocks: [], failures: [failure], diagnostics: (diagnostics + [failure]).sorted())
  }

}

private extension Array where Element == String { var nilIfEmpty: [String]? { isEmpty ? nil : self } }
