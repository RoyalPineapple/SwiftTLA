import Foundation
import SwiftTLA

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


package enum SymmetryGraphSource: String, Codable, Sendable {
  case swift
  case tlc
}

package struct TemporalCase: Equatable, Codable, Sendable {
  package let id: String
  package let fairness: TemporalFairnessMode
  package let exploration: FiniteExplorationConfiguration
  package let expectedProperties: [String: PropertyExpectation]

  package init(
    id: String,
    fairness: TemporalFairnessMode,
    exploration: FiniteExplorationConfiguration,
    expectedProperties: [String: PropertyExpectation]
  ) throws {
    self.id = id
    self.fairness = fairness
    self.exploration = exploration
    self.expectedProperties = expectedProperties
    try validate()
  }

  private func validate() throws {
    guard id.isEmpty == false, !expectedProperties.isEmpty,
          expectedProperties.keys.allSatisfy({ !$0.isEmpty }),
          case .disabled = exploration.symmetryReduction else {
      throw EvidenceFormatError.invalidField(record: id, field: "temporal case")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, fairness, exploration, expectedProperties
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(validatingKeys: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      fairness: try container.decode(TemporalFairnessMode.self, forKey: .fairness),
      exploration: try container.decode(FiniteExplorationConfiguration.self, forKey: .exploration),
      expectedProperties: try container.decode([String: PropertyExpectation].self, forKey: .expectedProperties))
  }
}

package struct SymmetryCase: Equatable, Codable, Sendable {
  package let id: String
  package let scope: Int
  package let rawExploration: FiniteExplorationConfiguration
  package let reducedExploration: FiniteExplorationConfiguration

  package init(
    id: String,
    scope: Int,
    rawExploration: FiniteExplorationConfiguration,
    reducedExploration: FiniteExplorationConfiguration
  ) throws {
    guard id.isEmpty == false, scope > 0,
          case .disabled = rawExploration.symmetryReduction,
          case .enabled = reducedExploration.symmetryReduction else {
      throw EvidenceFormatError.invalidField(record: id, field: "symmetry case")
    }
    self.id = id
    self.scope = scope
    self.rawExploration = rawExploration
    self.reducedExploration = reducedExploration
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, scope, rawExploration, reducedExploration
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(validatingKeys: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      scope: try container.decode(Int.self, forKey: .scope),
      rawExploration: try container.decode(
        FiniteExplorationConfiguration.self,
        forKey: .rawExploration),
      reducedExploration: try container.decode(
        FiniteExplorationConfiguration.self,
        forKey: .reducedExploration))
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
    let container = try decoder.container(validatingKeys: CodingKeys.self)
    try self.init(
      schema: try container.decode(String.self, forKey: .schema),
      temporalCases: try container.decode([TemporalCase].self, forKey: .temporalCases),
      symmetryCases: try container.decode([SymmetryCase].self, forKey: .symmetryCases))
  }
}
