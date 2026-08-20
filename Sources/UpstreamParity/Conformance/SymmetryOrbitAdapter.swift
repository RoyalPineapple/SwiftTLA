import Foundation

public enum SymmetryOrbitAdapterError: Error, Equatable, Sendable {
  case emptyPermutationGroup
  case incompatiblePermutationDomains
  case permutationDoesNotPreserveStateSpace
  case rawStateSetsDiffer
  case incompleteOrbit(String)
  case reducedStateOutsideOrbit(engine: SymmetryExplorationEngine, stateID: String)
  case multipleReducedRepresentatives(engine: SymmetryExplorationEngine, representative: String)
  case missingReducedRepresentative(engine: SymmetryExplorationEngine, representative: String)
}

public struct SymmetryPermutation: Equatable, Sendable {
  public let constantMapping: [String: String]

  public init(constantMapping: [String: String]) throws {
    guard !constantMapping.isEmpty,
          Set(constantMapping.values).count == constantMapping.count,
          Set(constantMapping.keys) == Set(constantMapping.values),
          constantMapping.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }) else {
      throw TemporalSymmetryGovernanceError.invalidField(record: "symmetry permutation", field: "constant mapping")
    }
    self.constantMapping = constantMapping
  }

  public func apply(_ state: CanonicalState) -> CanonicalState {
    CanonicalState(bindings: state.bindings.mapValues(apply))
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

  private func apply(_ value: CanonicalValue) -> CanonicalValue {
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
      .function(entries.map { CanonicalFunctionEntry(key: apply($0.key), value: apply($0.value)) })
    case .integer, .boolean, .string:
      value
    }
  }
}

public struct SymmetryOrbitDerivation: Equatable, Sendable {
  public let group: [SymmetryPermutation]
  public let orbits: [[CanonicalStateKey]]
  public let representativeForState: [CanonicalStateKey: CanonicalStateKey]

  public init(
    states: [CanonicalState],
    permutations: [SymmetryPermutation]
  ) throws {
    guard !permutations.isEmpty else { throw SymmetryOrbitAdapterError.emptyPermutationGroup }
    let domain = Set(permutations[0].constantMapping.keys)
    guard permutations.allSatisfy({ Set($0.constantMapping.keys) == domain }) else {
      throw SymmetryOrbitAdapterError.incompatiblePermutationDomains
    }
    let closure = try Self.closure(generators: permutations, domain: domain)
    let stateTable = Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0) })
    var unseen = Set(stateTable.keys)
    var derived: [[CanonicalStateKey]] = []
    var representatives: [CanonicalStateKey: CanonicalStateKey] = [:]

    while let first = unseen.sorted().first {
      guard let state = stateTable[first] else { continue }
      let members = Set(closure.map { $0.apply(state).key })
      guard members.allSatisfy({ stateTable[$0] != nil }) else {
        throw SymmetryOrbitAdapterError.permutationDoesNotPreserveStateSpace
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
    generators: [SymmetryPermutation], domain: Set<String>
  ) throws -> [SymmetryPermutation] {
    let identity = try SymmetryPermutation.identity(on: domain)
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

public struct PinnedSymmetryTLCCorrelation: Equatable, Sendable {
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
      throw TemporalSymmetryGovernanceError.invalidField(
        record: caseID, field: "TLC raw/reduced run correlation")
    }
    self.caseID = caseID
    self.gateRunID = gateRunID
    self.comparisonRunID = comparisonRunID
    self.rawRunID = rawRunID
    self.reducedRunID = reducedRunID
  }
}

public struct PinnedSymmetryTLCAdapterResult: Sendable {
  public let correlation: PinnedSymmetryTLCCorrelation
  public let raw: CanonicalRun
  public let reduced: CanonicalRun
}

public struct PinnedSymmetryTLCAdapter: Sendable {
  private let processAdapter: TLCProcessAdapter

  public init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
    self.processAdapter = processAdapter
  }

  public func run(
    correlation: PinnedSymmetryTLCCorrelation,
    raw: TLCProcessRequest,
    reduced: TLCProcessRequest,
    replay: TLCReplayPolicy = .required
  ) throws -> PinnedSymmetryTLCAdapterResult {
    try validatePair(correlation: correlation, raw: raw, reduced: reduced)
    let rawProcess = try processAdapter.run(raw, replay: replay)
    let reducedProcess = try processAdapter.run(reduced, replay: replay)
    let rawEvents = try Data(contentsOf: raw.graphEvents)
    let reducedEvents = try Data(contentsOf: reduced.graphEvents)
    let rawParser = TLCGraphEventParser(expectedCase: raw.expectedCase)
    let reducedParser = TLCGraphEventParser(expectedCase: reduced.expectedCase)
    guard try rawParser.parse(rawEvents).runID == correlation.rawRunID,
          try reducedParser.parse(reducedEvents).runID == correlation.reducedRunID else {
      throw TemporalSymmetryGovernanceError.inconsistentReference(
        record: correlation.caseID, field: "TLC graph-event run correlation")
    }
    let rawRun = try rawParser.parseCanonicalRun(rawEvents, result: rawProcess.primary)
    let reducedRun = try reducedParser.parseCanonicalRun(reducedEvents, result: reducedProcess.primary)
    return PinnedSymmetryTLCAdapterResult(correlation: correlation, raw: rawRun, reduced: reducedRun)
  }

  private func validatePair(
    correlation: PinnedSymmetryTLCCorrelation,
    raw: TLCProcessRequest,
    reduced: TLCProcessRequest
  ) throws {
    guard raw.caseID == correlation.caseID, reduced.caseID == correlation.caseID,
          raw.runID == correlation.rawRunID, reduced.runID == correlation.reducedRunID,
          raw.expectedCase.moduleSHA256 == reduced.expectedCase.moduleSHA256,
          raw.expectedCase.pin == reduced.expectedCase.pin,
          raw.module.resolvingSymlinksInPath() == reduced.module.resolvingSymlinksInPath(),
          raw.configuration.resolvingSymlinksInPath() != reduced.configuration.resolvingSymlinksInPath() else {
      throw TemporalSymmetryGovernanceError.inconsistentReference(
        record: raw.caseID, field: "pinned TLC raw/reduced pair")
    }
  }
}
