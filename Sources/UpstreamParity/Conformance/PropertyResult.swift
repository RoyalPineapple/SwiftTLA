import SwiftTLA
extension ValidationExpectation {
  package func accepts(_ result: PropertyResult) -> Bool {
    switch (self, result) {
    case (.satisfied, .satisfied), (.satisfied, .reached),
         (.violated, .violated), (.violated, .unreachable): true
    default: false
    }
  }
}

package enum PropertyResult: Equatable, Codable, Sendable {
  case satisfied
  case violated(GraphTrace)
  case reached(GraphTrace)
  case unreachable
  case unavailable

  package var isSatisfied: Bool {
    switch self {
    case .satisfied, .reached: true
    case .violated, .unreachable, .unavailable: false
    }
  }

  private enum Status: String, Codable { case satisfied, violated, reached, unreachable, unavailable }
  private enum CodingKeys: String, CodingKey, CaseIterable { case status, trace }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(validatingKeys: CodingKeys.self)
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
    case .reached:
      guard let trace, trace.cycleStartIndex == nil else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "reachability witness")
      }
      self = .reached(trace)
    case .unreachable:
      guard trace == nil else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "unreachable trace")
      }
      self = .unreachable
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
    case .reached(let trace):
      guard trace.cycleStartIndex == nil else {
        throw EvidenceFormatError.invalidField(record: "property result", field: "reachability witness")
      }
      try container.encode(Status.reached, forKey: .status)
      try container.encode(trace, forKey: .trace)
    case .unreachable:
      try container.encode(Status.unreachable, forKey: .status)
    }
  }
}
