import Foundation

public enum ConformanceGovernanceError: Error, Equatable, Sendable {
  case invalidSchema(String)
  case duplicateID(kind: String, id: String)
  case invalidField(record: String, field: String)
  case unknownCaseID(String)
  case unknownDivergenceID(String)
  case inconsistentReference(record: String, field: String)
  case unsupportedCategory(String)
}

enum ConformanceDecoding {
  private struct AnyCodingKey: CodingKey {
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

  static func container<Key>(
    _ decoder: Decoder,
    keyedBy keyType: Key.Type
  ) throws -> KeyedDecodingContainer<Key> where Key: CodingKey & CaseIterable {
    let actual = try decoder.container(keyedBy: AnyCodingKey.self)
    let known = Set(Key.allCases.map(\.stringValue))
    let unknown = Set(actual.allKeys.map(\.stringValue)).subtracting(known)
    guard unknown.isEmpty else {
      throw ConformanceGovernanceError.invalidField(
        record: "decode", field: "unknown field \(unknown.sorted().joined(separator: ","))")
    }
    return try decoder.container(keyedBy: keyType)
  }
}

public enum ConformanceDivergenceClassification: String, CaseIterable, Codable, Sendable {
  case swiftTLADefect
  case harnessOrConfigurationDefect
  case unsupportedConstruct
  case publishedSemanticsAmbiguity
  case suspectedTLCDefect
}

public enum ConformanceDivergenceDisposition: String, CaseIterable, Codable, Sendable {
  case open
  case resolved
  case unsupported
  case awaitingSemanticsReview
  case suspectedReferenceDefect
}
