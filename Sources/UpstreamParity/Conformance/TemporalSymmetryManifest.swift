import Foundation

package enum TemporalFairnessMode: String, Codable, Sendable {
  case none
  case weak
  case strong
}

package enum TemporalPropertyKind: String, Codable, Sendable {
  case always
  case eventually
  case alwaysEventually
  case eventuallyAlways
  case leadsTo

  package var renderedName: String {
    switch self {
    case .always: "AlwaysP"
    case .eventually: "EventuallyP"
    case .alwaysEventually: "AlwaysEventuallyP"
    case .eventuallyAlways: "EventuallyAlwaysP"
    case .leadsTo: "LeadsToPQ"
    }
  }
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
  case unavailable
}

package enum SymmetryGraphSource: String, Codable, Sendable {
  case swift
  case tlc
}

package struct TemporalCaseConfiguration: Equatable, Codable, Sendable {
  package let property: TemporalPropertyKind
  package let fairness: TemporalFairnessMode
  package let allowsImplicitStuttering: Bool

  package init(
    property: TemporalPropertyKind,
    fairness: TemporalFairnessMode,
    allowsImplicitStuttering: Bool
  ) {
    self.property = property
    self.fairness = fairness
    self.allowsImplicitStuttering = allowsImplicitStuttering
  }

  package var renderedPropertyConfiguration: String {
    let specification = switch fairness {
    case .none: "Spec"
    case .weak: "WFSpec"
    case .strong: "SFSpec"
    }
    return "SPECIFICATION \(specification)\nPROPERTY \(property.renderedName)\n"
  }

  package static let renderedGraphConfiguration = "SPECIFICATION Spec\n"

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case property, fairness, allowsImplicitStuttering
  }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    self.init(
      property: try container.decode(TemporalPropertyKind.self, forKey: .property),
      fairness: try container.decode(TemporalFairnessMode.self, forKey: .fairness),
      allowsImplicitStuttering: try container.decode(Bool.self, forKey: .allowsImplicitStuttering))
  }
}

package struct TemporalCase: Equatable, Codable, Sendable {
  package let id: String
  package let sourceInput: RetainedFileReference
  package let configuration: TemporalCaseConfiguration

  package init(
    id: String,
    sourceInput: RetainedFileReference,
    configuration: TemporalCaseConfiguration
  ) throws {
    self.id = id
    self.sourceInput = sourceInput
    self.configuration = configuration
    try validate()
  }

  private func validate() throws {
    try sourceInput.validate()
    guard !id.isEmpty else {
      throw EvidenceFormatError.invalidField(record: id, field: "temporal case")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case id, sourceInput, configuration }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      sourceInput: try container.decode(RetainedFileReference.self, forKey: .sourceInput),
      configuration: try container.decode(TemporalCaseConfiguration.self, forKey: .configuration))
  }
}

package struct SymmetryCase: Equatable, Codable, Sendable {
  package let id: String
  package let scope: Int

  package init(id: String, scope: Int) throws {
    guard !id.isEmpty, scope > 0 else {
      throw EvidenceFormatError.invalidField(record: id, field: "symmetry case")
    }
    self.id = id
    self.scope = scope
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case id, scope }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      scope: try container.decode(Int.self, forKey: .scope))
  }
}

package struct TemporalSymmetryManifest: Equatable, Codable, Sendable {
  package static let schema = "TemporalSymmetryManifest"
  package let schema: String
  package let temporalCases: [TemporalCase]
  package let symmetryCases: [SymmetryCase]

  package init(temporalCases: [TemporalCase], symmetryCases: [SymmetryCase]) throws {
    try self.init(schema: Self.schema, temporalCases: temporalCases, symmetryCases: symmetryCases)
  }

  package init(schema: String, temporalCases: [TemporalCase], symmetryCases: [SymmetryCase]) throws {
    guard schema == Self.schema, !temporalCases.isEmpty, !symmetryCases.isEmpty else {
      throw EvidenceFormatError.invalidSchema(schema)
    }
    var ids = Set<String>()
    for item in temporalCases {
      guard ids.insert(item.id).inserted else {
        throw EvidenceFormatError.duplicateID(kind: "case", id: item.id)
      }
    }
    for item in symmetryCases {
      guard ids.insert(item.id).inserted else {
        throw EvidenceFormatError.duplicateID(kind: "case", id: item.id)
      }
    }
    self.schema = schema
    self.temporalCases = temporalCases
    self.symmetryCases = symmetryCases
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case schema, temporalCases, symmetryCases }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      schema: try container.decode(String.self, forKey: .schema),
      temporalCases: try container.decode([TemporalCase].self, forKey: .temporalCases),
      symmetryCases: try container.decode([SymmetryCase].self, forKey: .symmetryCases))
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
