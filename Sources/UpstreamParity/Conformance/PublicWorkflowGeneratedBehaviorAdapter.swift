import Foundation
import SwiftTLA

public enum PublicWorkflowGeneratedBehaviorAuthority: String, Codable, Sendable {
  case diagnosticOnly
}

public struct PublicWorkflowGeneratedFixtureManifest: Equatable, Codable, Sendable {
  public let id: String
  public let sourceInput: CoreEvidenceReference
  public let configuration: CoreEvidenceReference
  public let semanticCitations: [String]
  public let provenance: CoreDivergenceProvenance
  public let builderEvidence: CoreEvidenceReference
  public let generatedEvidence: CoreEvidenceReference
  public let actionNames: [String]
  public let maxStates: Int
  public let expectedOutcome: PublicWorkflowExpectedOutcome

  public init(
    id: String,
    sourceInput: CoreEvidenceReference,
    configuration: CoreEvidenceReference,
    semanticCitations: [String],
    provenance: CoreDivergenceProvenance,
    builderEvidence: CoreEvidenceReference,
    generatedEvidence: CoreEvidenceReference,
    actionNames: [String],
    maxStates: Int,
    expectedOutcome: PublicWorkflowExpectedOutcome
  ) throws {
    self.id = id
    self.sourceInput = sourceInput
    self.configuration = configuration
    self.semanticCitations = semanticCitations
    self.provenance = provenance
    self.builderEvidence = builderEvidence
    self.generatedEvidence = generatedEvidence
    self.actionNames = actionNames
    self.maxStates = maxStates
    self.expectedOutcome = expectedOutcome
    try validate()
  }

  public func validate() throws {
    try sourceInput.validate()
    try configuration.validate()
    try provenance.validate()
    try builderEvidence.validate()
    try generatedEvidence.validate()
    guard !id.isEmpty, provenance.caseID == id, !semanticCitations.isEmpty,
          semanticCitations.allSatisfy({ !$0.isEmpty }), !actionNames.isEmpty,
          actionNames.allSatisfy({ !$0.isEmpty }), Set(actionNames).count == actionNames.count,
          maxStates > 0 else {
      throw PublicWorkflowGovernanceError.invalidField(record: id, field: "generated fixture manifest")
    }
  }

  public func validateArtifacts(relativeTo root: URL) throws {
    let source = try resolved(sourceInput, relativeTo: root)
    _ = try resolved(configuration, relativeTo: root)
    _ = try resolved(builderEvidence, relativeTo: root)
    _ = try resolved(generatedEvidence, relativeTo: root)
    guard provenance.moduleSHA256 == sourceInput.sha256,
          provenance.cfgSHA256 == self.configuration.sha256,
          provenance.argumentsSHA256 == self.configuration.sha256 else {
      throw PublicWorkflowGovernanceError.inconsistentReference(
        record: id, field: "generated fixture provenance binding")
    }
    _ = source
  }

  private func resolved(_ reference: CoreEvidenceReference, relativeTo root: URL) throws -> URL {
    let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = canonicalRoot.appendingPathComponent(reference.path).standardizedFileURL.resolvingSymlinksInPath()
    guard candidate.path.hasPrefix(canonicalRoot.path + "/"),
          FileManager.default.fileExists(atPath: candidate.path),
          SHA256.hex(try Data(contentsOf: candidate)) == reference.sha256 else {
      throw PublicWorkflowGovernanceError.inconsistentReference(
        record: id, field: "generated fixture artifact \(reference.path)")
    }
    return candidate
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, sourceInput, configuration, semanticCitations, provenance, builderEvidence, generatedEvidence
    case actionNames, maxStates, expectedOutcome
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      sourceInput: try container.decode(CoreEvidenceReference.self, forKey: .sourceInput),
      configuration: try container.decode(CoreEvidenceReference.self, forKey: .configuration),
      semanticCitations: try container.decode([String].self, forKey: .semanticCitations),
      provenance: try container.decode(CoreDivergenceProvenance.self, forKey: .provenance),
      builderEvidence: try container.decode(CoreEvidenceReference.self, forKey: .builderEvidence),
      generatedEvidence: try container.decode(CoreEvidenceReference.self, forKey: .generatedEvidence),
      actionNames: try container.decode([String].self, forKey: .actionNames),
      maxStates: try container.decode(Int.self, forKey: .maxStates),
      expectedOutcome: try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .expectedOutcome))
  }
}

public struct PublicWorkflowGeneratedBehaviorManifest: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowGeneratedBehaviorManifest"
  public let schema: String
  public let authority: PublicWorkflowGeneratedBehaviorAuthority
  public let fixtures: [PublicWorkflowGeneratedFixtureManifest]
  public let toolchain: PublicWorkflowGeneratedBehaviorToolchain

  public init(
    authority: PublicWorkflowGeneratedBehaviorAuthority,
    fixtures: [PublicWorkflowGeneratedFixtureManifest],
    toolchain: PublicWorkflowGeneratedBehaviorToolchain
  ) throws {
    try self.init(schema: Self.schema, authority: authority, fixtures: fixtures, toolchain: toolchain)
  }

  public init(
    schema: String,
    authority: PublicWorkflowGeneratedBehaviorAuthority,
    fixtures: [PublicWorkflowGeneratedFixtureManifest],
    toolchain: PublicWorkflowGeneratedBehaviorToolchain
  ) throws {
    guard schema == Self.schema, authority == .diagnosticOnly, !fixtures.isEmpty else {
      throw PublicWorkflowGovernanceError.invalidSchema(schema)
    }
    try toolchain.validate()
    var ids = Set<String>()
    for fixture in fixtures {
      try fixture.validate()
      guard ids.insert(fixture.id).inserted else {
        throw PublicWorkflowGovernanceError.duplicateID(kind: "generated fixture", id: fixture.id)
      }
    }
    self.schema = schema
    self.authority = authority
    self.fixtures = fixtures
    self.toolchain = toolchain
  }

  public static func load(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }

  public func validateArtifacts(relativeTo root: URL) throws {
    for fixture in fixtures {
      try fixture.validateArtifacts(relativeTo: root)
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, authority, fixtures, toolchain }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: try container.decode(String.self, forKey: .schema),
      authority: try container.decode(PublicWorkflowGeneratedBehaviorAuthority.self, forKey: .authority),
      fixtures: try container.decode([PublicWorkflowGeneratedFixtureManifest].self, forKey: .fixtures),
      toolchain: try container.decode(PublicWorkflowGeneratedBehaviorToolchain.self, forKey: .toolchain))
  }
}

public struct PublicWorkflowGeneratedBehaviorToolchain: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowGeneratedBehaviorToolchain"

  public struct Entry: Equatable, Codable, Sendable {
    public let id: String
    public let evidence: CoreEvidenceReference

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, evidence }

    public init(id: String, evidence: CoreEvidenceReference) throws {
      self.id = id
      self.evidence = evidence
      try evidence.validate()
    }

    public init(from decoder: Decoder) throws {
      let container = try PublicWorkflowDecoding.container(decoder, keyedBy: CodingKeys.self)
      try self.init(id: try container.decode(String.self, forKey: .id), evidence: try container.decode(CoreEvidenceReference.self, forKey: .evidence))
    }
  }

  public let schema: String
  public let dependencies: [Entry]
  public let notApplicable: [Entry]

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, dependencies, notApplicable }

  public init(schema: String, dependencies: [Entry], notApplicable: [Entry]) throws {
    self.schema = schema
    self.dependencies = dependencies
    self.notApplicable = notApplicable
    try validate()
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: try container.decode(String.self, forKey: .schema),
      dependencies: try container.decode([Entry].self, forKey: .dependencies),
      notApplicable: try container.decode([Entry].self, forKey: .notApplicable))
  }

  public func validate() throws {
    guard schema == Self.schema,
          Set(dependencies.map(\.id)) == ["adapter", "macro", "package", "packageResolved"],
          dependencies.count == 4,
          Set(notApplicable.map(\.id)) == ["bridge", "java", "tlc"],
          notApplicable.count == 3 else {
      throw PublicWorkflowGovernanceError.invalidField(record: "generated behavior toolchain", field: "identity coverage")
    }
  }

  func dependency(_ id: String) -> CoreEvidenceReference {
    dependencies.first(where: { $0.id == id })!.evidence
  }

  func nonApplicable(_ id: String) -> CoreEvidenceReference {
    notApplicable.first(where: { $0.id == id })!.evidence
  }
}

struct PublicWorkflowGeneratedMachineHarness {
  let initialStates: [TLAStateProjection]
  let actions: [PublicWorkflowGeneratedAction]
  let apply: (TLAStateProjection, ActionID) -> GeneratedActionResult
  let propertyOutcomes: (TLAStateProjection) -> [CompiledPropertyOutcome]

  init(
    initialStates: [TLAStateProjection],
    actions: [PublicWorkflowGeneratedAction],
    apply: @escaping (TLAStateProjection, ActionID) -> GeneratedActionResult,
    propertyOutcomes: @escaping (TLAStateProjection) -> [CompiledPropertyOutcome]
  ) {
    self.initialStates = initialStates
    self.actions = actions
    self.apply = apply
    self.propertyOutcomes = propertyOutcomes
  }
}

struct PublicWorkflowGeneratedAction: Hashable, Sendable {
  let id: ActionID
  let renderedName: String
}

enum GeneratedActionResult: Equatable, Sendable {
  case enabled(successors: [TLAStateProjection])
  case disabled
  case evaluationFailed(GeneratedActionDiagnostic)
  case evaluationUnavailable(GeneratedActionDiagnostic)
}

struct GeneratedActionDiagnostic: Equatable, Sendable {
  enum Code: String, Equatable, Sendable {
    case actionError
    case evaluationError
    case evaluatorUnavailable
  }

  let code: Code
  let message: String
}

public struct PublicWorkflowGeneratedFixtureConfiguration: Codable, Sendable {
  public static let schema = "PublicWorkflowGeneratedFixtureConfiguration"
  public let schema: String
  public let fixtureID: String
  public let maxStates: Int
  public let actionNames: [String]
  public let expectedOutcome: PublicWorkflowExpectedOutcome

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, fixtureID, maxStates, actionNames, expectedOutcome
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecoding.container(decoder, keyedBy: CodingKeys.self)
    schema = try container.decode(String.self, forKey: .schema)
    fixtureID = try container.decode(String.self, forKey: .fixtureID)
    maxStates = try container.decode(Int.self, forKey: .maxStates)
    actionNames = try container.decode([String].self, forKey: .actionNames)
    expectedOutcome = try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .expectedOutcome)
    guard schema == Self.schema, !fixtureID.isEmpty, maxStates > 0,
          !actionNames.isEmpty, Set(actionNames).count == actionNames.count else {
      throw PublicWorkflowGovernanceError.invalidField(record: fixtureID, field: "generated fixture configuration")
    }
  }
}

public struct PublicWorkflowGeneratedBehaviorRun: Codable, Sendable {
  public static let schema = "PublicWorkflowGeneratedBehaviorRun"
  public let schema: String
  public let manifest: CoreEvidenceReference
  public let comparison: PublicWorkflowComparison
  public let builderObservation: CoreEvidenceReference
  public let generatedObservation: CoreEvidenceReference
  public let mismatchFingerprint: String?

  public init(
    manifest: CoreEvidenceReference,
    comparison: PublicWorkflowComparison,
    builderObservation: CoreEvidenceReference,
    generatedObservation: CoreEvidenceReference,
    mismatchFingerprint: String?
  ) {
    self.schema = Self.schema
    self.manifest = manifest
    self.comparison = comparison
    self.builderObservation = builderObservation
    self.generatedObservation = generatedObservation
    self.mismatchFingerprint = mismatchFingerprint
  }
}

public struct PublicWorkflowGeneratedBehaviorAdapter: Sendable {
  public init() {}

  @discardableResult
  public func run(
    manifestURL: URL,
    projectRoot: URL,
    outputDirectory: URL,
    correlation: PublicWorkflowCaseRunCorrelation
  ) throws -> PublicWorkflowGeneratedBehaviorRun {
    let root = try validatedDirectory(projectRoot)
    let manifestURL = try resolved(manifestURL, beneath: root)
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try PublicWorkflowGeneratedBehaviorManifest.load(manifestData)
    guard let fixture = manifest.fixtures.first(where: { $0.id == correlation.caseID }) else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: correlation.caseID, field: "generated fixture selection")
    }

    let sourceData = try verifiedData(for: fixture.sourceInput, beneath: root)
    let configurationData = try verifiedData(for: fixture.configuration, beneath: root)
    let expectedBuilderData = try verifiedData(for: fixture.builderEvidence, beneath: root)
    let expectedGeneratedData = try verifiedData(for: fixture.generatedEvidence, beneath: root)
    try validateToolchain(manifest.toolchain, provenance: fixture.provenance, beneath: root)
    try validateProvenance(fixture.provenance, source: sourceData, configuration: configurationData, toolchain: manifest.toolchain)
    let configuration = try JSONDecoder().decode(PublicWorkflowGeneratedFixtureConfiguration.self, from: configurationData)
    guard configuration.fixtureID == fixture.id,
          configuration.maxStates == fixture.maxStates,
          configuration.actionNames.sorted() == fixture.actionNames.sorted(),
          configuration.expectedOutcome == fixture.expectedOutcome else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: fixture.id, field: "generated fixture configuration")
    }

    let compiledFixture = try PublicWorkflowGeneratedFixtureRegistry.fixture(id: fixture.id)
    guard compiledFixture.machine.actions.map(\.renderedName).sorted() == fixture.actionNames.sorted(),
          !compiledFixture.machine.initialStates.isEmpty else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: fixture.id, field: "compiled generated fixture")
    }
    let declaredCase = try declaredCase(for: fixture)
    let builder = try observeBuilder(spec: compiledFixture.builderSpec, maxStates: fixture.maxStates)
    let generated = try observeGenerated(machine: compiledFixture.machine, maxStates: fixture.maxStates)
    try verifyObservation(builder, equals: expectedBuilderData, reference: fixture.builderEvidence)
    try verifyObservation(generated, equals: expectedGeneratedData, reference: fixture.generatedEvidence)
    let outcome: PublicWorkflowExpectedOutcome = generated == builder ? .exact : .difference
    guard outcome == fixture.expectedOutcome else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: fixture.id, field: "generated behavior expected outcome")
    }
    let diagnosticCode: PublicWorkflowDiagnosticCode = outcome == .exact ? .exactAgreement : .observationDifference
    let builderBinding = try binding(
      case: declaredCase, correlation: correlation, evidence: fixture.builderEvidence)
    let generatedBinding = try binding(
      case: declaredCase, correlation: correlation, evidence: fixture.generatedEvidence)
    let comparison = try PublicWorkflowComparison(
      caseID: declaredCase.id,
      correlation: correlation,
      left: generated,
      right: builder,
      outcome: outcome,
      diagnosticCode: diagnosticCode,
      leftBinding: generatedBinding,
      rightBinding: builderBinding)
    let output = try writableOutputDirectory(outputDirectory, beneath: root)
    let builderURL = output.appendingPathComponent("builder-observation.json")
    let generatedURL = output.appendingPathComponent("generated-observation.json")
    let comparisonURL = output.appendingPathComponent("comparison.json")
    try writeCanonical(builder, to: builderURL)
    try writeCanonical(generated, to: generatedURL)
    try writeCanonical(comparison, to: comparisonURL)
    let fingerprint = outcome == .difference ? try stableMismatchFingerprint(generated: generated, builder: builder) : nil
    let run = PublicWorkflowGeneratedBehaviorRun(
      manifest: try reference(for: manifestURL, beneath: root, data: manifestData),
      comparison: comparison,
      builderObservation: try reference(for: builderURL, beneath: root),
      generatedObservation: try reference(for: generatedURL, beneath: root),
      mismatchFingerprint: fingerprint)
    try writeCanonical(run, to: output.appendingPathComponent("run.json"))
    return run
  }

  private func binding(
    case declaredCase: PublicWorkflowConformanceCase,
    correlation: PublicWorkflowCaseRunCorrelation,
    evidence: CoreEvidenceReference
  ) throws -> PublicWorkflowEvidenceBinding {
    try PublicWorkflowEvidenceBinding(
      caseID: declaredCase.id,
      gateRunID: correlation.gateRunID,
      evidenceRunID: correlation.comparisonRunID,
      sourceInput: declaredCase.sourceInput,
      configuration: declaredCase.configuration,
      provenance: declaredCase.provenance,
      evidence: evidence)
  }

  private func declaredCase(for fixture: PublicWorkflowGeneratedFixtureManifest) throws -> PublicWorkflowConformanceCase {
    try PublicWorkflowConformanceCase(
      id: fixture.id,
      category: .generatedBehavior,
      publicName: "bounded generated fixture \(fixture.id)",
      finiteBounds: try CoreFiniteBounds(summary: "generated fixture bound", limits: ["states": fixture.maxStates]),
      semanticCitations: fixture.semanticCitations,
      provenance: fixture.provenance,
      sourceInput: fixture.sourceInput,
      configuration: fixture.configuration,
      expectedOutcome: fixture.expectedOutcome,
      authorityBoundary: .publishedSemantics)
  }

  private func validateProvenance(
    _ provenance: CoreDivergenceProvenance,
    source: Data,
    configuration: Data,
    toolchain: PublicWorkflowGeneratedBehaviorToolchain
  ) throws {
    guard provenance.moduleSHA256 == SHA256.hex(source),
          provenance.cfgSHA256 == SHA256.hex(configuration),
          provenance.argumentsSHA256 == SHA256.hex(configuration),
          provenance.tlcTag == "not-applicable-generated-behavior",
          provenance.tlcCommit == "not-applicable-generated-behavior",
          provenance.tlcJarSHA256 == toolchain.nonApplicable("tlc").sha256,
          provenance.javaDistribution == "not-applicable-generated-behavior",
          provenance.javaVersion == "not-applicable-generated-behavior",
          provenance.javaArchiveSHA256 == toolchain.nonApplicable("java").sha256,
          provenance.bridgeClass == "SwiftTLA.PublicWorkflowGeneratedFixtureRegistry",
          provenance.bridgeSourceSHA256 == fixtureRegistryDigest(from: source),
          provenance.bridgeBinarySHA256 == toolchain.nonApplicable("bridge").sha256 else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: provenance.caseID, field: "generated source/configuration provenance")
    }
  }

  private func fixtureRegistryDigest(from source: Data) -> String {
    SHA256.hex(source)
  }

  private func validateToolchain(
    _ toolchain: PublicWorkflowGeneratedBehaviorToolchain,
    provenance: CoreDivergenceProvenance,
    beneath root: URL
  ) throws {
    for dependency in toolchain.dependencies { _ = try verifiedData(for: dependency.evidence, beneath: root) }
    for reason in toolchain.notApplicable { _ = try verifiedData(for: reason.evidence, beneath: root) }
    guard provenance.bridgeClass == "SwiftTLA.PublicWorkflowGeneratedFixtureRegistry" else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: provenance.caseID, field: "compiled fixture registry identity")
    }
  }

  private func verifyObservation(
    _ observation: PublicWorkflowCanonicalObservation,
    equals expected: Data,
    reference: CoreEvidenceReference
  ) throws {
    let retained = try JSONDecoder().decode(PublicWorkflowCanonicalObservation.self, from: expected)
    guard observation == retained else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: reference.path, field: "computed canonical observation")
    }
  }

  private func verifiedData(for reference: CoreEvidenceReference, beneath root: URL) throws -> Data {
    let url = try resolved(root.appendingPathComponent(reference.path), beneath: root)
    let data = try Data(contentsOf: url)
    guard SHA256.hex(data) == reference.sha256 else {
      throw PublicWorkflowGovernanceError.inconsistentReference(record: reference.path, field: "SHA-256")
    }
    return data
  }

  private func validatedDirectory(_ url: URL) throws -> URL {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw PublicWorkflowGovernanceError.invalidField(record: url.path, field: "project root")
    }
    return resolved
  }

  private func resolved(_ url: URL, beneath root: URL) throws -> URL {
    let candidate = url.path.hasPrefix("/") ? url : root.appendingPathComponent(url.path)
    var existing = candidate
    var suffix = [String]()
    while !FileManager.default.fileExists(atPath: existing.path) {
      let parent = existing.deletingLastPathComponent()
      guard parent != existing else { break }
      suffix.append(existing.lastPathComponent)
      existing = parent
    }
    let resolved = suffix.reversed().reduce(existing.resolvingSymlinksInPath().standardizedFileURL) {
      $0.appendingPathComponent($1)
    }.standardizedFileURL
    guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
      let field = url.path.hasPrefix("/") ? "path outside project root" : "path escape"
      throw PublicWorkflowGovernanceError.invalidField(record: url.path, field: field)
    }
    return resolved
  }

  private func writableOutputDirectory(_ output: URL, beneath root: URL) throws -> URL {
    let path = try resolved(output, beneath: root)
    guard !FileManager.default.fileExists(atPath: path.path) else {
      throw PublicWorkflowGovernanceError.invalidField(record: path.path, field: "output already exists")
    }
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return path
  }

  private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private func stableMismatchFingerprint(
    generated: PublicWorkflowCanonicalObservation,
    builder: PublicWorkflowCanonicalObservation
  ) throws -> String {
    struct Difference: Encodable {
      let generated: PublicWorkflowCanonicalObservation
      let builder: PublicWorkflowCanonicalObservation
    }
    return SHA256.hex(try canonicalData(Difference(generated: generated, builder: builder)))
  }

  private func writeCanonical<T: Encodable>(_ value: T, to url: URL) throws {
    try canonicalData(value).write(to: url, options: .atomic)
  }

  private func reference(for url: URL, beneath root: URL, data: Data? = nil) throws -> CoreEvidenceReference {
    let resolved = try resolved(url, beneath: root)
    let retained = try data ?? Data(contentsOf: resolved)
    let prefix = root.path + "/"
    guard resolved.path.hasPrefix(prefix) else {
      throw PublicWorkflowGovernanceError.invalidField(record: resolved.path, field: "project-relative evidence")
    }
    return try CoreEvidenceReference(path: String(resolved.path.dropFirst(prefix.count)), sha256: SHA256.hex(retained))
  }

  private func observeBuilder(spec: TLASpec, maxStates: Int) throws -> PublicWorkflowCanonicalObservation {
    do {
      let compilation = try spec.compile()
      let run = try SwiftGraphAdapter().adapt(ModelChecker(compilation: compilation, maxStates: maxStates).explore())
      return try observation(
        graph: run.graph,
        outcome: run.outcome,
        diagnostics: run.errors.map { "builder:\($0.code):\($0.message)" },
        traces: run.traces,
        propertyOutcomes: compilation.propertyOutcomes(in:))
    } catch {
      return try unavailableObservation("builder:\(String(describing: error))")
    }
  }

  private func canonicalState(from projection: TLAStateProjection) throws -> CanonicalState {
    let bindings = Dictionary(uniqueKeysWithValues: projection.entries.map {
      ($0.token.description, CanonicalValue($0.value))
    })
    return CanonicalState(bindings: bindings)
  }

  private func observeGenerated(
    machine: PublicWorkflowGeneratedMachineHarness,
    maxStates: Int
  ) throws -> PublicWorkflowCanonicalObservation {
    var queue: [TLAStateProjection] = []
    var seen = Set<CanonicalStateKey>()
    var states: [CanonicalStateKey: CanonicalState] = [:]
    var initial = [CanonicalState]()
    var edges = [CanonicalEdge]()
    var predecessors: [CanonicalStateKey: (CanonicalStateKey, String)] = [:]
    var failures = [String]()
    var diagnostics = [String]()
    var failureTrace: [String]?

    for state in machine.initialStates {
      let canonical = try canonicalState(from: state)
      guard seen.insert(canonical.key).inserted else { continue }
      initial.append(canonical)
      states[canonical.key] = canonical
      queue.append(state)
    }

    var index = 0
    while index < queue.count {
      guard index < maxStates else {
        failures.append("generated:depthExceeded:\(maxStates)")
        diagnostics.append("generated:bounded exploration incomplete")
        break
      }
      let state = queue[index]
      index += 1
      let source = try canonicalState(from: state)
      for action in machine.actions.sorted(by: { $0.renderedName < $1.renderedName }) {
        switch machine.apply(state, action.id) {
        case .enabled(let successors):
          for successor in successors {
            let target = try canonicalState(from: successor)
            edges.append(CanonicalEdge(source: source.key, action: action.renderedName, target: target.key))
            if seen.insert(target.key).inserted {
              states[target.key] = target
              predecessors[target.key] = (source.key, action.renderedName)
              queue.append(successor)
            }
          }
        case .disabled:
          continue
        case .evaluationFailed(let diagnostic):
          failures.append("generated:evaluationFailed:\(action.renderedName):\(diagnostic.code.rawValue):\(diagnostic.message)")
          diagnostics.append("generated:evaluation failed")
        case .evaluationUnavailable(let diagnostic):
          failures.append("generated:evaluationUnavailable:\(action.renderedName):\(diagnostic.code.rawValue):\(diagnostic.message)")
          diagnostics.append("generated:evaluation unavailable")
        }
        if failureTrace == nil, !failures.isEmpty {
          failureTrace = trace(to: source.key, predecessors: predecessors)
        }
      }
    }

    let graph = try CanonicalGraph(initialStates: initial, states: Array(states.values), edges: edges)
    let outcome: CanonicalOutcome = failures.isEmpty ? .exhaustiveSuccess : .executionError(failures.sorted().joined(separator: "|"))
    return try observation(
      graph: graph,
      outcome: outcome,
      diagnostics: diagnostics,
      traces: [],
      propertyOutcomes: machine.propertyOutcomes,
      explicitFailures: failures,
      explicitTrace: failureTrace,
      traceForState: { state in self.trace(to: state, predecessors: predecessors) })
  }

  private func observation(
    graph: CanonicalGraph,
    outcome: CanonicalOutcome,
    diagnostics: [String],
    traces: [CanonicalTrace],
    propertyOutcomes: (TLAStateProjection) -> [CompiledPropertyOutcome],
    explicitFailures: [String] = [],
    explicitTrace: [String]? = nil,
    traceForState: ((CanonicalStateKey) -> [String])? = nil
  ) throws -> PublicWorkflowCanonicalObservation {
    let outcomeDetails = describe(outcome)
    let properties = propertyProjection(
      graph: graph,
      outcomes: propertyOutcomes,
      traceForState: traceForState ?? { graphTrace(to: $0, in: graph) })
    let labeledTransitions = graph.edgeOccurrences.flatMap { edge, count in
      Array(repeating: edge.canonicalEncoding, count: count)
    }.sorted()
    let enabledTransitions = graph.observations.flatMap { state, observation in
      observation.enabledActions.map { "enabled:\(state.canonicalEncoding):\($0)" }
    }.sorted()
    let traces = traces.flatMap { trace in
      trace.steps.map { "\(trace.id):\($0.state.canonicalEncoding):\($0.action)" }
    }.sorted()
    return try PublicWorkflowCanonicalObservation(
      initialStates: graph.initialStateKeys.sorted().map(\.canonicalEncoding).ifEmpty("unavailable:no initial state"),
      reachableStates: graph.states.keys.sorted().map(\.canonicalEncoding),
      labeledTransitions: labeledTransitions,
      enabledTransitions: enabledTransitions,
      properties: properties.records + ["outcome:\(outcomeDetails.outcome)"],
      deadlocks: graph.observations.compactMap { $0.value.isTerminal ? $0.key.canonicalEncoding : nil }.sorted(),
      failures: (explicitFailures + properties.failures + outcomeDetails.failure).sorted(),
      diagnostics: (diagnostics + properties.diagnostics + outcomeDetails.diagnostics).sorted(),
      trace: explicitTrace ?? properties.trace ?? traces.nilIfEmpty)
  }

  private func unavailableObservation(_ failure: String) throws -> PublicWorkflowCanonicalObservation {
    try PublicWorkflowCanonicalObservation(
      initialStates: ["unavailable"], reachableStates: [], labeledTransitions: [], enabledTransitions: [],
      properties: ["outcome:unavailable"], deadlocks: [], failures: [failure], diagnostics: [failure])
  }

  private func propertyProjection(
    graph: CanonicalGraph,
    outcomes: (TLAStateProjection) -> [CompiledPropertyOutcome],
    traceForState: (CanonicalStateKey) -> [String]
  ) -> (records: [String], failures: [String], diagnostics: [String], trace: [String]?) {
    var records = [String]()
    var failures = [String]()
    var diagnostics = [String]()
    var trace: [String]?
    for state in graph.states.keys.sorted() {
      guard let canonical = graph.states[state] else { continue }
      let projection: TLAStateProjection
      do {
        let entries = try canonical.bindings.map { name, value -> TLAStateProjection.Entry in
          guard let token = TLAStateProjection.Token(validating: name) else {
            throw TLAStateProjectionDiagnostic.invalidKey(path: name)
          }
          return .init(token: token, value: TLAValue(value))
        }
        projection = try TLAStateProjection(validating: entries)
      } catch {
        failures.append("propertyProjectionFailed:\(state.canonicalEncoding):\(error)")
        diagnostics.append("property:projectionFailed")
        trace = trace ?? traceForState(state)
        continue
      }
      for outcome in outcomes(projection) {
        switch outcome {
        case .satisfied(let name):
          records.append("property:\(state.canonicalEncoding):satisfied:\(name)")
        case .violated(let name):
          records.append("property:\(state.canonicalEncoding):violated:\(name)")
          failures.append("propertyViolation:\(state.canonicalEncoding):\(name)")
          diagnostics.append("property:violated:\(name)")
          trace = trace ?? traceForState(state)
        case .evaluationFailed(let name, let diagnostic):
          records.append("property:\(state.canonicalEncoding):evaluationFailed:\(name):\(diagnostic.code.rawValue)")
          failures.append("propertyEvaluationFailed:\(state.canonicalEncoding):\(name):\(diagnostic.message)")
          diagnostics.append("property:evaluationFailed:\(name):\(diagnostic.code.rawValue)")
          trace = trace ?? traceForState(state)
        case .evaluationUnavailable(let name, let diagnostic):
          records.append("property:\(state.canonicalEncoding):evaluationUnavailable:\(name):\(diagnostic.code.rawValue)")
          failures.append("propertyEvaluationUnavailable:\(state.canonicalEncoding):\(name):\(diagnostic.message)")
          diagnostics.append("property:evaluationUnavailable:\(name):\(diagnostic.code.rawValue)")
          trace = trace ?? traceForState(state)
        }
      }
    }
    return (records.sorted(), failures.sorted(), diagnostics.sorted(), trace)
  }

  private func graphTrace(to target: CanonicalStateKey, in graph: CanonicalGraph) -> [String] {
    var queue = graph.initialStateKeys.sorted()
    var predecessors = [CanonicalStateKey: (CanonicalStateKey, String)]()
    var index = 0
    while index < queue.count {
      let state = queue[index]
      index += 1
      if state == target { return trace(to: state, predecessors: predecessors) }
      for edge in graph.edgeOccurrences.keys.sorted() where edge.source == state && predecessors[edge.target] == nil && !graph.initialStateKeys.contains(edge.target) {
        predecessors[edge.target] = (state, edge.action)
        queue.append(edge.target)
      }
    }
    return ["graph:\(target.canonicalEncoding):unreachable"]
  }

  private func describe(_ outcome: CanonicalOutcome) -> (outcome: String, failure: [String], diagnostics: [String]) {
    switch outcome {
    case .exhaustiveSuccess: return ("exhaustiveSuccess", [], [])
    case .invariantViolation(let invariant): return ("invariantViolation", ["invariant:\(invariant)"], ["checker:invariant violation"])
    case .deadlock(let state): return ("deadlock", ["deadlock:\(state.canonicalEncoding)"], ["checker:deadlock"])
    case .incomplete(let reason): return ("incomplete", ["incomplete:\(reason)"], ["checker:incomplete"])
    case .executionError(let message): return ("executionError", ["evaluation:\(message)"], ["checker:execution error"])
    }
  }

  private func trace(
    to state: CanonicalStateKey,
    predecessors: [CanonicalStateKey: (CanonicalStateKey, String)]
  ) -> [String] {
    var steps = ["generated:\(state.canonicalEncoding):init"]
    var cursor = state
    while let predecessor = predecessors[cursor] {
      steps.append("generated:\(predecessor.0.canonicalEncoding):\(predecessor.1)")
      cursor = predecessor.0
    }
    return steps.reversed()
  }
}

private extension Array where Element == String {
  func ifEmpty(_ replacement: String) -> [String] { isEmpty ? [replacement] : self }
  var nilIfEmpty: [String]? { isEmpty ? nil : self }
}

private extension TLAValue {
  init(_ value: CanonicalValue) {
    switch value {
    case .integer(let value): self = .int(value)
    case .boolean(let value): self = .bool(value)
    case .string(let value): self = .string(value)
    case .constant(let value): self = .constant(value)
    case .orderedSet(let values): self = .set(Set(values.map(TLAValue.init)))
    case .orderedTuple(let values): self = .tuple(values.map(TLAValue.init))
    case .orderedRecord(let fields):
      self = .record(TLARecord(fields.map { .init($0.name, TLAValue($0.value)) }))
    case .orderedFunction(let entries):
      self = .function(Dictionary(uniqueKeysWithValues: entries.map { (TLAValue($0.key), TLAValue($0.value)) }))
    }
  }
}
