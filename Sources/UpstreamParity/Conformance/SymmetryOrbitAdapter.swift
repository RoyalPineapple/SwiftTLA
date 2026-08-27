import Foundation

package enum SymmetryOrbitAdapterError: Error, Equatable, Sendable {
  case emptyPermutationGroup
  case incompatiblePermutationDomains
  case permutationDoesNotPreserveStateSpace
  case permutationLimitExceeded(required: Int, limit: Int)
  case incompleteOrbit(String)
  case reducedStateOutsideOrbit(source: SymmetryGraphSource, stateID: String)
  case multipleReducedRepresentatives(source: SymmetryGraphSource, representative: String)
  case missingReducedRepresentative(source: SymmetryGraphSource, representative: String)
}

package struct SymmetryPermutation: Equatable, Sendable {
  package let constantMapping: [String: String]

  package init(constantMapping: [String: String]) throws {
    guard !constantMapping.isEmpty,
          Set(constantMapping.values).count == constantMapping.count,
          Set(constantMapping.keys) == Set(constantMapping.values),
          constantMapping.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }) else {
      throw EvidenceFormatError.invalidField(record: "symmetry permutation", field: "constant mapping")
    }
    self.constantMapping = constantMapping
  }

  package func apply(_ state: CanonicalState) throws -> CanonicalState {
    CanonicalState(bindings: try state.bindings.mapValues(apply))
  }

  fileprivate static func identity(on domain: Set<String>) throws -> Self {
    try Self(constantMapping: Dictionary(uniqueKeysWithValues: domain.map { ($0, $0) }))
  }

  fileprivate func composing(after other: Self) throws -> Self {
    try Self(constantMapping: Dictionary(uniqueKeysWithValues: try constantMapping.keys.map { key in
      guard let intermediate = other.constantMapping[key],
            let result = constantMapping[intermediate] else {
        throw SymmetryOrbitAdapterError.incompatiblePermutationDomains
      }
      return (key, result)
    }))
  }

  fileprivate var key: String {
    constantMapping.sorted { $0.key < $1.key }
      .map { "\($0.key)->\($0.value)" }
      .joined(separator: "|")
  }

  private func apply(_ value: CanonicalValue) throws -> CanonicalValue {
    switch value {
    case .constant(let name):
      .constant(constantMapping[name] ?? name)
    case .orderedSet(let values):
      .set(try values.map(apply))
    case .orderedTuple(let values):
      .tuple(try values.map(apply))
    case .orderedRecord(let fields):
      .record(try Dictionary(uniqueKeysWithValues: fields.map { ($0.name, try apply($0.value)) }))
    case .orderedFunction(let entries):
      try .function(entries.map { try CanonicalFunctionEntry(key: apply($0.key), value: apply($0.value)) })
    case .integer, .boolean, .string:
      value
    }
  }
}

package struct SymmetryOrbitDerivation: Equatable, Sendable {
  package let orbits: [[CanonicalStateKey]]
  package let representativeForState: [CanonicalStateKey: CanonicalStateKey]

  package init(
    states: [CanonicalState],
    permutations: [SymmetryPermutation],
    maximumPermutationCount: Int
  ) throws {
    guard !permutations.isEmpty else { throw SymmetryOrbitAdapterError.emptyPermutationGroup }
    guard maximumPermutationCount > 0 else {
      throw SymmetryOrbitAdapterError.permutationLimitExceeded(
        required: 1,
        limit: maximumPermutationCount
      )
    }
    let domain = Set(permutations[0].constantMapping.keys)
    guard permutations.allSatisfy({ Set($0.constantMapping.keys) == domain }) else {
      throw SymmetryOrbitAdapterError.incompatiblePermutationDomains
    }
    let closure = try Self.closure(
      generators: permutations,
      domain: domain,
      maximumPermutationCount: maximumPermutationCount
    )
    let stateTable = try canonicalStateTable(states)
    var unseen = Set(stateTable.keys)
    var derived: [[CanonicalStateKey]] = []
    var representatives: [CanonicalStateKey: CanonicalStateKey] = [:]

    while let first = unseen.sorted().first {
      guard let state = stateTable[first] else { continue }
      let members = Set(try closure.map { try $0.apply(state).key })
      guard members.allSatisfy({ stateTable[$0] != nil }) else {
        throw SymmetryOrbitAdapterError.permutationDoesNotPreserveStateSpace
      }
      let ordered = members.sorted()
      let representative = ordered[0]
      for member in ordered { representatives[member] = representative }
      unseen.subtract(members)
      derived.append(ordered)
    }
    self.orbits = derived.sorted { $0[0] < $1[0] }
    self.representativeForState = representatives
  }

  private static func closure(
    generators: [SymmetryPermutation],
    domain: Set<String>,
    maximumPermutationCount: Int
  ) throws -> [SymmetryPermutation] {
    let identity = try SymmetryPermutation.identity(on: domain)
    var known = [identity.key: identity]
    var frontier = [identity]
    while let current = frontier.popLast() {
      for generator in generators {
        let next = try generator.composing(after: current)
        if known[next.key] == nil {
          let (required, overflow) = known.count.addingReportingOverflow(1)
          guard overflow == false, required <= maximumPermutationCount else {
            throw SymmetryOrbitAdapterError.permutationLimitExceeded(
              required: overflow ? .max : required,
              limit: maximumPermutationCount
            )
          }
          known[next.key] = next
          frontier.append(next)
        }
      }
    }
    return known.values.sorted { $0.key < $1.key }
  }
}
