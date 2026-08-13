import Foundation

public enum TemporalSymmetryGovernanceErrorV1: Error, Equatable, Sendable {
  case invalidSchema(String)
  case duplicateID(kind: String, id: String)
  case invalidField(record: String, field: String)
  case unknownCaseID(String)
  case unknownDivergenceID(String)
  case inconsistentReference(record: String, field: String)
}

private struct TemporalSymmetryAnyCodingKeyV1: CodingKey {
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

enum TemporalSymmetryGovernanceDecodingV1 {
  static func container<Key>(
    _ decoder: Decoder,
    keyedBy keyType: Key.Type
  ) throws -> KeyedDecodingContainer<Key> where Key: CodingKey & CaseIterable {
    let actual = try decoder.container(keyedBy: TemporalSymmetryAnyCodingKeyV1.self)
    let known = Set(Key.allCases.map(\.stringValue))
    let unexpected = Set(actual.allKeys.map(\.stringValue)).subtracting(known)
    guard unexpected.isEmpty else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(
        record: "decode", field: "unknown field \(unexpected.sorted().joined(separator: ","))")
    }
    return try decoder.container(keyedBy: Key.self)
  }
}

public enum TemporalSymmetryCaseKindV1: String, Codable, Sendable {
  case temporal
  case symmetry
}

public enum TemporalFairnessModeV1: String, Codable, Sendable {
  case none
  case weak
  case strong
}

public enum TemporalSymmetryExpectedOutcomeV1: String, Codable, Sendable {
  case exact
  case difference
  case unavailable
}

public enum TemporalPropertyOutcomeV1: String, Codable, Sendable {
  case satisfied
  case violated
}

public enum TemporalEvaluationAvailabilityV1: String, Codable, Sendable {
  case evaluated
  case unavailable
}

public enum TemporalTraceAvailabilityV1: String, Codable, Sendable {
  case available
  case unavailable
  case notApplicable
}

public enum TemporalRecurrentReasonCodeV1: String, Codable, Sendable {
  case accepting
  case rejectedByWeakFairness
  case rejectedByStrongFairness
  case rejectedByProperty
}

public enum TemporalSymmetryDiagnosticCodeV1: String, Codable, Sendable {
  case exactAgreement
  case propertyOutcomeDifference
  case applicableOutcomeDifference
  case graphIdentityDifference
  case initialStateDifference
  case temporalEvidenceUnavailable
  case orbitEvidenceUnavailable
  case orbitDifference
}

public enum SymmetryExplorationEngineV1: String, Codable, Sendable {
  case swift
  case tlc
}

public enum SymmetryApplicableOutcomeV1: String, Codable, Sendable {
  case notApplicable
  case satisfied
  case violated
  case deadlocked
}

public struct TemporalCompleteGraphPassDeclarationV1: Equatable, Codable, Sendable {
  public let configuration: CoreEvidenceReferenceV1

  public init(configuration: CoreEvidenceReferenceV1) throws {
    self.configuration = configuration
    try configuration.validate()
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case configuration }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(configuration: container.decode(CoreEvidenceReferenceV1.self, forKey: .configuration))
  }
}

public struct TemporalSymmetryConfigurationV1: Equatable, Codable, Sendable {
  public let property: String?
  public let fairness: TemporalFairnessModeV1?
  public let fairnessActions: [String]
  public let symmetryCollection: String?
  public let symmetryScope: Int?
  public let symmetryEnabled: Bool
  public let allowsImplicitStuttering: Bool
  public let completeGraphPass: TemporalCompleteGraphPassDeclarationV1?

  public init(
    property: String? = nil,
    fairness: TemporalFairnessModeV1? = nil,
    fairnessActions: [String] = [],
    symmetryCollection: String? = nil,
    symmetryScope: Int? = nil,
    symmetryEnabled: Bool = false,
    allowsImplicitStuttering: Bool = false,
    completeGraphPass: TemporalCompleteGraphPassDeclarationV1? = nil
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
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "fairnessActions")
    }
    if property == nil {
      guard fairness == nil, fairnessActions.isEmpty, !allowsImplicitStuttering, completeGraphPass == nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "temporal fields")
      }
    } else {
      guard property?.isEmpty == false, fairness != nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "property or fairness")
      }
    }
    if completeGraphPass != nil {
      guard property != nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "complete graph pass")
      }
    }
    if symmetryEnabled {
      guard symmetryCollection?.isEmpty == false, (symmetryScope ?? 0) > 0 else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "symmetry")
      }
    } else {
      guard symmetryCollection == nil, symmetryScope == nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "configuration", field: "disabled symmetry")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case property, fairness, fairnessActions, symmetryCollection, symmetryScope, symmetryEnabled
    case allowsImplicitStuttering, completeGraphPass
  }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      property: try container.decodeIfPresent(String.self, forKey: .property),
      fairness: try container.decodeIfPresent(TemporalFairnessModeV1.self, forKey: .fairness),
      fairnessActions: try container.decodeIfPresent([String].self, forKey: .fairnessActions) ?? [],
      symmetryCollection: try container.decodeIfPresent(String.self, forKey: .symmetryCollection),
      symmetryScope: try container.decodeIfPresent(Int.self, forKey: .symmetryScope),
      symmetryEnabled: try container.decode(Bool.self, forKey: .symmetryEnabled),
      allowsImplicitStuttering: try container.decodeIfPresent(Bool.self, forKey: .allowsImplicitStuttering) ?? false,
      completeGraphPass: try container.decodeIfPresent(TemporalCompleteGraphPassDeclarationV1.self, forKey: .completeGraphPass))
  }
}

public struct TemporalSymmetryCaseV1: Equatable, Codable, Sendable {
  public let id: String
  public let kind: TemporalSymmetryCaseKindV1
  public let swiftSpec: String
  public let provenance: CoreDivergenceProvenanceV1
  public let finiteBounds: CoreFiniteBoundsV1
  public let semanticCitations: [String]
  public let sourceInput: CoreEvidenceReferenceV1
  public let configuration: TemporalSymmetryConfigurationV1
  public let expectedOutcome: TemporalSymmetryExpectedOutcomeV1

  public init(
    id: String,
    kind: TemporalSymmetryCaseKindV1,
    swiftSpec: String,
    provenance: CoreDivergenceProvenanceV1,
    finiteBounds: CoreFiniteBoundsV1,
    semanticCitations: [String],
    sourceInput: CoreEvidenceReferenceV1,
    configuration: TemporalSymmetryConfigurationV1,
    expectedOutcome: TemporalSymmetryExpectedOutcomeV1
  ) throws {
    self.id = id
    self.kind = kind
    self.swiftSpec = swiftSpec
    self.provenance = provenance
    self.finiteBounds = finiteBounds
    self.semanticCitations = semanticCitations
    self.sourceInput = sourceInput
    self.configuration = configuration
    self.expectedOutcome = expectedOutcome
    try validate()
  }

  public func validate() throws {
    try provenance.validate()
    try finiteBounds.validate()
    try sourceInput.validate()
    try configuration.validate()
    guard !id.isEmpty, !swiftSpec.isEmpty, provenance.caseID == id,
          !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: id, field: "case declaration")
    }
    switch kind {
    case .temporal:
      guard configuration.property != nil, configuration.fairness != nil, !configuration.symmetryEnabled else {
        throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: id, field: "temporal configuration")
      }
    case .symmetry:
      guard configuration.property == nil, configuration.symmetryEnabled else {
        throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: id, field: "symmetry configuration")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, swiftSpec, provenance, finiteBounds, semanticCitations, sourceInput, configuration, expectedOutcome
  }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKindV1.self, forKey: .kind),
      swiftSpec: container.decode(String.self, forKey: .swiftSpec),
      provenance: container.decode(CoreDivergenceProvenanceV1.self, forKey: .provenance),
      finiteBounds: container.decode(CoreFiniteBoundsV1.self, forKey: .finiteBounds),
      semanticCitations: container.decode([String].self, forKey: .semanticCitations),
      sourceInput: container.decode(CoreEvidenceReferenceV1.self, forKey: .sourceInput),
      configuration: container.decode(TemporalSymmetryConfigurationV1.self, forKey: .configuration),
      expectedOutcome: container.decode(TemporalSymmetryExpectedOutcomeV1.self, forKey: .expectedOutcome))
  }
}

public struct TemporalSymmetryCasesV1: Equatable, Codable, Sendable {
  public static let schema = "TemporalSymmetryCasesV1"
  public let schema: String
  public let cases: [TemporalSymmetryCaseV1]

  public init(cases: [TemporalSymmetryCaseV1]) throws {
    try self.init(schema: Self.schema, cases: cases)
  }

  public init(schema: String, cases: [TemporalSymmetryCaseV1]) throws {
    guard schema == Self.schema else { throw TemporalSymmetryGovernanceErrorV1.invalidSchema(schema) }
    var ids = Set<String>()
    for item in cases {
      try item.validate()
      guard ids.insert(item.id).inserted else {
        throw TemporalSymmetryGovernanceErrorV1.duplicateID(kind: "case", id: item.id)
      }
    }
    self.schema = schema
    self.cases = cases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: container.decode(String.self, forKey: .schema), cases: container.decode([TemporalSymmetryCaseV1].self, forKey: .cases))
  }
}

public struct TemporalSymmetryCaseRunCorrelationV1: Equatable, Codable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let swiftRunID: UUID
  public let tlcRunID: UUID
  public let comparisonRunID: UUID

  public init(caseID: String, gateRunID: UUID, swiftRunID: UUID, tlcRunID: UUID, comparisonRunID: UUID) throws {
    guard !caseID.isEmpty,
          Set([gateRunID, swiftRunID, tlcRunID, comparisonRunID]).count == 4 else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "correlation", field: "caseID")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.swiftRunID = swiftRunID
    self.tlcRunID = tlcRunID
    self.comparisonRunID = comparisonRunID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, gateRunID, swiftRunID, tlcRunID, comparisonRunID
  }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      gateRunID: container.decode(UUID.self, forKey: .gateRunID),
      swiftRunID: container.decode(UUID.self, forKey: .swiftRunID),
      tlcRunID: container.decode(UUID.self, forKey: .tlcRunID),
      comparisonRunID: container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

public struct TemporalLassoWitnessV1: Equatable, Codable, Sendable {
  public let prefixStateIDs: [String]
  public let cycleStateIDs: [String]

  public init(prefixStateIDs: [String], cycleStateIDs: [String]) throws {
    self.prefixStateIDs = prefixStateIDs
    self.cycleStateIDs = cycleStateIDs
    guard prefixStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.count >= 2,
          cycleStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.first == cycleStateIDs.last else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal lasso", field: "state IDs")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case prefixStateIDs, cycleStateIDs }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      prefixStateIDs: container.decode([String].self, forKey: .prefixStateIDs),
      cycleStateIDs: container.decode([String].self, forKey: .cycleStateIDs))
  }
}

public struct TemporalRecurrentComponentV1: Equatable, Codable, Sendable {
  public let stateIDs: [String]
  public let reasonCode: TemporalRecurrentReasonCodeV1

  public init(stateIDs: [String], reasonCode: TemporalRecurrentReasonCodeV1) throws {
    guard !stateIDs.isEmpty, Set(stateIDs).count == stateIDs.count,
          stateIDs.allSatisfy({ !$0.isEmpty }) else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "recurrent component", field: "state IDs or reason")
    }
    self.stateIDs = stateIDs.sorted()
    self.reasonCode = reasonCode
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case stateIDs, reasonCode }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      stateIDs: container.decode([String].self, forKey: .stateIDs),
      reasonCode: container.decode(TemporalRecurrentReasonCodeV1.self, forKey: .reasonCode))
  }
}

public struct TemporalPropertyResultV1: Equatable, Codable, Sendable {
  public let availability: TemporalEvaluationAvailabilityV1
  public let outcome: TemporalPropertyOutcomeV1?
  public let graphID: String
  public let initialStateIDs: [String]
  public let traceAvailability: TemporalTraceAvailabilityV1
  public let traceEvidence: CoreEvidenceReferenceV1?
  public let lasso: TemporalLassoWitnessV1?

  public init(
    availability: TemporalEvaluationAvailabilityV1,
    outcome: TemporalPropertyOutcomeV1?,
    graphID: String,
    initialStateIDs: [String],
    traceAvailability: TemporalTraceAvailabilityV1,
    traceEvidence: CoreEvidenceReferenceV1? = nil,
    lasso: TemporalLassoWitnessV1? = nil
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
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "graph or initial states")
    }
    try traceEvidence?.validate()
    switch availability {
    case .evaluated:
      guard outcome != nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "missing property outcome")
      }
    case .unavailable:
      guard outcome == nil, traceAvailability == .unavailable, traceEvidence == nil, lasso == nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "unavailable evaluation")
      }
      return
    }
    switch traceAvailability {
    case .available:
      guard traceEvidence != nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "traceEvidence")
      }
      if outcome == .violated, lasso == nil {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "lasso")
      }
    case .unavailable:
      guard traceEvidence == nil, lasso == nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "unavailable trace")
      }
    case .notApplicable:
      guard outcome == .satisfied, traceEvidence == nil, lasso == nil else {
        throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "temporal result", field: "not applicable trace")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case availability, outcome, graphID, initialStateIDs, traceAvailability, traceEvidence, lasso
  }

  public init(from decoder: Decoder) throws {
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      availability: container.decode(TemporalEvaluationAvailabilityV1.self, forKey: .availability),
      outcome: try container.decodeIfPresent(TemporalPropertyOutcomeV1.self, forKey: .outcome),
      graphID: container.decode(String.self, forKey: .graphID),
      initialStateIDs: container.decode([String].self, forKey: .initialStateIDs),
      traceAvailability: container.decode(TemporalTraceAvailabilityV1.self, forKey: .traceAvailability),
      traceEvidence: try container.decodeIfPresent(CoreEvidenceReferenceV1.self, forKey: .traceEvidence),
      lasso: try container.decodeIfPresent(TemporalLassoWitnessV1.self, forKey: .lasso))
  }
}

public struct TemporalCompleteGraphEvidenceV1: Equatable, Codable, Sendable {
  public let propertyRunID: UUID
  public let graphRunID: UUID
  public let arguments: [String]
  public let fingerprintPolynomial: Int
  public let operatingSystem: String
  public let architecture: String
  public let environment: [String: String]
  public let sourceInput: CoreEvidenceReferenceV1
  public let configuration: CoreEvidenceReferenceV1
  public let graphEvents: CoreEvidenceReferenceV1
  public let result: CoreEvidenceReferenceV1

  public init(
    propertyRunID: UUID,
    graphRunID: UUID,
    arguments: [String],
    fingerprintPolynomial: Int,
    operatingSystem: String,
    architecture: String,
    environment: [String: String],
    sourceInput: CoreEvidenceReferenceV1,
    configuration: CoreEvidenceReferenceV1,
    graphEvents: CoreEvidenceReferenceV1,
    result: CoreEvidenceReferenceV1
  ) throws {
    guard propertyRunID != graphRunID else {
      throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(record: "complete graph evidence", field: "run IDs")
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
    let container = try TemporalSymmetryGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      propertyRunID: container.decode(UUID.self, forKey: .propertyRunID),
      graphRunID: container.decode(UUID.self, forKey: .graphRunID),
      arguments: container.decode([String].self, forKey: .arguments),
      fingerprintPolynomial: container.decode(Int.self, forKey: .fingerprintPolynomial),
      operatingSystem: container.decode(String.self, forKey: .operatingSystem),
      architecture: container.decode(String.self, forKey: .architecture),
      environment: container.decode([String: String].self, forKey: .environment),
      sourceInput: container.decode(CoreEvidenceReferenceV1.self, forKey: .sourceInput),
      configuration: container.decode(CoreEvidenceReferenceV1.self, forKey: .configuration),
      graphEvents: container.decode(CoreEvidenceReferenceV1.self, forKey: .graphEvents),
      result: container.decode(CoreEvidenceReferenceV1.self, forKey: .result))
  }

  public func validate() throws {
    _ = try Self(
      propertyRunID: propertyRunID, graphRunID: graphRunID, arguments: arguments,
      fingerprintPolynomial: fingerprintPolynomial, operatingSystem: operatingSystem, architecture: architecture,
      environment: environment, sourceInput: sourceInput,
      configuration: configuration, graphEvents: graphEvents, result: result)
  }
}
