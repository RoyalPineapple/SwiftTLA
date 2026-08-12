import Foundation

public enum SymmetryOrbitAdapterErrorV1: Error, Equatable, Sendable {
  case emptyPermutationGroup
  case incompatiblePermutationDomains
  case permutationDoesNotPreserveStateSpace
  case rawStateSetsDiffer
  case incompleteOrbit(String)
  case reducedStateOutsideOrbit(engine: SymmetryExplorationEngineV1, stateID: String)
  case multipleReducedRepresentatives(engine: SymmetryExplorationEngineV1, representative: String)
  case missingReducedRepresentative(engine: SymmetryExplorationEngineV1, representative: String)
}

public struct SymmetryPermutationV1: Equatable, Sendable {
  public let constantMapping: [String: String]

  public init(constantMapping: [String: String]) throws {
    guard !constantMapping.isEmpty,
          Set(constantMapping.values).count == constantMapping.count,
          Set(constantMapping.keys) == Set(constantMapping.values),
          constantMapping.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }) else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(record: "symmetry permutation", field: "constant mapping")
    }
    self.constantMapping = constantMapping
  }

  public func apply(_ state: CanonicalStateV1) -> CanonicalStateV1 {
    CanonicalStateV1(bindings: state.bindings.mapValues(apply))
  }

  fileprivate static func identity(on domain: Set<String>) throws -> Self {
    try Self(constantMapping: Dictionary(uniqueKeysWithValues: domain.map { ($0, $0) }))
  }

  fileprivate func composing(after other: Self) throws -> Self {
    try Self(constantMapping: Dictionary(uniqueKeysWithValues: constantMapping.keys.map {
      ($0, constantMapping[other.constantMapping[$0]!]!)
    }))
  }

  fileprivate var key: String {
    constantMapping.keys.sorted().map { "\($0)->\(constantMapping[$0]!)" }.joined(separator: "|")
  }

  private func apply(_ value: CanonicalValueV1) -> CanonicalValueV1 {
    switch value {
    case .constant(let name):
      .constant(constantMapping[name] ?? name)
    case .orderedSet(let values):
      .set(values.map(apply))
    case .orderedTuple(let values):
      .tuple(values.map(apply))
    case .orderedRecord(let fields):
      .record(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, apply($0.value)) }))
    case .orderedFunction(let entries):
      .function(entries.map { CanonicalFunctionEntryV1(key: apply($0.key), value: apply($0.value)) })
    case .integer, .boolean, .string:
      value
    }
  }
}

public struct SymmetryOrbitDerivationV1: Equatable, Sendable {
  public let group: [SymmetryPermutationV1]
  public let orbits: [[CanonicalStateKeyV1]]
  public let representativeForState: [CanonicalStateKeyV1: CanonicalStateKeyV1]

  public init(
    states: [CanonicalStateV1],
    permutations: [SymmetryPermutationV1]
  ) throws {
    guard !permutations.isEmpty else { throw SymmetryOrbitAdapterErrorV1.emptyPermutationGroup }
    let domain = Set(permutations[0].constantMapping.keys)
    guard permutations.allSatisfy({ Set($0.constantMapping.keys) == domain }) else {
      throw SymmetryOrbitAdapterErrorV1.incompatiblePermutationDomains
    }
    let closure = try Self.closure(generators: permutations, domain: domain)
    let stateTable = Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0) })
    var unseen = Set(stateTable.keys)
    var derived: [[CanonicalStateKeyV1]] = []
    var representatives: [CanonicalStateKeyV1: CanonicalStateKeyV1] = [:]

    while let first = unseen.sorted().first {
      guard let state = stateTable[first] else { continue }
      let members = Set(closure.map { $0.apply(state).key })
      guard members.allSatisfy({ stateTable[$0] != nil }) else {
        throw SymmetryOrbitAdapterErrorV1.permutationDoesNotPreserveStateSpace
      }
      let ordered = members.sorted()
      let representative = ordered[0]
      for member in ordered { representatives[member] = representative }
      unseen.subtract(members)
      derived.append(ordered)
    }
    self.group = closure
    self.orbits = derived.sorted { $0[0] < $1[0] }
    self.representativeForState = representatives
  }

  private static func closure(
    generators: [SymmetryPermutationV1], domain: Set<String>
  ) throws -> [SymmetryPermutationV1] {
    let identity = try SymmetryPermutationV1.identity(on: domain)
    var known = [identity.key: identity]
    var frontier = [identity]
    while let current = frontier.popLast() {
      for generator in generators {
        let next = try generator.composing(after: current)
        if known[next.key] == nil {
          known[next.key] = next
          frontier.append(next)
        }
      }
    }
    return known.values.sorted { $0.key < $1.key }
  }
}

public struct PinnedSymmetryTLCCorrelationV1: Equatable, Sendable {
  public let caseID: String
  public let gateRunID: UUID
  public let comparisonRunID: UUID
  public let rawRunID: UUID
  public let reducedRunID: UUID

  public init(
    caseID: String,
    gateRunID: UUID,
    comparisonRunID: UUID,
    rawRunID: UUID,
    reducedRunID: UUID
  ) throws {
    guard !caseID.isEmpty,
          Set([gateRunID, comparisonRunID, rawRunID, reducedRunID]).count == 4 else {
      throw TemporalSymmetryGovernanceErrorV1.invalidField(
        record: caseID, field: "TLC raw/reduced run correlation")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.comparisonRunID = comparisonRunID
    self.rawRunID = rawRunID
    self.reducedRunID = reducedRunID
  }
}

public struct PinnedSymmetryTLCAdapterResultV1: Sendable {
  public let correlation: PinnedSymmetryTLCCorrelationV1
  public let raw: CanonicalRunV1
  public let reduced: CanonicalRunV1
}

public struct PinnedSymmetryTLCAdapterV1: Sendable {
  private let processAdapter: TLCProcessAdapterV1

  public init(processAdapter: TLCProcessAdapterV1 = TLCProcessAdapterV1()) {
    self.processAdapter = processAdapter
  }

  public func run(
    correlation: PinnedSymmetryTLCCorrelationV1,
    raw: TLCProcessRequestV1,
    reduced: TLCProcessRequestV1,
    replay: TLCReplayPolicyV1 = .required
  ) throws -> PinnedSymmetryTLCAdapterResultV1 {
    try validatePair(correlation: correlation, raw: raw, reduced: reduced)
    let rawProcess = try processAdapter.run(raw, replay: replay)
    let reducedProcess = try processAdapter.run(reduced, replay: replay)
    let rawEvents = try Data(contentsOf: raw.graphEvents)
    let reducedEvents = try Data(contentsOf: reduced.graphEvents)
    let rawParser = TLCGraphEventParserV1(expectedCase: raw.expectedCase)
    let reducedParser = TLCGraphEventParserV1(expectedCase: reduced.expectedCase)
    guard try rawParser.parse(rawEvents).runID == correlation.rawRunID,
          try reducedParser.parse(reducedEvents).runID == correlation.reducedRunID else {
      throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(
        record: correlation.caseID, field: "TLC graph-event run correlation")
    }
    let rawRun = try rawParser.parseCanonicalRun(rawEvents, result: rawProcess.primary)
    let reducedRun = try reducedParser.parseCanonicalRun(reducedEvents, result: reducedProcess.primary)
    return PinnedSymmetryTLCAdapterResultV1(correlation: correlation, raw: rawRun, reduced: reducedRun)
  }

  private func validatePair(
    correlation: PinnedSymmetryTLCCorrelationV1,
    raw: TLCProcessRequestV1,
    reduced: TLCProcessRequestV1
  ) throws {
    guard raw.caseID == correlation.caseID, reduced.caseID == correlation.caseID,
          raw.runID == correlation.rawRunID, reduced.runID == correlation.reducedRunID,
          raw.expectedCase.moduleSHA256 == reduced.expectedCase.moduleSHA256,
          raw.expectedCase.pin == reduced.expectedCase.pin,
          raw.module.resolvingSymlinksInPath() == reduced.module.resolvingSymlinksInPath(),
          raw.configuration.resolvingSymlinksInPath() != reduced.configuration.resolvingSymlinksInPath() else {
      throw TemporalSymmetryGovernanceErrorV1.inconsistentReference(
        record: raw.caseID, field: "pinned TLC raw/reduced pair")
    }
  }
}
