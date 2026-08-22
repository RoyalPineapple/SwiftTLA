@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct SymmetricCollectionCanonicalizationTests {
  private struct Device: Identifiable {
    let id: Int
  }

  private struct CanonicalGraph: Equatable {
    let states: Set<String>
    let transitions: Set<String>
  }

  private func independentlyCanonicalizedGraph(
    _ graph: StateGraph,
    groups: [[TLAValue]]
  ) -> CanonicalGraph {
    let canonicalState = { projection in
      independentlyCanonicalizedState(projection, groups: groups)
    }
    var transitions = Set<String>()
    for (sourceID, edges) in graph.transitions {
      guard let source = graph.states[sourceID] else { continue }
      for edge in edges {
        guard let target = graph.states[edge.target] else { continue }
        transitions.insert(
          "\(canonicalState(source)) --\(edge.action)--> \(canonicalState(target))"
        )
      }
    }
    return CanonicalGraph(
      states: Set(graph.states.values.map(canonicalState)),
      transitions: transitions
    )
  }

  private func independentlyCanonicalizedState(
    _ projection: TLAStateProjection,
    groups: [[TLAValue]]
  ) -> String {
    var candidates = [projection.entries]
    for group in groups {
      candidates = candidates.flatMap { candidate in
        permutations(group).map { permutation in
          applyPermutation(candidate, mapping: Dictionary(uniqueKeysWithValues: zip(group, permutation)))
        }
      }
    }
    return candidates.map(encode).min() ?? ""
  }

  private func permutations(_ values: [TLAValue]) -> [[TLAValue]] {
    guard let first = values.first else { return [[]] }
    return permutations(Array(values.dropFirst())).flatMap { tail in
      (0...tail.count).map { index in
        var permutation = tail
        permutation.insert(first, at: index)
        return permutation
      }
    }
  }

  private func applyPermutation(
    _ state: [TLAStateProjection.Entry],
    mapping: [TLAValue: TLAValue]
  ) -> [TLAStateProjection.Entry] {
    state.map { .init(token: $0.token, value: applyPermutation($0.value, mapping: mapping)) }
  }

  private func applyPermutation(
    _ value: TLAValue,
    mapping: [TLAValue: TLAValue]
  ) -> TLAValue {
    if let replacement = mapping[value] { return replacement }
    switch value {
    case .set(let values): return .set(Set(values.map { applyPermutation($0, mapping: mapping) }))
    case .tuple(let values): return .tuple(values.map { applyPermutation($0, mapping: mapping) })
    case .record(let fields):
      return .record(.init(fields.fields.map { field in
        .init(field.name, applyPermutation(field.value, mapping: mapping))
      }))
    case .function(let entries):
      return .function(Dictionary(uniqueKeysWithValues: entries.map {
        (applyPermutation($0.key, mapping: mapping), applyPermutation($0.value, mapping: mapping))
      }))
    default: return value
    }
  }

  private func encode(_ state: [TLAStateProjection.Entry]) -> String {
    state.sorted { $0.token.description < $1.token.description }
      .map { "\(String(reflecting: $0.token.description))=\(encode($0.value))" }
      .joined(separator: "|")
  }

  private func encode(_ value: TLAValue) -> String {
    switch value {
    case .int(let value): return "int:\(value)"
    case .bool(let value): return "bool:\(value)"
    case .string(let value): return "string:\(String(reflecting: value))"
    case .constant(let value): return "constant:\(String(reflecting: value))"
    case .set(let values): return "set:[\(values.map(encode).sorted().joined(separator: ","))]"
    case .tuple(let values): return "tuple:[\(values.map(encode).joined(separator: ","))]"
    case .record(let fields):
      let entries = fields.fields.map { field in
        "\(String(reflecting: field.name)):\(encode(field.value))"
      }.joined(separator: ",")
      return "record:[\(entries)]"
    case .function(let entries):
      return "function:[\(entries.map { "\(encode($0.key)):\(encode($0.value))" }.sorted().joined(separator: ","))]"
    }
  }

  @Test("Nested symmetric values are quotient-canonicalized without collapsing identities")
  func nestedValuesUseFullStatePermutations() throws {
    let members = SymmetricCollectionVar<Device, TLAValue>("members")
    let selected = "selected"
    let nestedValue = StateExpr.record([
      "member": .variable(selected),
      "nested": .tupleLiteral([
        .setLiteral([.variable(selected)]),
        .functionLiteral(
          .setLiteral([.variable(selected)]),
          "functionKey",
          StateExpr.record(["key": .variable("functionKey")])
        )
      ])
    ])
    let symmetric = TLASpec("NestedMembers") {
      SymmetricCollection(members, verificationScope: 2, initial: .record([:]))
      Action("mark") {
        .existsAction(
          selected,
          .domain(.variable(members.name)),
          .assign(.named(members.name), .except(.variable(members.name), .variable(selected), nestedValue))
        )
      }
    }
    let unreduced = TLASpec(
      name: "NestedMembersUnreduced",
      variables: symmetric.variables,
      actions: symmetric.actions,
      invariants: []
    )

    let rawGraph = try ModelChecker(compilation: try unreduced.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
    let reducedGraph = try ModelChecker(compilation: try symmetric.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
    let groups = symmetric.symmetricCollections.map { $0.metadata.members }
    #expect(independentlyCanonicalizedGraph(rawGraph, groups: groups)
      == independentlyCanonicalizedGraph(reducedGraph, groups: groups))
  }

  @Test("Independent collection groups preserve the exhaustive orbit quotient at scopes one through four")
  func independentGroupsMatchAnExhaustiveRawOrbitQuotient() throws {
    for scope in 1...4 {
      let left = SymmetricCollectionVar<Device, Int>("left")
      let right = SymmetricCollectionVar<Device, Int>("right")
      let symmetric = TLASpec("IndependentMembers\(scope)") {
        SymmetricCollection(left, verificationScope: scope, initial: 0)
        SymmetricCollection(right, verificationScope: scope, initial: 0)
        CollectionAction("markLeft", on: left) { member in
          (left[member] == 0) && left.update(member, to: 1)
        }
        CollectionAction("markRight", on: right) { member in
          (right[member] == 0) && right.update(member, to: 1)
        }
      }
      let unreduced = TLASpec(
        name: "IndependentMembers\(scope)Unreduced",
        variables: symmetric.variables,
        actions: symmetric.actions,
        invariants: []
      )

      let groups = symmetric.symmetricCollections.map { $0.metadata.members }
      let rawGraph = try ModelChecker(compilation: try unreduced.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
      let reducedGraph = try ModelChecker(compilation: try symmetric.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
      #expect(independentlyCanonicalizedGraph(rawGraph, groups: groups)
        == independentlyCanonicalizedGraph(reducedGraph, groups: groups))
    }
  }

  @Test("TLA and CFG declare symmetric members as TLC model values")
  func symmetricCollectionsEmitModelValueSymmetryBundle() throws {
    let members = SymmetricCollectionVar<Device, Int>("devicePhases")
    let spec = TLASpec("DevicePhases") {
      SymmetricCollection(members, verificationScope: 2, initial: 0)
    }

    let bundle = try spec.compile().renderedTLAModuleBundle()
    #expect(bundle.tla.contains("CONSTANTS DevicePhasesMember0, DevicePhasesMember1"))
    #expect(bundle.tla.contains("DevicePhasesKeys == {DevicePhasesMember0, DevicePhasesMember1}"))
    #expect(bundle.tla.contains("SymmDevicePhases == Permutations(DevicePhasesKeys)"))
    #expect(bundle.tla.contains("devicePhases = [member \\in DevicePhasesKeys |-> 0]"))
    #expect(bundle.cfg.contains("CONSTANT DevicePhasesMember0 = DevicePhasesMember0"))
    #expect(bundle.cfg.contains("CONSTANT DevicePhasesMember1 = DevicePhasesMember1"))
    #expect(bundle.cfg.contains("SYMMETRY SymmDevicePhases"))
    #expect(!bundle.tla.contains("\"DevicePhasesMember0\""))
  }
}
