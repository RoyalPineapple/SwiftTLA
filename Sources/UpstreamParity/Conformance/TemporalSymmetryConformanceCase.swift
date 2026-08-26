import Foundation

package enum TemporalSymmetryCaseKind: String, Codable, Sendable {
  case temporal
  case symmetry
}

package enum TemporalFairnessMode: String, Codable, Sendable {
  case none
  case weak
  case strong
}

package enum TemporalSymmetryOutcome: String, Codable, Sendable {
  case exact
  case difference
  case unavailable
}

package enum TemporalPropertyOutcome: String, Codable, Sendable {
  case satisfied
  case violated
}

package enum TemporalEvaluationAvailability: String, Codable, Sendable {
  case evaluated
  case unavailable
}

package enum TemporalTraceAvailability: String, Codable, Sendable {
  case available
  case unavailable
  case notApplicable
}

package enum TemporalSymmetryDiagnosticCode: String, Codable, Sendable {
  case exactAgreement
  case propertyOutcomeDifference
  case applicableOutcomeDifference
  case graphIdentityDifference
  case initialStateDifference
  case temporalEvidenceUnavailable
  case orbitEvidenceUnavailable
  case orbitDifference
}

package enum SymmetryExplorationEngine: String, Codable, Sendable {
  case swift
  case tlc
}

package enum SymmetryApplicableOutcome: String, Codable, Sendable {
  case notApplicable
  case satisfied
  case violated
  case deadlocked
}

package struct TemporalCompleteGraphPassDeclaration: Equatable, Codable, Sendable {
  package let configuration: RetainedFileReference

  package init(configuration: RetainedFileReference) throws {
    self.configuration = configuration
    try configuration.validate()
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case configuration }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(configuration: container.decode(RetainedFileReference.self, forKey: .configuration))
  }
}

package struct TemporalSymmetryConfiguration: Equatable, Codable, Sendable {
  package let property: String?
  package let fairness: TemporalFairnessMode?
  package let fairnessActions: [String]
  package let symmetryCollection: String?
  package let symmetryScope: Int?
  package let symmetryEnabled: Bool
  package let allowsImplicitStuttering: Bool
  package let completeGraphPass: TemporalCompleteGraphPassDeclaration?

  package init(
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

  package func validate() throws {
    guard Set(fairnessActions).count == fairnessActions.count,
          fairnessActions.allSatisfy({ !$0.isEmpty }) else {
      throw EvidenceFormatError.invalidField(record: "configuration", field: "fairnessActions")
    }
    if property == nil {
      guard fairness == nil, fairnessActions.isEmpty, !allowsImplicitStuttering, completeGraphPass == nil else {
        throw EvidenceFormatError.invalidField(record: "configuration", field: "temporal fields")
      }
    } else {
      guard property?.isEmpty == false, fairness != nil else {
        throw EvidenceFormatError.invalidField(record: "configuration", field: "property or fairness")
      }
    }
    if completeGraphPass != nil {
      guard property != nil else {
        throw EvidenceFormatError.invalidField(record: "configuration", field: "complete graph pass")
      }
    }
    if symmetryEnabled {
      guard symmetryCollection?.isEmpty == false, (symmetryScope ?? 0) > 0 else {
        throw EvidenceFormatError.invalidField(record: "configuration", field: "symmetry")
      }
    } else {
      guard symmetryCollection == nil, symmetryScope == nil else {
        throw EvidenceFormatError.invalidField(record: "configuration", field: "disabled symmetry")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case property, fairness, fairnessActions, symmetryCollection, symmetryScope, symmetryEnabled
    case allowsImplicitStuttering, completeGraphPass
  }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
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

package struct TemporalSymmetryCase: Equatable, Codable, Sendable {
  package let id: String
  package let kind: TemporalSymmetryCaseKind
  package let swiftSpec: String
  package let finiteBounds: FiniteBounds
  package let sourceInput: RetainedFileReference?
  package let configuration: TemporalSymmetryConfiguration

  package init(
    id: String,
    kind: TemporalSymmetryCaseKind,
    swiftSpec: String,
    finiteBounds: FiniteBounds,
    sourceInput: RetainedFileReference? = nil,
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

  package func validate() throws {
    try finiteBounds.validate()
    try sourceInput?.validate()
    try configuration.validate()
    guard !id.isEmpty, !swiftSpec.isEmpty else {
      throw EvidenceFormatError.invalidField(record: id, field: "case declaration")
    }
    switch kind {
    case .temporal:
      guard configuration.property != nil, configuration.fairness != nil,
            configuration.symmetryEnabled == false, sourceInput != nil else {
        throw EvidenceFormatError.inconsistentReference(record: id, field: "temporal configuration")
      }
    case .symmetry:
      guard configuration.property == nil, configuration.symmetryEnabled, sourceInput == nil else {
        throw EvidenceFormatError.inconsistentReference(record: id, field: "symmetry configuration")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, swiftSpec, finiteBounds, sourceInput, configuration
  }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKind.self, forKey: .kind),
      swiftSpec: container.decode(String.self, forKey: .swiftSpec),
      finiteBounds: container.decode(FiniteBounds.self, forKey: .finiteBounds),
      sourceInput: try container.decodeIfPresent(RetainedFileReference.self, forKey: .sourceInput),
      configuration: container.decode(TemporalSymmetryConfiguration.self, forKey: .configuration))
  }
}

package struct TemporalSymmetryCases: Equatable, Codable, Sendable {
  package static let schema = "TemporalSymmetryCases"
  package let schema: String
  package let cases: [TemporalSymmetryCase]

  package init(cases: [TemporalSymmetryCase]) throws {
    try self.init(schema: Self.schema, cases: cases)
  }

  package init(schema: String, cases: [TemporalSymmetryCase]) throws {
    guard schema == Self.schema else { throw EvidenceFormatError.invalidSchema(schema) }
    var ids = Set<String>()
    for item in cases {
      try item.validate()
      guard ids.insert(item.id).inserted else {
        throw EvidenceFormatError.duplicateID(kind: "case", id: item.id)
      }
    }
    self.schema = schema
    self.cases = cases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(schema: container.decode(String.self, forKey: .schema), cases: container.decode([TemporalSymmetryCase].self, forKey: .cases))
  }
}

package struct TemporalSymmetryCaseOutcomeCorrelation: Equatable, Codable, Sendable {
  package let caseID: String
  package let runID: UUID
  package let swiftRunID: UUID
  package let tlcRunID: UUID
  package let comparisonRunID: UUID

  package init(caseID: String, runID: UUID, swiftRunID: UUID, tlcRunID: UUID, comparisonRunID: UUID) throws {
    guard !caseID.isEmpty,
          Set([runID, swiftRunID, tlcRunID, comparisonRunID]).count == 4 else {
      throw EvidenceFormatError.invalidField(record: "correlation", field: "caseID")
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

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      runID: container.decode(UUID.self, forKey: .runID),
      swiftRunID: container.decode(UUID.self, forKey: .swiftRunID),
      tlcRunID: container.decode(UUID.self, forKey: .tlcRunID),
      comparisonRunID: container.decode(UUID.self, forKey: .comparisonRunID))
  }
}

package struct TemporalLassoWitness: Equatable, Codable, Sendable {
  package let prefixStateIDs: [String]
  package let cycleStateIDs: [String]

  package init(prefixStateIDs: [String], cycleStateIDs: [String]) throws {
    self.prefixStateIDs = prefixStateIDs
    self.cycleStateIDs = cycleStateIDs
    guard prefixStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.count >= 2,
          cycleStateIDs.allSatisfy({ !$0.isEmpty }), cycleStateIDs.first == cycleStateIDs.last else {
      throw EvidenceFormatError.invalidField(record: "temporal lasso", field: "state IDs")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case prefixStateIDs, cycleStateIDs }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      prefixStateIDs: container.decode([String].self, forKey: .prefixStateIDs),
      cycleStateIDs: container.decode([String].self, forKey: .cycleStateIDs))
  }
}

package struct TemporalPropertyResult: Equatable, Codable, Sendable {
  package let availability: TemporalEvaluationAvailability
  package let outcome: TemporalPropertyOutcome?
  package let graphID: String
  package let initialStateIDs: [String]
  package let traceAvailability: TemporalTraceAvailability
  package let traceEvidence: RetainedFileReference?
  package let lasso: TemporalLassoWitness?

  package init(
    availability: TemporalEvaluationAvailability,
    outcome: TemporalPropertyOutcome?,
    graphID: String,
    initialStateIDs: [String],
    traceAvailability: TemporalTraceAvailability,
    traceEvidence: RetainedFileReference? = nil,
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

  package func validate() throws {
    guard !graphID.isEmpty, !initialStateIDs.isEmpty,
          Set(initialStateIDs).count == initialStateIDs.count,
          initialStateIDs.allSatisfy({ !$0.isEmpty }) else {
      throw EvidenceFormatError.invalidField(record: "temporal result", field: "graph or initial states")
    }
    try traceEvidence?.validate()
    switch availability {
    case .evaluated:
      guard outcome != nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "missing property outcome")
      }
    case .unavailable:
      guard outcome == nil, traceAvailability == .unavailable, traceEvidence == nil, lasso == nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "unavailable evaluation")
      }
      return
    }
    switch traceAvailability {
    case .available:
      guard traceEvidence != nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "traceEvidence")
      }
      if outcome == .violated, lasso == nil {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "lasso")
      }
    case .unavailable:
      guard traceEvidence == nil, lasso == nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "unavailable trace")
      }
    case .notApplicable:
      guard outcome == .satisfied, traceEvidence == nil, lasso == nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "not applicable trace")
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case availability, outcome, graphID, initialStateIDs, traceAvailability, traceEvidence, lasso
  }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      availability: container.decode(TemporalEvaluationAvailability.self, forKey: .availability),
      outcome: try container.decodeIfPresent(TemporalPropertyOutcome.self, forKey: .outcome),
      graphID: container.decode(String.self, forKey: .graphID),
      initialStateIDs: container.decode([String].self, forKey: .initialStateIDs),
      traceAvailability: container.decode(TemporalTraceAvailability.self, forKey: .traceAvailability),
      traceEvidence: try container.decodeIfPresent(RetainedFileReference.self, forKey: .traceEvidence),
      lasso: try container.decodeIfPresent(TemporalLassoWitness.self, forKey: .lasso))
  }
}

package struct TemporalCompleteGraphEvidence: Equatable, Codable, Sendable {
  package let propertyRunID: UUID
  package let graphRunID: UUID
  package let arguments: [String]
  package let fingerprintPolynomial: Int
  package let operatingSystem: String
  package let architecture: String
  package let environment: [String: String]
  package let sourceInput: RetainedFileReference
  package let configuration: RetainedFileReference
  package let graphEvents: RetainedFileReference
  package let result: RetainedFileReference

  package init(
    propertyRunID: UUID,
    graphRunID: UUID,
    arguments: [String],
    fingerprintPolynomial: Int,
    operatingSystem: String,
    architecture: String,
    environment: [String: String],
    sourceInput: RetainedFileReference,
    configuration: RetainedFileReference,
    graphEvents: RetainedFileReference,
    result: RetainedFileReference
  ) throws {
    guard propertyRunID != graphRunID else {
      throw EvidenceFormatError.inconsistentReference(record: "complete graph evidence", field: "run IDs")
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

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      propertyRunID: container.decode(UUID.self, forKey: .propertyRunID),
      graphRunID: container.decode(UUID.self, forKey: .graphRunID),
      arguments: container.decode([String].self, forKey: .arguments),
      fingerprintPolynomial: container.decode(Int.self, forKey: .fingerprintPolynomial),
      operatingSystem: container.decode(String.self, forKey: .operatingSystem),
      architecture: container.decode(String.self, forKey: .architecture),
      environment: container.decode([String: String].self, forKey: .environment),
      sourceInput: container.decode(RetainedFileReference.self, forKey: .sourceInput),
      configuration: container.decode(RetainedFileReference.self, forKey: .configuration),
      graphEvents: container.decode(RetainedFileReference.self, forKey: .graphEvents),
      result: container.decode(RetainedFileReference.self, forKey: .result))
  }

  package func validate() throws {
    _ = try Self(
      propertyRunID: propertyRunID, graphRunID: graphRunID, arguments: arguments,
      fingerprintPolynomial: fingerprintPolynomial, operatingSystem: operatingSystem, architecture: architecture,
      environment: environment, sourceInput: sourceInput,
      configuration: configuration, graphEvents: graphEvents, result: result)
  }
}
