import Foundation

public enum TemporalSymmetryCaseKind: String, Codable, Sendable {
  case temporal
  case symmetry
}

public enum TemporalFairnessMode: String, Codable, Sendable {
  case none
  case weak
  case strong
}

public enum TemporalSymmetryOutcome: String, Codable, Sendable {
  case exact
  case difference
  case unavailable
}

public enum TemporalPropertyOutcome: String, Codable, Sendable {
  case satisfied
  case violated
}

public enum TemporalEvaluationAvailability: String, Codable, Sendable {
  case evaluated
  case unavailable
}

public enum TemporalTraceAvailability: String, Codable, Sendable {
  case available
  case unavailable
  case notApplicable
}

public enum TemporalSymmetryDiagnosticCode: String, Codable, Sendable {
  case exactAgreement
  case propertyOutcomeDifference
  case applicableOutcomeDifference
  case graphIdentityDifference
  case initialStateDifference
  case temporalEvidenceUnavailable
  case orbitEvidenceUnavailable
  case orbitDifference
}

public enum SymmetryExplorationEngine: String, Codable, Sendable {
  case swift
  case tlc
}

public enum SymmetryApplicableOutcome: String, Codable, Sendable {
  case notApplicable
  case satisfied
  case violated
  case deadlocked
}

public struct TemporalCompleteGraphPassDeclaration: Equatable, Codable, Sendable {
  public let configuration: CoreEvidenceReference

  public init(configuration: CoreEvidenceReference) throws {
    self.configuration = configuration
    try configuration.validate()
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case configuration }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(configuration: container.decode(CoreEvidenceReference.self, forKey: .configuration))
  }
}

public struct TemporalSymmetryConfiguration: Equatable, Codable, Sendable {
  public let property: String?
  public let fairness: TemporalFairnessMode?
  public let fairnessActions: [String]
  public let symmetryCollection: String?
  public let symmetryScope: Int?
  public let symmetryEnabled: Bool
  public let allowsImplicitStuttering: Bool
  public let completeGraphPass: TemporalCompleteGraphPassDeclaration?

  public init(
    property: String? = nil,
    fairness: TemporalFairnessMode? = nil,
    fairnessActions: [String] = [],
    symmetryCollection: String? = nil,
    symmetryScope: Int? = nil,
    symmetryEnabled: Bool = false,
    allowsImplicitStuttering: Bool = false,
    completeGraphPass: TemporalCompleteGraphPassDeclaration? = nil
  ) throws {
    self.property = property
    self.fairness = fairness
    self.fairnessActions = fairnessActions
    self.symmetryCollection = symmetryCollection
    self.symmetryScope = symmetryScope
    self.symmetryEnabled = symmetryEnabled
    self.allowsImplicitStuttering = allowsImplicitStuttering
    self.completeGraphPass = completeGraphPass
    try validate()
  }

  public func validate() throws {
    guard Set(fairnessActions).count == fairnessActions.count,
          fairnessActions.allSatisfy({ !$0.isEmpty }) else {
      throw ConformanceGovernanceError.invalidField(record: "configuration", field: "fairnessActions")
    }
    if property == nil {
      guard fairness == nil, fairnessActions.isEmpty, !allowsImplicitStuttering, completeGraphPass == nil else {
        throw ConformanceGovernanceError.invalidField(record: "configuration", field: "temporal fields")
      }
    } else {
      guard property?.isEmpty == false, fairness != nil else {
        throw ConformanceGovernanceError.invalidField(record: "configuration", field: "property or fairness")
      }
    }
    if completeGraphPass != nil {
      guard property != nil else {
        throw ConformanceGovernanceError.invalidField(record: "configuration", field: "complete graph pass")
      }
    }
    if symmetryEnabled {
      guard symmetryCollection?.isEmpty == false, (symmetryScope ?? 0) > 0 else {
        throw ConformanceGovernanceError.invalidField(record: "configuration", field: "symmetry")
      }
    } else {
      guard symmetryCollection == nil, symmetryScope == nil else {
        throw ConformanceGovernanceError.invalidField(record: "configuration", field: "disabled symmetry")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case property, fairness, fairnessActions, symmetryCollection, symmetryScope, symmetryEnabled
    case allowsImplicitStuttering, completeGraphPass
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      property: try container.decodeIfPresent(String.self, forKey: .property),
      fairness: try container.decodeIfPresent(TemporalFairnessMode.self, forKey: .fairness),
      fairnessActions: try container.decodeIfPresent([String].self, forKey: .fairnessActions) ?? [],
      symmetryCollection: try container.decodeIfPresent(String.self, forKey: .symmetryCollection),
      symmetryScope: try container.decodeIfPresent(Int.self, forKey: .symmetryScope),
      symmetryEnabled: try container.decode(Bool.self, forKey: .symmetryEnabled),
      allowsImplicitStuttering: try container.decodeIfPresent(Bool.self, forKey: .allowsImplicitStuttering) ?? false,
      completeGraphPass: try container.decodeIfPresent(TemporalCompleteGraphPassDeclaration.self, forKey: .completeGraphPass))
  }
}

public struct TemporalSymmetryCase: Equatable, Codable, Sendable {
  public let id: String
  public let kind: TemporalSymmetryCaseKind
  public let swiftSpec: String
  public let finiteBounds: CoreFiniteBounds
  public let sourceInput: CoreEvidenceReference?
  public let configuration: TemporalSymmetryConfiguration

  public init(
    id: String,
    kind: TemporalSymmetryCaseKind,
    swiftSpec: String,
    finiteBounds: CoreFiniteBounds,
    sourceInput: CoreEvidenceReference? = nil,
    configuration: TemporalSymmetryConfiguration
  ) throws {
    self.id = id
    self.kind = kind
    self.swiftSpec = swiftSpec
    self.finiteBounds = finiteBounds
    self.sourceInput = sourceInput
    self.configuration = configuration
    try validate()
  }

  public func validate() throws {
    try finiteBounds.validate()
    try sourceInput?.validate()
    try configuration.validate()
    guard !id.isEmpty, !swiftSpec.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: id, field: "case declaration")
    }
    switch kind {
    case .temporal:
      guard configuration.property != nil, configuration.fairness != nil,
            configuration.symmetryEnabled == false, sourceInput != nil else {
        throw ConformanceGovernanceError.inconsistentReference(record: id, field: "temporal configuration")
      }
    case .symmetry:
      guard configuration.property == nil, configuration.symmetryEnabled, sourceInput == nil else {
        throw ConformanceGovernanceError.inconsistentReference(record: id, field: "symmetry configuration")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, swiftSpec, finiteBounds, sourceInput, configuration
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKind.self, forKey: .kind),
      swiftSpec: container.decode(String.self, forKey: .swiftSpec),
      finiteBounds: container.decode(CoreFiniteBounds.self, forKey: .finiteBounds),
      sourceInput: try container.decodeIfPresent(CoreEvidenceReference.self, forKey: .sourceInput),
      configuration: container.decode(TemporalSymmetryConfiguration.self, forKey: .configuration))
  }
}

public struct TemporalSymmetryCases: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryCases"
  public let schema: String
  public let cases: [TemporalSymmetryCase]

  public init(cases: [TemporalSymmetryCase]) throws {
    try self.init(schema: Self.schema, cases: cases)
  }

  public init(schema: String, cases: [TemporalSymmetryCase]) throws {
    guard schema == Self.schema else { throw ConformanceGovernanceError.invalidSchema(schema) }
    var ids = Set<String>()
    for item in cases {
      try item.validate()
      guard ids.insert(item.id).inserted else {
        throw ConformanceGovernanceError.duplicateID(kind: "case", id: item.id)
      }
    }
    self.schema = schema
    self.cases = cases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: container.decode(String.self, forKey: .schema), cases: container.decode([TemporalSymmetryCase].self, forKey: .cases))
  }
}

public struct TemporalSymmetryCaseRunCorrelation: Equatable, Codable, Sendable {
  public let caseID: String
  public let runID: UUID
  public let swiftRunID: UUID
  public let tlcRunID: UUID
  public let comparisonRunID: UUID

  public init(caseID: String, runID: UUID, swiftRunID: UUID, tlcRunID: UUID, comparisonRunID: UUID) throws {
    guard !caseID.isEmpty,
          Set([runID, swiftRunID, tlcRunID, comparisonRunID]).count == 4 else {
      throw ConformanceGovernanceError.invalidField(record: "correlation", field: "caseID")
    }
    self.caseID = caseID
    self.runID = runID
    self.swiftRunID = swiftRunID
    self.tlcRunID = tlcRunID
    self.comparisonRunID = comparisonRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, runID, swiftRunID, tlcRunID, comparisonRunID
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      runID: container.decode(UUID.self, forKey: .runID),
      swiftRunID: container.decode(UUID.self, forKey: .swiftRunID),
      tlcRunID: container.decode(UUID.self, forKey: .tlcRunID),
      comparisonRunID: container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

public struct TemporalLassoWitness: Equatable, Codable, Sendable {
  public let prefixStateIDs: [String]
  public let cycleStateIDs: [String]

  public init(prefixStateIDs: [String], cycleStateIDs: [String]) throws {
    self.prefixStateIDs = prefixStateIDs
    self.cycleStateIDs = cycleStateIDs
    guard prefixStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.count >= 2,
          cycleStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.first == cycleStateIDs.last else {
      throw ConformanceGovernanceError.invalidField(record: "temporal lasso", field: "state IDs")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case prefixStateIDs, cycleStateIDs }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      prefixStateIDs: container.decode([String].self, forKey: .prefixStateIDs),
      cycleStateIDs: container.decode([String].self, forKey: .cycleStateIDs))
  }
}

public struct TemporalPropertyResult: Equatable, Codable, Sendable {
  public let availability: TemporalEvaluationAvailability
  public let outcome: TemporalPropertyOutcome?
  public let graphID: String
  public let initialStateIDs: [String]
  public let traceAvailability: TemporalTraceAvailability
  public let traceEvidence: CoreEvidenceReference?
  public let lasso: TemporalLassoWitness?

  public init(
    availability: TemporalEvaluationAvailability,
    outcome: TemporalPropertyOutcome?,
    graphID: String,
    initialStateIDs: [String],
    traceAvailability: TemporalTraceAvailability,
    traceEvidence: CoreEvidenceReference? = nil,
    lasso: TemporalLassoWitness? = nil
  ) throws {
    self.availability = availability
    self.outcome = outcome
    self.graphID = graphID
    self.initialStateIDs = initialStateIDs.sorted()
    self.traceAvailability = traceAvailability
    self.traceEvidence = traceEvidence
    self.lasso = lasso
    try validate()
  }

  public func validate() throws {
    guard !graphID.isEmpty, !initialStateIDs.isEmpty,
          Set(initialStateIDs).count == initialStateIDs.count,
          initialStateIDs.allSatisfy({ !$0.isEmpty }) else {
      throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "graph or initial states")
    }
    try traceEvidence?.validate()
    switch availability {
    case .evaluated:
      guard outcome != nil else {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "missing property outcome")
      }
    case .unavailable:
      guard outcome == nil, traceAvailability == .unavailable, traceEvidence == nil, lasso == nil else {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "unavailable evaluation")
      }
      return
    }
    switch traceAvailability {
    case .available:
      guard traceEvidence != nil else {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "traceEvidence")
      }
      if outcome == .violated, lasso == nil {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "lasso")
      }
    case .unavailable:
      guard traceEvidence == nil, lasso == nil else {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "unavailable trace")
      }
    case .notApplicable:
      guard outcome == .satisfied, traceEvidence == nil, lasso == nil else {
        throw ConformanceGovernanceError.invalidField(record: "temporal result", field: "not applicable trace")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case availability, outcome, graphID, initialStateIDs, traceAvailability, traceEvidence, lasso
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      availability: container.decode(TemporalEvaluationAvailability.self, forKey: .availability),
      outcome: try container.decodeIfPresent(TemporalPropertyOutcome.self, forKey: .outcome),
      graphID: container.decode(String.self, forKey: .graphID),
      initialStateIDs: container.decode([String].self, forKey: .initialStateIDs),
      traceAvailability: container.decode(TemporalTraceAvailability.self, forKey: .traceAvailability),
      traceEvidence: try container.decodeIfPresent(CoreEvidenceReference.self, forKey: .traceEvidence),
      lasso: try container.decodeIfPresent(TemporalLassoWitness.self, forKey: .lasso))
  }
}

public struct TemporalCompleteGraphEvidence: Equatable, Codable, Sendable {
  public let propertyRunID: UUID
  public let graphRunID: UUID
  public let arguments: [String]
  public let fingerprintPolynomial: Int
  public let operatingSystem: String
  public let architecture: String
  public let environment: [String: String]
  public let sourceInput: CoreEvidenceReference
  public let configuration: CoreEvidenceReference
  public let graphEvents: CoreEvidenceReference
  public let result: CoreEvidenceReference

  public init(
    propertyRunID: UUID,
    graphRunID: UUID,
    arguments: [String],
    fingerprintPolynomial: Int,
    operatingSystem: String,
    architecture: String,
    environment: [String: String],
    sourceInput: CoreEvidenceReference,
    configuration: CoreEvidenceReference,
    graphEvents: CoreEvidenceReference,
    result: CoreEvidenceReference
  ) throws {
    guard propertyRunID != graphRunID else {
      throw ConformanceGovernanceError.inconsistentReference(record: "complete graph evidence", field: "run IDs")
    }
    try sourceInput.validate()
    try configuration.validate()
    try graphEvents.validate()
    try result.validate()
    self.propertyRunID = propertyRunID
    self.graphRunID = graphRunID
    self.arguments = arguments
    self.fingerprintPolynomial = fingerprintPolynomial
    self.operatingSystem = operatingSystem
    self.architecture = architecture
    self.environment = environment
    self.sourceInput = sourceInput
    self.configuration = configuration
    self.graphEvents = graphEvents
    self.result = result
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case propertyRunID, graphRunID, arguments, fingerprintPolynomial, operatingSystem, architecture, environment
    case sourceInput, configuration, graphEvents, result
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      propertyRunID: container.decode(UUID.self, forKey: .propertyRunID),
      graphRunID: container.decode(UUID.self, forKey: .graphRunID),
      arguments: container.decode([String].self, forKey: .arguments),
      fingerprintPolynomial: container.decode(Int.self, forKey: .fingerprintPolynomial),
      operatingSystem: container.decode(String.self, forKey: .operatingSystem),
      architecture: container.decode(String.self, forKey: .architecture),
      environment: container.decode([String: String].self, forKey: .environment),
      sourceInput: container.decode(CoreEvidenceReference.self, forKey: .sourceInput),
      configuration: container.decode(CoreEvidenceReference.self, forKey: .configuration),
      graphEvents: container.decode(CoreEvidenceReference.self, forKey: .graphEvents),
      result: container.decode(CoreEvidenceReference.self, forKey: .result))
  }

  public func validate() throws {
    _ = try Self(
      propertyRunID: propertyRunID, graphRunID: graphRunID, arguments: arguments,
      fingerprintPolynomial: fingerprintPolynomial, operatingSystem: operatingSystem, architecture: architecture,
      environment: environment, sourceInput: sourceInput,
      configuration: configuration, graphEvents: graphEvents, result: result)
  }
}
