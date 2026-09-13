package enum PropertyResult: Equatable, Codable, Sendable {
  case satisfied
  case violated(GraphTrace)
  case unavailable

  private enum Status: String, Codable { case satisfied, violated, unavailable }
  private enum CodingKeys: String, CodingKey, CaseIterable { case status, trace }

  package init(from decoder: Decoder) throws {
    let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    let trace = try container.decodeIfPresent(GraphTrace.self, forKey: .trace)
    switch try container.decode(Status.self, forKey: .status) {
    case .satisfied:
      guard trace == nil else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "satisfied trace")
      }
      self = .satisfied
    case .violated:
      guard let trace else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "violated trace")
      }
      self = .violated(trace)
    case .unavailable:
      guard trace == nil else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "unavailable trace")
      }
      self = .unavailable
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .satisfied:
      try container.encode(Status.satisfied, forKey: .status)
    case .violated(let trace):
      try container.encode(Status.violated, forKey: .status)
      try container.encode(trace, forKey: .trace)
    case .unavailable:
      try container.encode(Status.unavailable, forKey: .status)
    }
  }
}
