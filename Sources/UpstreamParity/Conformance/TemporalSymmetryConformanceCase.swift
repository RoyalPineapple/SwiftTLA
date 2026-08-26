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

package enum TemporalComparisonStatus: String, Codable, Sendable {
  case exact
  case propertyOutcomeDifference
  case graphDifference
  case incompleteGraph
  case unavailable
}

package enum SymmetryExplorationEngine: String, Codable, Sendable {
  case swift
  case tlc
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
  package let sourceInput: RetainedFileReference?
  package let configuration: TemporalSymmetryConfiguration

  package init(
    id: String,
    kind: TemporalSymmetryCaseKind,
    swiftSpec: String,
    sourceInput: RetainedFileReference? = nil,
    configuration: TemporalSymmetryConfiguration
  ) throws {
    self.id = id
    self.kind = kind
    self.swiftSpec = swiftSpec
    self.sourceInput = sourceInput
    self.configuration = configuration
    try validate()
  }

  package func validate() throws {
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
    case id, kind, swiftSpec, sourceInput, configuration
  }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      kind: container.decode(TemporalSymmetryCaseKind.self, forKey: .kind),
      swiftSpec: container.decode(String.self, forKey: .swiftSpec),
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

package enum TemporalPropertyResult: Equatable, Codable, Sendable {
  case satisfied
  case violated(TemporalLassoWitness)
  case unavailable

  private enum Status: String, Codable { case satisfied, violated, unavailable }
  private enum CodingKeys: String, CodingKey, CaseIterable { case status, lasso }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    let lasso = try container.decodeIfPresent(TemporalLassoWitness.self, forKey: .lasso)
    switch try container.decode(Status.self, forKey: .status) {
    case .satisfied:
      guard lasso == nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "satisfied lasso")
      }
      self = .satisfied
    case .violated:
      guard let lasso else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "violated lasso")
      }
      self = .violated(lasso)
    case .unavailable:
      guard lasso == nil else {
        throw EvidenceFormatError.invalidField(record: "temporal result", field: "unavailable lasso")
      }
      self = .unavailable
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .satisfied:
      try container.encode(Status.satisfied, forKey: .status)
    case .violated(let lasso):
      try container.encode(Status.violated, forKey: .status)
      try container.encode(lasso, forKey: .lasso)
    case .unavailable:
      try container.encode(Status.unavailable, forKey: .status)
    }
  }
}
