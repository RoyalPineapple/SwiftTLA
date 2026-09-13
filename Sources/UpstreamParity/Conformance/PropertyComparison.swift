import SwiftTLA

/// A named model property and deadlock freedom are independent checks.
package enum ModelCheck: Equatable, Encodable, Sendable {
  case property(String)
  case deadlock

  package var artifactPath: String {
    switch self {
    case .property(let name): "properties/\(name)"
    case .deadlock: "deadlock"
    }
  }

  package func bundle(from rendered: RenderedSpecification) throws -> TLAModuleBundle {
    switch self {
    case .property(let name): try rendered.tlaBundle(checking: [name], checkDeadlock: false)
    case .deadlock: try rendered.tlaBundle(checking: [], checkDeadlock: true)
    }
  }
}

package enum PropertyComparisonStatus: String, Codable, Sendable {
  case exact
  case propertyOutcomeDifference
  case graphDifference
  case unavailable
}

package struct PropertyComparison: Equatable, Encodable, Sendable {
  package static let schema = "PropertyComparison"

  package let schema = Self.schema
  package let caseID: String
  package let check: ModelCheck
  package let status: PropertyComparisonStatus
  package let swiftResult: PropertyResult
  package let tlcResult: PropertyResult
}
