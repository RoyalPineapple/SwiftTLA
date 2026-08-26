import Foundation

package struct FiniteBounds: Equatable, Codable, Sendable {
  package let summary: String
  package let limits: [String: Int]

  package init(summary: String, limits: [String: Int]) throws {
    self.summary = summary
    self.limits = limits
    try validate()
  }

  package func validate() throws {
    guard !summary.isEmpty, !limits.isEmpty, limits.allSatisfy({ !$0.key.isEmpty && $0.value > 0 }) else {
      throw EvidenceFormatError.invalidField(record: "finiteBounds", field: "limits")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case summary, limits }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      summary: container.decode(String.self, forKey: .summary),
      limits: container.decode([String: Int].self, forKey: .limits))
  }
}

package struct RetainedFileReference: Equatable, Codable, Sendable {
  package let path: String
  package let sha256: String

  package init(path: String, sha256: String) throws {
    self.path = path
    self.sha256 = sha256
    try validate()
  }

  package func validate() throws {
    guard !path.isEmpty, !path.hasPrefix("/"), TLCReferencePin.isSHA256(sha256) else {
      throw EvidenceFormatError.invalidField(record: "evidence", field: "path or sha256")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case path, sha256 }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      path: container.decode(String.self, forKey: .path),
      sha256: container.decode(String.self, forKey: .sha256))
  }
}
