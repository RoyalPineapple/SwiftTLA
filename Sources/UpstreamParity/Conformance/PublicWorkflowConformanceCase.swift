import Foundation

public enum PublicWorkflowGovernanceErrorV1: Error, Equatable, Sendable {
  case invalidSchema(String)
  case duplicateID(kind: String, id: String)
  case invalidField(record: String, field: String)
  case unknownCaseID(String)
  case unknownDivergenceID(String)
  case inconsistentReference(record: String, field: String)
}

private struct PublicWorkflowAnyCodingKeyV1: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

enum PublicWorkflowDecodingV1 {
  static func container<Key>(
    _ decoder: Decoder, keyedBy keyType: Key.Type
  ) throws -> KeyedDecodingContainer<Key> where Key: CodingKey & CaseIterable {
    let actual = try decoder.container(keyedBy: PublicWorkflowAnyCodingKeyV1.self)
    let known = Set(Key.allCases.map(\.stringValue))
    let unknown = Set(actual.allKeys.map(\.stringValue)).subtracting(known)
    guard unknown.isEmpty else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(
        record: "decode", field: "unknown field \(unknown.sorted().joined(separator: ","))")
    }
    return try decoder.container(keyedBy: keyType)
  }
}

public enum PublicWorkflowCaseCategoryV1: String, Codable, Sendable {
  case annotation
  case parserBuilder
  case generatedBehavior
  case nestedPackage
  case platform
}

public enum PublicWorkflowExpectedOutcomeV1: String, Codable, Sendable {
  case exact
  case difference
  case unavailable
}

public enum PublicWorkflowAuthorityBoundaryV1: String, Codable, Sendable {
  case publishedSemantics
  case executableReference
  case diagnosticSource
}

public enum PublicWorkflowEvidenceStatusV1: String, Codable, Sendable {
  case complete
  case partial
  case unavailable
}

public enum PublicWorkflowDiagnosticCodeV1: String, Codable, Sendable {
  case exactAgreement
  case observationDifference
  case invalidFixtureAccepted
  case evaluationFailed
  case evaluationUnavailable
  case platformValidationFailed
  case evidenceUnavailable
}

public struct PublicWorkflowConformanceCaseV1: Equatable, Codable, Sendable {
  public let id: String
  public let category: PublicWorkflowCaseCategoryV1
  public let publicName: String
  public let finiteBounds: CoreFiniteBoundsV1
  public let semanticCitations: [String]
  public let provenance: CoreDivergenceProvenanceV1
  public let sourceInput: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let expectedOutcome: PublicWorkflowExpectedOutcomeV1
  public let authorityBoundary: PublicWorkflowAuthorityBoundaryV1

  public init(
    id: String,
    category: PublicWorkflowCaseCategoryV1,
    publicName: String,
    finiteBounds: CoreFiniteBoundsV1,
    semanticCitations: [String],
    provenance: CoreDivergenceProvenanceV1,
    sourceInput: CoreEvidenceReferenceV1,
    configuration: CoreEvidenceReferenceV1,
    expectedOutcome: PublicWorkflowExpectedOutcomeV1,
    authorityBoundary: PublicWorkflowAuthorityBoundaryV1
  ) throws {
    self.id = id
    self.category = category
    self.publicName = publicName
    self.finiteBounds = finiteBounds
    self.semanticCitations = semanticCitations
    self.provenance = provenance
    self.sourceInput = sourceInput
    self.configuration = configuration
    self.expectedOutcome = expectedOutcome
    self.authorityBoundary = authorityBoundary
    try validate()
  }

  public func validate() throws {
    try finiteBounds.validate()
    try provenance.validate()
    try sourceInput.validate()
    try configuration.validate()
    guard !id.isEmpty, !publicName.isEmpty, provenance.caseID == id,
          !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }),
          authorityBoundary == .publishedSemantics else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "case declaration")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, category, publicName, finiteBounds, semanticCitations, provenance, sourceInput, configuration
    case expectedOutcome, authorityBoundary
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      category: try container.decode(PublicWorkflowCaseCategoryV1.self, forKey: .category),
      publicName: try container.decode(String.self, forKey: .publicName),
      finiteBounds: try container.decode(CoreFiniteBoundsV1.self, forKey: .finiteBounds),
      semanticCitations: try container.decode([String].self, forKey: .semanticCitations),
      provenance: try container.decode(CoreDivergenceProvenanceV1.self, forKey: .provenance),
      sourceInput: try container.decode(CoreEvidenceReferenceV1.self, forKey: .sourceInput),
      configuration: try container.decode(CoreEvidenceReferenceV1.self, forKey: .configuration),
      expectedOutcome: try container.decode(PublicWorkflowExpectedOutcomeV1.self, forKey: .expectedOutcome),
      authorityBoundary: try container.decode(PublicWorkflowAuthorityBoundaryV1.self, forKey: .authorityBoundary))
  }
}

public struct PublicWorkflowCasesV1: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowCasesV1"
  public let schema: String
  public let cases: [PublicWorkflowConformanceCaseV1]

  public init(cases: [PublicWorkflowConformanceCaseV1]) throws { try self.init(schema: Self.schema, cases: cases) }

  public init(schema: String, cases: [PublicWorkflowConformanceCaseV1]) throws {
    guard schema == Self.schema else { throw PublicWorkflowGovernanceErrorV1.invalidSchema(schema) }
    var ids = Set<String>()
    for record in cases {
      try record.validate()
      guard ids.insert(record.id).inserted else {
        throw PublicWorkflowGovernanceErrorV1.duplicateID(kind: "case", id: record.id)
      }
    }
    self.schema = schema
    self.cases = cases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), cases: try container.decode([PublicWorkflowConformanceCaseV1].self, forKey: .cases))
  }
}

public struct PublicWorkflowCaseRunCorrelationV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let fixtureRunID: UUID
  public let comparisonRunID: UUID

  public init(caseID: String, gateRunID: UUID, fixtureRunID: UUID, comparisonRunID: UUID) throws {
    guard !caseID.isEmpty, Set([gateRunID, fixtureRunID, comparisonRunID]).count == 3 else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "correlation", field: "caseID or run IDs")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.fixtureRunID = fixtureRunID
    self.comparisonRunID = comparisonRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, gateRunID, fixtureRunID, comparisonRunID }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), gateRunID: try container.decode(UUID.self, forKey: .gateRunID), fixtureRunID: try container.decode(UUID.self, forKey: .fixtureRunID), comparisonRunID: try container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

public struct PublicWorkflowEvidenceBindingV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let evidenceRunID: UUID
  public let sourceInput: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let provenance: CoreDivergenceProvenanceV1
  public let evidence: CoreEvidenceReferenceV1

  public init(
    caseID: String, gateRunID: UUID, evidenceRunID: UUID, sourceInput: CoreEvidenceReferenceV1,
    configuration: CoreEvidenceReferenceV1, provenance: CoreDivergenceProvenanceV1,
    evidence: CoreEvidenceReferenceV1
  ) throws {
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.evidenceRunID = evidenceRunID
    self.sourceInput = sourceInput
    self.configuration = configuration
    self.provenance = provenance
    self.evidence = evidence
    try validate()
  }

  public func validate() throws {
    try sourceInput.validate()
    try configuration.validate()
    try provenance.validate()
    try evidence.validate()
    guard !caseID.isEmpty, provenance.caseID == caseID else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: caseID, field: "evidence binding")
    }
  }

  func matches(
    _ declaration: PublicWorkflowConformanceCaseV1, gateRunID: UUID,
    expectedRunID: UUID, evidence: CoreEvidenceReferenceV1
  ) -> Bool {
    caseID == declaration.id && self.gateRunID == gateRunID && evidenceRunID == expectedRunID
      && sourceInput == declaration.sourceInput && configuration == declaration.configuration
      && provenance == declaration.provenance && self.evidence == evidence
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, gateRunID, evidenceRunID, sourceInput, configuration, provenance, evidence
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: try container.decode(String.self, forKey: .caseID),
      gateRunID: try container.decode(UUID.self, forKey: .gateRunID),
      evidenceRunID: try container.decode(UUID.self, forKey: .evidenceRunID),
      sourceInput: try container.decode(CoreEvidenceReferenceV1.self, forKey: .sourceInput),
      configuration: try container.decode(CoreEvidenceReferenceV1.self, forKey: .configuration),
      provenance: try container.decode(CoreDivergenceProvenanceV1.self, forKey: .provenance),
      evidence: try container.decode(CoreEvidenceReferenceV1.self, forKey: .evidence))
  }
}

public struct PublicWorkflowCaseEvidenceV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let correlation: PublicWorkflowCaseRunCorrelationV1
  public let status: PublicWorkflowEvidenceStatusV1
  public let fixture: CoreEvidenceReferenceV1
  public let comparison: CoreEvidenceReferenceV1
  public let provenance: CoreEvidenceReferenceV1
  public let fixtureBinding: PublicWorkflowEvidenceBindingV1
  public let comparisonBinding: PublicWorkflowEvidenceBindingV1
  public let provenanceBinding: PublicWorkflowEvidenceBindingV1
  public let outcome: PublicWorkflowExpectedOutcomeV1
  public let diagnosticCode: PublicWorkflowDiagnosticCodeV1
  public let execution: PublicWorkflowCIExecutionV1

  public init(
    caseID: String, correlation: PublicWorkflowCaseRunCorrelationV1, status: PublicWorkflowEvidenceStatusV1,
    fixture: CoreEvidenceReferenceV1, comparison: CoreEvidenceReferenceV1, provenance: CoreEvidenceReferenceV1,
    fixtureBinding: PublicWorkflowEvidenceBindingV1, comparisonBinding: PublicWorkflowEvidenceBindingV1,
    provenanceBinding: PublicWorkflowEvidenceBindingV1,
    outcome: PublicWorkflowExpectedOutcomeV1, diagnosticCode: PublicWorkflowDiagnosticCodeV1,
    execution: PublicWorkflowCIExecutionV1
  ) throws {
    self.caseID = caseID
    self.correlation = correlation
    self.status = status
    self.fixture = fixture
    self.comparison = comparison
    self.provenance = provenance
    self.fixtureBinding = fixtureBinding
    self.comparisonBinding = comparisonBinding
    self.provenanceBinding = provenanceBinding
    self.outcome = outcome
    self.diagnosticCode = diagnosticCode
    self.execution = execution
    try validate()
  }

  public func validate() throws {
    try fixture.validate()
    try comparison.validate()
    try provenance.validate()
    try fixtureBinding.validate()
    try comparisonBinding.validate()
    try provenanceBinding.validate()
    try execution.validate()
    guard !caseID.isEmpty, correlation.caseID == caseID else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: caseID, field: "correlation")
    }
    guard status == .complete ? outcome != .unavailable && diagnosticCode != .evidenceUnavailable : outcome == .unavailable && diagnosticCode == .evidenceUnavailable else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: caseID, field: "evidence status")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, correlation, status, fixture, comparison, provenance, fixtureBinding, comparisonBinding
    case provenanceBinding, outcome, diagnosticCode, execution
  }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), correlation: try container.decode(PublicWorkflowCaseRunCorrelationV1.self, forKey: .correlation), status: try container.decode(PublicWorkflowEvidenceStatusV1.self, forKey: .status), fixture: try container.decode(CoreEvidenceReferenceV1.self, forKey: .fixture), comparison: try container.decode(CoreEvidenceReferenceV1.self, forKey: .comparison), provenance: try container.decode(CoreEvidenceReferenceV1.self, forKey: .provenance), fixtureBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .fixtureBinding), comparisonBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .comparisonBinding), provenanceBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .provenanceBinding), outcome: try container.decode(PublicWorkflowExpectedOutcomeV1.self, forKey: .outcome), diagnosticCode: try container.decode(PublicWorkflowDiagnosticCodeV1.self, forKey: .diagnosticCode), execution: try container.decode(PublicWorkflowCIExecutionV1.self, forKey: .execution))
  }
}

public enum PublicWorkflowFixtureOutcomeV1: String, Codable, Sendable { case succeeded, failed }

public struct PublicWorkflowFixtureResultV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let runID: UUID
  public let fixture: CoreEvidenceReferenceV1
  public let command: String
  public let expectedOutcome: PublicWorkflowFixtureOutcomeV1
  public let actualOutcome: PublicWorkflowFixtureOutcomeV1
  public let diagnosticCode: String?
  public let stdout: CoreEvidenceReferenceV1
  public let stderr: CoreEvidenceReferenceV1
  public let binding: PublicWorkflowEvidenceBindingV1

  public init(caseID: String, runID: UUID, fixture: CoreEvidenceReferenceV1, command: String, expectedOutcome: PublicWorkflowFixtureOutcomeV1, actualOutcome: PublicWorkflowFixtureOutcomeV1, diagnosticCode: String?, stdout: CoreEvidenceReferenceV1, stderr: CoreEvidenceReferenceV1, binding: PublicWorkflowEvidenceBindingV1) throws {
    self.caseID = caseID
    self.runID = runID
    self.fixture = fixture
    self.command = command
    self.expectedOutcome = expectedOutcome
    self.actualOutcome = actualOutcome
    self.diagnosticCode = diagnosticCode
    self.stdout = stdout
    self.stderr = stderr
    self.binding = binding
    try validate()
  }

  public func validate() throws {
    try fixture.validate()
    try stdout.validate()
    try stderr.validate()
    try binding.validate()
    guard !caseID.isEmpty, !command.isEmpty,
          binding.caseID == caseID, binding.evidenceRunID == runID, binding.evidence == fixture,
          actualOutcome == .succeeded || diagnosticCode?.isEmpty == false else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: caseID, field: "fixture result")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, runID, fixture, command, expectedOutcome, actualOutcome, diagnosticCode, stdout, stderr, binding }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), runID: try container.decode(UUID.self, forKey: .runID), fixture: try container.decode(CoreEvidenceReferenceV1.self, forKey: .fixture), command: try container.decode(String.self, forKey: .command), expectedOutcome: try container.decode(PublicWorkflowFixtureOutcomeV1.self, forKey: .expectedOutcome), actualOutcome: try container.decode(PublicWorkflowFixtureOutcomeV1.self, forKey: .actualOutcome), diagnosticCode: try container.decodeIfPresent(String.self, forKey: .diagnosticCode), stdout: try container.decode(CoreEvidenceReferenceV1.self, forKey: .stdout), stderr: try container.decode(CoreEvidenceReferenceV1.self, forKey: .stderr), binding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .binding))
  }
}

public struct PublicWorkflowCanonicalObservationV1: Equatable, Codable, Sendable {
  public let initialStates: [String]
  public let reachableStates: [String]
  public let labeledTransitions: [String]
  public let enabledTransitions: [String]
  public let properties: [String]
  public let deadlocks: [String]
  public let failures: [String]
  public let diagnostics: [String]
  public let trace: [String]?

  public init(initialStates: [String], reachableStates: [String], labeledTransitions: [String], enabledTransitions: [String], properties: [String], deadlocks: [String], failures: [String], diagnostics: [String], trace: [String]? = nil) throws {
    self.initialStates = initialStates
    self.reachableStates = reachableStates
    self.labeledTransitions = labeledTransitions
    self.enabledTransitions = enabledTransitions
    self.properties = properties
    self.deadlocks = deadlocks
    self.failures = failures
    self.diagnostics = diagnostics
    self.trace = trace
    try validate()
  }

  public func validate() throws {
    let collections = [initialStates, reachableStates, labeledTransitions, enabledTransitions, properties, deadlocks, failures, diagnostics]
    guard !initialStates.isEmpty, collections.allSatisfy({ $0.allSatisfy { !$0.isEmpty } }), trace?.allSatisfy({ !$0.isEmpty }) != false else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "observation", field: "canonical fields")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case initialStates, reachableStates, labeledTransitions, enabledTransitions, properties, deadlocks, failures, diagnostics, trace }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(initialStates: try container.decode([String].self, forKey: .initialStates), reachableStates: try container.decode([String].self, forKey: .reachableStates), labeledTransitions: try container.decode([String].self, forKey: .labeledTransitions), enabledTransitions: try container.decode([String].self, forKey: .enabledTransitions), properties: try container.decode([String].self, forKey: .properties), deadlocks: try container.decode([String].self, forKey: .deadlocks), failures: try container.decode([String].self, forKey: .failures), diagnostics: try container.decode([String].self, forKey: .diagnostics), trace: try container.decodeIfPresent([String].self, forKey: .trace))
  }
}

public struct PublicWorkflowComparisonV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let correlation: PublicWorkflowCaseRunCorrelationV1
  public let left: PublicWorkflowCanonicalObservationV1
  public let right: PublicWorkflowCanonicalObservationV1
  public let outcome: PublicWorkflowExpectedOutcomeV1
  public let diagnosticCode: PublicWorkflowDiagnosticCodeV1
  public let leftBinding: PublicWorkflowEvidenceBindingV1
  public let rightBinding: PublicWorkflowEvidenceBindingV1

  public init(caseID: String, correlation: PublicWorkflowCaseRunCorrelationV1, left: PublicWorkflowCanonicalObservationV1, right: PublicWorkflowCanonicalObservationV1, outcome: PublicWorkflowExpectedOutcomeV1, diagnosticCode: PublicWorkflowDiagnosticCodeV1, leftBinding: PublicWorkflowEvidenceBindingV1, rightBinding: PublicWorkflowEvidenceBindingV1) throws {
    self.caseID = caseID
    self.correlation = correlation
    self.left = left
    self.right = right
    self.outcome = outcome
    self.diagnosticCode = diagnosticCode
    self.leftBinding = leftBinding
    self.rightBinding = rightBinding
    try validate()
  }

  public func validate() throws {
    try left.validate()
    try right.validate()
    try leftBinding.validate()
    try rightBinding.validate()
    guard correlation.caseID == caseID, leftBinding.caseID == caseID, rightBinding.caseID == caseID,
          leftBinding.gateRunID == correlation.gateRunID, rightBinding.gateRunID == correlation.gateRunID,
          leftBinding.evidenceRunID == correlation.comparisonRunID,
          rightBinding.evidenceRunID == correlation.comparisonRunID, outcome != .unavailable else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: caseID, field: "comparison correlation")
    }
    let matches = left == right
    guard (outcome == .exact && matches && diagnosticCode == .exactAgreement) || (outcome == .difference && !matches && diagnosticCode == .observationDifference) else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: caseID, field: "comparison outcome")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, correlation, left, right, outcome, diagnosticCode, leftBinding, rightBinding }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), correlation: try container.decode(PublicWorkflowCaseRunCorrelationV1.self, forKey: .correlation), left: try container.decode(PublicWorkflowCanonicalObservationV1.self, forKey: .left), right: try container.decode(PublicWorkflowCanonicalObservationV1.self, forKey: .right), outcome: try container.decode(PublicWorkflowExpectedOutcomeV1.self, forKey: .outcome), diagnosticCode: try container.decode(PublicWorkflowDiagnosticCodeV1.self, forKey: .diagnosticCode), leftBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .leftBinding), rightBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .rightBinding))
  }
}

public enum PublicWorkflowPlatformStatusV1: String, Codable, Sendable { case succeeded, failed, unavailable }

/// Execution metadata is diagnostic or a hosted-workflow candidate; public admission is external to this product.
public enum PublicWorkflowEvidenceAuthorityV1: String, Codable, Sendable { case candidate, diagnostic }

/// Immutable execution metadata retained with every platform result.
public struct PublicWorkflowCIExecutionV1: Equatable, Codable, Sendable {
  public let authority: PublicWorkflowEvidenceAuthorityV1
  public let gitSHA: String?
  public let repository: String?
  public let workflow: String?
  public let ref: String?
  public let runID: String?
  public let runAttempt: Int?
  public let job: String?
  public let serverURL: String?
  public let metadata: CoreEvidenceReferenceV1

  public init(authority: PublicWorkflowEvidenceAuthorityV1, gitSHA: String? = nil, repository: String? = nil,
              workflow: String? = nil, ref: String? = nil, runID: String? = nil, runAttempt: Int? = nil, job: String? = nil,
              serverURL: String? = nil, metadata: CoreEvidenceReferenceV1) throws {
    self.authority = authority
    self.gitSHA = gitSHA
    self.repository = repository
    self.workflow = workflow
    self.ref = ref
    self.runID = runID
    self.runAttempt = runAttempt
    self.job = job
    self.serverURL = serverURL
    self.metadata = metadata
    try validate()
  }

  public func validate() throws {
    try metadata.validate()
    switch authority {
    case .diagnostic:
      guard gitSHA == nil, repository == nil, workflow == nil, ref == nil, runID == nil, runAttempt == nil, job == nil, serverURL == nil else {
        throw PublicWorkflowGovernanceErrorV1.invalidField(record: "diagnostic execution", field: "hosted identity")
      }
    case .candidate:
      let isSHA = gitSHA?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
      guard isSHA, repository?.isEmpty == false, workflow?.isEmpty == false, ref?.isEmpty == false, runID?.isEmpty == false,
            (runAttempt ?? 0) > 0, job?.isEmpty == false, serverURL?.isEmpty == false else {
        throw PublicWorkflowGovernanceErrorV1.invalidField(record: "CI execution", field: "identity")
      }
    }
  }

}

public struct PublicWorkflowPlatformRunCorrelationV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let platformRunID: UUID

  public init(caseID: String, gateRunID: UUID, platformRunID: UUID) throws {
    guard !caseID.isEmpty else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "platform correlation", field: "caseID")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.platformRunID = platformRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, gateRunID, platformRunID }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID),
                  gateRunID: try container.decode(UUID.self, forKey: .gateRunID),
                  platformRunID: try container.decode(UUID.self, forKey: .platformRunID))
  }
}

public struct PublicWorkflowPlatformEvidenceV1: Equatable, Codable, Sendable {
  public let platform: String
  public let command: String
  public let sdk: String
  public let destination: String
  public let xcodeVersion: String
  public let fixture: CoreEvidenceReferenceV1
  public let status: PublicWorkflowPlatformStatusV1
  public let exitCode: Int?
  public let stdout: CoreEvidenceReferenceV1
  public let stderr: CoreEvidenceReferenceV1
  public let correlation: PublicWorkflowPlatformRunCorrelationV1
  public let fixtureBinding: PublicWorkflowEvidenceBindingV1
  public let stdoutBinding: PublicWorkflowEvidenceBindingV1
  public let stderrBinding: PublicWorkflowEvidenceBindingV1
  public let execution: PublicWorkflowCIExecutionV1

  public init(platform: String, command: String, sdk: String, destination: String, xcodeVersion: String, fixture: CoreEvidenceReferenceV1, status: PublicWorkflowPlatformStatusV1, exitCode: Int?, stdout: CoreEvidenceReferenceV1, stderr: CoreEvidenceReferenceV1, correlation: PublicWorkflowPlatformRunCorrelationV1, fixtureBinding: PublicWorkflowEvidenceBindingV1, stdoutBinding: PublicWorkflowEvidenceBindingV1, stderrBinding: PublicWorkflowEvidenceBindingV1, execution: PublicWorkflowCIExecutionV1) throws {
    self.platform = platform
    self.command = command
    self.sdk = sdk
    self.destination = destination
    self.xcodeVersion = xcodeVersion
    self.fixture = fixture
    self.status = status
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
    self.correlation = correlation
    self.fixtureBinding = fixtureBinding
    self.stdoutBinding = stdoutBinding
    self.stderrBinding = stderrBinding
    self.execution = execution
    try validate()
  }

  public func validate() throws {
    try fixture.validate()
    try stdout.validate()
    try stderr.validate()
    try fixtureBinding.validate()
    try stdoutBinding.validate()
    try stderrBinding.validate()
    try execution.validate()
    guard !platform.isEmpty, !command.isEmpty, !sdk.isEmpty, !destination.isEmpty, !xcodeVersion.isEmpty else {
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: "platform", field: "identity")
    }
    guard [fixtureBinding, stdoutBinding, stderrBinding].allSatisfy({
      $0.caseID == correlation.caseID && $0.gateRunID == correlation.gateRunID
        && $0.evidenceRunID == correlation.platformRunID
    }), fixtureBinding.evidence == fixture, stdoutBinding.evidence == stdout, stderrBinding.evidence == stderr else {
      throw PublicWorkflowGovernanceErrorV1.inconsistentReference(record: platform, field: "platform artifacts")
    }
    switch status {
    case .succeeded:
      guard exitCode == 0 else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: platform, field: "exitCode") }
    case .failed:
      guard let exitCode, exitCode != 0 else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: platform, field: "exitCode") }
    case .unavailable:
      guard exitCode == nil else { throw PublicWorkflowGovernanceErrorV1.invalidField(record: platform, field: "exitCode") }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case platform, command, sdk, destination, xcodeVersion, fixture, status, exitCode, stdout, stderr, correlation, fixtureBinding, stdoutBinding, stderrBinding, execution }

  public init(from decoder: Decoder) throws {
    let container = try PublicWorkflowDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(platform: try container.decode(String.self, forKey: .platform), command: try container.decode(String.self, forKey: .command), sdk: try container.decode(String.self, forKey: .sdk), destination: try container.decode(String.self, forKey: .destination), xcodeVersion: try container.decode(String.self, forKey: .xcodeVersion), fixture: try container.decode(CoreEvidenceReferenceV1.self, forKey: .fixture), status: try container.decode(PublicWorkflowPlatformStatusV1.self, forKey: .status), exitCode: try container.decodeIfPresent(Int.self, forKey: .exitCode), stdout: try container.decode(CoreEvidenceReferenceV1.self, forKey: .stdout), stderr: try container.decode(CoreEvidenceReferenceV1.self, forKey: .stderr), correlation: try container.decode(PublicWorkflowPlatformRunCorrelationV1.self, forKey: .correlation), fixtureBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .fixtureBinding), stdoutBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .stdoutBinding), stderrBinding: try container.decode(PublicWorkflowEvidenceBindingV1.self, forKey: .stderrBinding), execution: try container.decode(PublicWorkflowCIExecutionV1.self, forKey: .execution))
  }
}
