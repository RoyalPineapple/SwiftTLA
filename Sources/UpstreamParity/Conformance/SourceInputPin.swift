import Foundation

package struct SourceInputPin: Equatable, Codable, Sendable {
  package let path: String
  package let sha256: String

  package init(path: String, sha256: String) throws {
    self.path = path
    self.sha256 = sha256
    try validate()
  }

  package func validate() throws {
    guard !path.isEmpty, !path.hasPrefix("/"), TLCReferencePin.isSHA256(sha256) else {
      throw EvidenceFormatError.invalidField(record: "source input", field: "path or sha256")
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
