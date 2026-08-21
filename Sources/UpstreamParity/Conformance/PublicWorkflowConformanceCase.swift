import Foundation

public enum PublicWorkflowCaseCategory: String, Codable, Sendable {
  case annotation
  case parserBuilder
  case generatedBehavior
  case nestedPackage
  case platform
}

public enum PublicWorkflowExpectedOutcome: String, Codable, Sendable {
  case exact
  case difference
  case unavailable
}

public enum PublicWorkflowAuthorityBoundary: String, Codable, Sendable {
  case publishedSemantics
  case executableReference
  case diagnosticSource
}

public enum PublicWorkflowEvidenceStatus: String, Codable, Sendable {
  case complete
  case partial
  case unavailable
}

public enum PublicWorkflowDiagnosticCode: String, Codable, Sendable {
  case exactAgreement
  case observationDifference
  case invalidFixtureAccepted
  case evaluationFailed
  case evaluationUnavailable
  case platformValidationFailed
  case evidenceUnavailable
}

public struct PublicWorkflowConformanceCase: Equatable, Codable, Sendable {
  public let id: String
  public let category: PublicWorkflowCaseCategory
  public let publicName: String
  public let finiteBounds: CoreFiniteBounds
  public let semanticCitations: [String]
  public let provenance: CoreEvidenceProvenance
  public let sourceInput: CoreEvidenceReference
  public let configuration: CoreEvidenceReference
  public let expectedOutcome: PublicWorkflowExpectedOutcome
  public let authorityBoundary: PublicWorkflowAuthorityBoundary

  public init(
    id: String,
    category: PublicWorkflowCaseCategory,
    publicName: String,
    finiteBounds: CoreFiniteBounds,
    semanticCitations: [String],
    provenance: CoreEvidenceProvenance,
    sourceInput: CoreEvidenceReference,
    configuration: CoreEvidenceReference,
    expectedOutcome: PublicWorkflowExpectedOutcome,
    authorityBoundary: PublicWorkflowAuthorityBoundary
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
      throw ConformanceGovernanceError.invalidField(record: id, field: "case declaration")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, category, publicName, finiteBounds, semanticCitations, provenance, sourceInput, configuration
    case expectedOutcome, authorityBoundary
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      category: try container.decode(PublicWorkflowCaseCategory.self, forKey: .category),
      publicName: try container.decode(String.self, forKey: .publicName),
      finiteBounds: try container.decode(CoreFiniteBounds.self, forKey: .finiteBounds),
      semanticCitations: try container.decode([String].self, forKey: .semanticCitations),
      provenance: try container.decode(CoreEvidenceProvenance.self, forKey: .provenance),
      sourceInput: try container.decode(CoreEvidenceReference.self, forKey: .sourceInput),
      configuration: try container.decode(CoreEvidenceReference.self, forKey: .configuration),
      expectedOutcome: try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .expectedOutcome),
      authorityBoundary: try container.decode(PublicWorkflowAuthorityBoundary.self, forKey: .authorityBoundary))
  }
}

public struct PublicWorkflowCases: Equatable, Codable, Sendable {
  public static let schema = "PublicWorkflowCases"
  public let schema: String
  public let cases: [PublicWorkflowConformanceCase]

  public init(cases: [PublicWorkflowConformanceCase]) throws { try self.init(schema: Self.schema, cases: cases) }

  public init(schema: String, cases: [PublicWorkflowConformanceCase]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for record in cases {
      try record.validate()
      guard ids.insert(record.id).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "case", id: record.id)
      }
    }
    self.schema = schema
    self.cases = cases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: try container.decode(String.self, forKey: .schema), cases: try container.decode([PublicWorkflowConformanceCase].self, forKey: .cases))
  }
}

public struct PublicWorkflowCaseRunCorrelation: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let fixtureRunID: UUID
  public let comparisonRunID: UUID

  public init(caseID: String, gateRunID: UUID, fixtureRunID: UUID, comparisonRunID: UUID) throws {
    guard !caseID.isEmpty, Set([gateRunID, fixtureRunID, comparisonRunID]).count == 3 else {
      throw ConformanceGovernanceError.invalidField(record: "correlation", field: "caseID or run IDs")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.fixtureRunID = fixtureRunID
    self.comparisonRunID = comparisonRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, gateRunID, fixtureRunID, comparisonRunID }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), gateRunID: try container.decode(UUID.self, forKey: .gateRunID), fixtureRunID: try container.decode(UUID.self, forKey: .fixtureRunID), comparisonRunID: try container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

public struct PublicWorkflowEvidenceBinding: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let evidenceRunID: UUID
  public let sourceInput: CoreEvidenceReference
  public let configuration: CoreEvidenceReference
  public let provenance: CoreEvidenceProvenance
  public let evidence: CoreEvidenceReference

  public init(
    caseID: String, gateRunID: UUID, evidenceRunID: UUID, sourceInput: CoreEvidenceReference,
    configuration: CoreEvidenceReference, provenance: CoreEvidenceProvenance,
    evidence: CoreEvidenceReference
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
      throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "evidence binding")
    }
  }

  func matches(
    _ declaration: PublicWorkflowConformanceCase, gateRunID: UUID,
    expectedRunID: UUID, evidence: CoreEvidenceReference
  ) -> Bool {
    caseID == declaration.id && self.gateRunID == gateRunID && evidenceRunID == expectedRunID
      && sourceInput == declaration.sourceInput && configuration == declaration.configuration
      && provenance == declaration.provenance && self.evidence == evidence
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, gateRunID, evidenceRunID, sourceInput, configuration, provenance, evidence
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: try container.decode(String.self, forKey: .caseID),
      gateRunID: try container.decode(UUID.self, forKey: .gateRunID),
      evidenceRunID: try container.decode(UUID.self, forKey: .evidenceRunID),
      sourceInput: try container.decode(CoreEvidenceReference.self, forKey: .sourceInput),
      configuration: try container.decode(CoreEvidenceReference.self, forKey: .configuration),
      provenance: try container.decode(CoreEvidenceProvenance.self, forKey: .provenance),
      evidence: try container.decode(CoreEvidenceReference.self, forKey: .evidence))
  }
}

public struct PublicWorkflowCaseEvidence: Equatable, Codable, Sendable {
  public let caseID: String
  public let correlation: PublicWorkflowCaseRunCorrelation
  public let status: PublicWorkflowEvidenceStatus
  public let fixture: CoreEvidenceReference
  public let comparison: CoreEvidenceReference
  public let provenance: CoreEvidenceReference
  public let fixtureBinding: PublicWorkflowEvidenceBinding
  public let comparisonBinding: PublicWorkflowEvidenceBinding
  public let provenanceBinding: PublicWorkflowEvidenceBinding
  public let outcome: PublicWorkflowExpectedOutcome
  public let diagnosticCode: PublicWorkflowDiagnosticCode
  public let execution: PublicWorkflowCIExecution

  public init(
    caseID: String, correlation: PublicWorkflowCaseRunCorrelation, status: PublicWorkflowEvidenceStatus,
    fixture: CoreEvidenceReference, comparison: CoreEvidenceReference, provenance: CoreEvidenceReference,
    fixtureBinding: PublicWorkflowEvidenceBinding, comparisonBinding: PublicWorkflowEvidenceBinding,
    provenanceBinding: PublicWorkflowEvidenceBinding,
    outcome: PublicWorkflowExpectedOutcome, diagnosticCode: PublicWorkflowDiagnosticCode,
    execution: PublicWorkflowCIExecution
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
      throw ConformanceGovernanceError.inconsistentReference(record: caseID, field: "correlation")
    }
    guard status == .complete ? outcome != .unavailable && diagnosticCode != .evidenceUnavailable : outcome == .unavailable && diagnosticCode == .evidenceUnavailable else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "evidence status")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, correlation, status, fixture, comparison, provenance, fixtureBinding, comparisonBinding
    case provenanceBinding, outcome, diagnosticCode, execution
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), correlation: try container.decode(PublicWorkflowCaseRunCorrelation.self, forKey: .correlation), status: try container.decode(PublicWorkflowEvidenceStatus.self, forKey: .status), fixture: try container.decode(CoreEvidenceReference.self, forKey: .fixture), comparison: try container.decode(CoreEvidenceReference.self, forKey: .comparison), provenance: try container.decode(CoreEvidenceReference.self, forKey: .provenance), fixtureBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .fixtureBinding), comparisonBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .comparisonBinding), provenanceBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .provenanceBinding), outcome: try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .outcome), diagnosticCode: try container.decode(PublicWorkflowDiagnosticCode.self, forKey: .diagnosticCode), execution: try container.decode(PublicWorkflowCIExecution.self, forKey: .execution))
  }
}

public enum PublicWorkflowFixtureOutcome: String, Codable, Sendable { case succeeded, failed }

public struct PublicWorkflowFixtureResult: Equatable, Codable, Sendable {
  public let caseID: String
  public let runID: UUID
  public let fixture: CoreEvidenceReference
  public let command: String
  public let expectedOutcome: PublicWorkflowFixtureOutcome
  public let actualOutcome: PublicWorkflowFixtureOutcome
  public let diagnosticCode: String?
  public let stdout: CoreEvidenceReference
  public let stderr: CoreEvidenceReference
  public let binding: PublicWorkflowEvidenceBinding

  public init(caseID: String, runID: UUID, fixture: CoreEvidenceReference, command: String, expectedOutcome: PublicWorkflowFixtureOutcome, actualOutcome: PublicWorkflowFixtureOutcome, diagnosticCode: String?, stdout: CoreEvidenceReference, stderr: CoreEvidenceReference, binding: PublicWorkflowEvidenceBinding) throws {
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
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "fixture result")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, runID, fixture, command, expectedOutcome, actualOutcome, diagnosticCode, stdout, stderr, binding }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), runID: try container.decode(UUID.self, forKey: .runID), fixture: try container.decode(CoreEvidenceReference.self, forKey: .fixture), command: try container.decode(String.self, forKey: .command), expectedOutcome: try container.decode(PublicWorkflowFixtureOutcome.self, forKey: .expectedOutcome), actualOutcome: try container.decode(PublicWorkflowFixtureOutcome.self, forKey: .actualOutcome), diagnosticCode: try container.decodeIfPresent(String.self, forKey: .diagnosticCode), stdout: try container.decode(CoreEvidenceReference.self, forKey: .stdout), stderr: try container.decode(CoreEvidenceReference.self, forKey: .stderr), binding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .binding))
  }
}

public struct PublicWorkflowCanonicalObservation: Equatable, Codable, Sendable {
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
      throw ConformanceGovernanceError.invalidField(record: "observation", field: "canonical fields")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case initialStates, reachableStates, labeledTransitions, enabledTransitions, properties, deadlocks, failures, diagnostics, trace }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(initialStates: try container.decode([String].self, forKey: .initialStates), reachableStates: try container.decode([String].self, forKey: .reachableStates), labeledTransitions: try container.decode([String].self, forKey: .labeledTransitions), enabledTransitions: try container.decode([String].self, forKey: .enabledTransitions), properties: try container.decode([String].self, forKey: .properties), deadlocks: try container.decode([String].self, forKey: .deadlocks), failures: try container.decode([String].self, forKey: .failures), diagnostics: try container.decode([String].self, forKey: .diagnostics), trace: try container.decodeIfPresent([String].self, forKey: .trace))
  }
}

public struct PublicWorkflowComparison: Equatable, Codable, Sendable {
  public let caseID: String
  public let correlation: PublicWorkflowCaseRunCorrelation
  public let left: PublicWorkflowCanonicalObservation
  public let right: PublicWorkflowCanonicalObservation
  public let outcome: PublicWorkflowExpectedOutcome
  public let diagnosticCode: PublicWorkflowDiagnosticCode
  public let leftBinding: PublicWorkflowEvidenceBinding
  public let rightBinding: PublicWorkflowEvidenceBinding

  public init(caseID: String, correlation: PublicWorkflowCaseRunCorrelation, left: PublicWorkflowCanonicalObservation, right: PublicWorkflowCanonicalObservation, outcome: PublicWorkflowExpectedOutcome, diagnosticCode: PublicWorkflowDiagnosticCode, leftBinding: PublicWorkflowEvidenceBinding, rightBinding: PublicWorkflowEvidenceBinding) throws {
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
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "comparison correlation")
    }
    let matches = left == right
    guard (outcome == .exact && matches && diagnosticCode == .exactAgreement) || (outcome == .difference && !matches && diagnosticCode == .observationDifference) else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "comparison outcome")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, correlation, left, right, outcome, diagnosticCode, leftBinding, rightBinding }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID), correlation: try container.decode(PublicWorkflowCaseRunCorrelation.self, forKey: .correlation), left: try container.decode(PublicWorkflowCanonicalObservation.self, forKey: .left), right: try container.decode(PublicWorkflowCanonicalObservation.self, forKey: .right), outcome: try container.decode(PublicWorkflowExpectedOutcome.self, forKey: .outcome), diagnosticCode: try container.decode(PublicWorkflowDiagnosticCode.self, forKey: .diagnosticCode), leftBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .leftBinding), rightBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .rightBinding))
  }
}

public enum PublicWorkflowPlatformStatus: String, Codable, Sendable { case succeeded, failed, unavailable }

/// Execution metadata is diagnostic or a hosted-workflow candidate; public admission is external to this product.
public enum PublicWorkflowEvidenceAuthority: String, Codable, Sendable { case candidate, diagnostic }

/// Immutable execution metadata retained with every platform result.
public struct PublicWorkflowCIExecution: Equatable, Codable, Sendable {
  public let authority: PublicWorkflowEvidenceAuthority
  public let gitSHA: String?
  public let repository: String?
  public let workflow: String?
  public let ref: String?
  public let runID: String?
  public let runAttempt: Int?
  public let job: String?
  public let serverURL: String?
  public let metadata: CoreEvidenceReference

  public init(authority: PublicWorkflowEvidenceAuthority, gitSHA: String? = nil, repository: String? = nil,
              workflow: String? = nil, ref: String? = nil, runID: String? = nil, runAttempt: Int? = nil, job: String? = nil,
              serverURL: String? = nil, metadata: CoreEvidenceReference) throws {
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
        throw ConformanceGovernanceError.invalidField(record: "diagnostic execution", field: "hosted identity")
      }
    case .candidate:
      let isSHA = gitSHA?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
      guard isSHA, repository?.isEmpty == false, workflow?.isEmpty == false, ref?.isEmpty == false, runID?.isEmpty == false,
            (runAttempt ?? 0) > 0, job?.isEmpty == false, serverURL?.isEmpty == false else {
        throw ConformanceGovernanceError.invalidField(record: "CI execution", field: "identity")
      }
    }
  }

}

public struct PublicWorkflowPlatformRunCorrelation: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let platformRunID: UUID

  public init(caseID: String, gateRunID: UUID, platformRunID: UUID) throws {
    guard !caseID.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: "platform correlation", field: "caseID")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.platformRunID = platformRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case caseID, gateRunID, platformRunID }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(caseID: try container.decode(String.self, forKey: .caseID),
                  gateRunID: try container.decode(UUID.self, forKey: .gateRunID),
                  platformRunID: try container.decode(UUID.self, forKey: .platformRunID))
  }
}

public struct PublicWorkflowPlatformEvidence: Equatable, Codable, Sendable {
  public let platform: String
  public let command: String
  public let sdk: String
  public let destination: String
  public let xcodeVersion: String
  public let fixture: CoreEvidenceReference
  public let status: PublicWorkflowPlatformStatus
  public let exitCode: Int?
  public let stdout: CoreEvidenceReference
  public let stderr: CoreEvidenceReference
  public let correlation: PublicWorkflowPlatformRunCorrelation
  public let fixtureBinding: PublicWorkflowEvidenceBinding
  public let stdoutBinding: PublicWorkflowEvidenceBinding
  public let stderrBinding: PublicWorkflowEvidenceBinding
  public let execution: PublicWorkflowCIExecution

  public init(platform: String, command: String, sdk: String, destination: String, xcodeVersion: String, fixture: CoreEvidenceReference, status: PublicWorkflowPlatformStatus, exitCode: Int?, stdout: CoreEvidenceReference, stderr: CoreEvidenceReference, correlation: PublicWorkflowPlatformRunCorrelation, fixtureBinding: PublicWorkflowEvidenceBinding, stdoutBinding: PublicWorkflowEvidenceBinding, stderrBinding: PublicWorkflowEvidenceBinding, execution: PublicWorkflowCIExecution) throws {
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
      throw ConformanceGovernanceError.invalidField(record: "platform", field: "identity")
    }
    guard [fixtureBinding, stdoutBinding, stderrBinding].allSatisfy({
      $0.caseID == correlation.caseID && $0.gateRunID == correlation.gateRunID
        && $0.evidenceRunID == correlation.platformRunID
    }), fixtureBinding.evidence == fixture, stdoutBinding.evidence == stdout, stderrBinding.evidence == stderr else {
      throw ConformanceGovernanceError.inconsistentReference(record: platform, field: "platform artifacts")
    }
    switch status {
    case .succeeded:
      guard exitCode == 0 else { throw ConformanceGovernanceError.invalidField(record: platform, field: "exitCode") }
    case .failed:
      guard let exitCode, exitCode != 0 else { throw ConformanceGovernanceError.invalidField(record: platform, field: "exitCode") }
    case .unavailable:
      guard exitCode == nil else { throw ConformanceGovernanceError.invalidField(record: platform, field: "exitCode") }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case platform, command, sdk, destination, xcodeVersion, fixture, status, exitCode, stdout, stderr, correlation, fixtureBinding, stdoutBinding, stderrBinding, execution }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(platform: try container.decode(String.self, forKey: .platform), command: try container.decode(String.self, forKey: .command), sdk: try container.decode(String.self, forKey: .sdk), destination: try container.decode(String.self, forKey: .destination), xcodeVersion: try container.decode(String.self, forKey: .xcodeVersion), fixture: try container.decode(CoreEvidenceReference.self, forKey: .fixture), status: try container.decode(PublicWorkflowPlatformStatus.self, forKey: .status), exitCode: try container.decodeIfPresent(Int.self, forKey: .exitCode), stdout: try container.decode(CoreEvidenceReference.self, forKey: .stdout), stderr: try container.decode(CoreEvidenceReference.self, forKey: .stderr), correlation: try container.decode(PublicWorkflowPlatformRunCorrelation.self, forKey: .correlation), fixtureBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .fixtureBinding), stdoutBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .stdoutBinding), stderrBinding: try container.decode(PublicWorkflowEvidenceBinding.self, forKey: .stderrBinding), execution: try container.decode(PublicWorkflowCIExecution.self, forKey: .execution))
  }
}
