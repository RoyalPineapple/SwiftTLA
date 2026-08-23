import Foundation

public struct CoreFiniteBounds: Equatable, Codable, Sendable {
  public let summary: String
  public let limits: [String: Int]

  public init(summary: String, limits: [String: Int]) throws {
    self.summary = summary
    self.limits = limits
    try validate()
  }

  public func validate() throws {
    guard !summary.isEmpty, !limits.isEmpty, limits.allSatisfy({ !$0.key.isEmpty && $0.value > 0 }) else {
      throw ConformanceGovernanceError.invalidField(record: "finiteBounds", field: "limits")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case summary, limits }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      summary: container.decode(String.self, forKey: .summary),
      limits: container.decode([String: Int].self, forKey: .limits))
  }
}

public struct CoreEvidenceProvenance: Equatable, Codable, Sendable {
  public let caseID: String
  public let moduleSHA256: String
  public let cfgSHA256: String
  public let argumentsSHA256: String
  public let tlcTag: String
  public let tlcCommit: String
  public let tlcJarSHA256: String
  public let javaDistribution: String
  public let javaVersion: String
  public let javaArchiveSHA256: String
  public let bridgeClass: String
  public let bridgeSourceSHA256: String
  public let bridgeBinarySHA256: String

  public init(
    caseID: String,
    moduleSHA256: String,
    cfgSHA256: String,
    argumentsSHA256: String,
    tlcTag: String,
    tlcCommit: String,
    tlcJarSHA256: String,
    javaDistribution: String,
    javaVersion: String,
    javaArchiveSHA256: String,
    bridgeClass: String,
    bridgeSourceSHA256: String,
    bridgeBinarySHA256: String
  ) throws {
    self.caseID = caseID
    self.moduleSHA256 = moduleSHA256
    self.cfgSHA256 = cfgSHA256
    self.argumentsSHA256 = argumentsSHA256
    self.tlcTag = tlcTag
    self.tlcCommit = tlcCommit
    self.tlcJarSHA256 = tlcJarSHA256
    self.javaDistribution = javaDistribution
    self.javaVersion = javaVersion
    self.javaArchiveSHA256 = javaArchiveSHA256
    self.bridgeClass = bridgeClass
    self.bridgeSourceSHA256 = bridgeSourceSHA256
    self.bridgeBinarySHA256 = bridgeBinarySHA256
    try validate()
  }

  public func validate() throws {
    guard !caseID.isEmpty, !tlcTag.isEmpty, !tlcCommit.isEmpty, !javaDistribution.isEmpty,
          !javaVersion.isEmpty, !bridgeClass.isEmpty else {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: "provenance")
    }
    for (field, digest) in [
      ("moduleSHA256", moduleSHA256), ("cfgSHA256", cfgSHA256),
      ("argumentsSHA256", argumentsSHA256), ("tlcJarSHA256", tlcJarSHA256),
      ("javaArchiveSHA256", javaArchiveSHA256),
      ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
    ] where !TLCReferencePin.isSHA256(digest) {
      throw ConformanceGovernanceError.invalidField(record: caseID, field: field)
    }
  }

  package func tlcReferencePin() throws -> TLCReferencePin {
    try .init(
      tag: tlcTag,
      commit: tlcCommit,
      jarSHA256: tlcJarSHA256,
      javaDistribution: javaDistribution,
      javaVersion: javaVersion,
      javaArchiveSHA256: javaArchiveSHA256,
      bridgeClass: bridgeClass,
      bridgeSourceSHA256: bridgeSourceSHA256,
      bridgeBinarySHA256: bridgeBinarySHA256
    )
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case caseID, moduleSHA256, cfgSHA256, argumentsSHA256, tlcTag, tlcCommit, tlcJarSHA256
    case javaDistribution, javaVersion, javaArchiveSHA256, bridgeClass, bridgeSourceSHA256
    case bridgeBinarySHA256
  }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      caseID: container.decode(String.self, forKey: .caseID),
      moduleSHA256: container.decode(String.self, forKey: .moduleSHA256),
      cfgSHA256: container.decode(String.self, forKey: .cfgSHA256),
      argumentsSHA256: container.decode(String.self, forKey: .argumentsSHA256),
      tlcTag: container.decode(String.self, forKey: .tlcTag),
      tlcCommit: container.decode(String.self, forKey: .tlcCommit),
      tlcJarSHA256: container.decode(String.self, forKey: .tlcJarSHA256),
      javaDistribution: container.decode(String.self, forKey: .javaDistribution),
      javaVersion: container.decode(String.self, forKey: .javaVersion),
      javaArchiveSHA256: container.decode(String.self, forKey: .javaArchiveSHA256),
      bridgeClass: container.decode(String.self, forKey: .bridgeClass),
      bridgeSourceSHA256: container.decode(String.self, forKey: .bridgeSourceSHA256),
      bridgeBinarySHA256: container.decode(String.self, forKey: .bridgeBinarySHA256))
  }
}

public struct CoreEvidenceReference: Equatable, Codable, Sendable {
  public let path: String
  public let sha256: String

  public init(path: String, sha256: String) throws {
    self.path = path
    self.sha256 = sha256
    try validate()
  }

  public func validate() throws {
    guard !path.isEmpty, !path.hasPrefix("/"), TLCReferencePin.isSHA256(sha256) else {
      throw ConformanceGovernanceError.invalidField(record: "evidence", field: "path or sha256")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case path, sha256 }

  public init(from decoder: Decoder) throws {
    let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
    try self.init(
      path: container.decode(String.self, forKey: .path),
      sha256: container.decode(String.self, forKey: .sha256))
  }
}
