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

  @Test("Compiled value ordering distinguishes nested values from delimiter-shaped strings")
  func compiledValueOrderingIsStructural() {
    let nested = CompiledValue.tuple([.string("a"), .string("b")])
    let delimiterShaped = CompiledValue.tuple([.string("a,string:b")])

    #expect((nested == delimiterShaped) == false)
    #expect(nested < delimiterShaped || delimiterShaped < nested)
  }

  private func independentlyCanonicalizedGraph(
    _ graph: StateGraph,
    groups: [[TLAValue]]
  ) -> CanonicalGraph {
    let canonicalState = { projection in
      independentlyCanonicalizedState(projection, groups: groups)
    }
    let mappings = permutationMappings(groups)
    var transitions = Set<String>()
    for (sourceID, edges) in graph.transitions {
      guard let source = graph.states[sourceID] else { continue }
      for edge in edges {
        guard let target = graph.states[edge.target] else { continue }
        let sourceRepresentative = canonicalState(source)
        let arguments = mappings.compactMap { mapping -> [String]? in
          guard encode(applyPermutation(source.entries, mapping: mapping)) == sourceRepresentative else {
            return nil
          }
          return edge.label.arguments.map {
            encode(applyPermutation($0, mapping: mapping))
          }
        }.min { $0.lexicographicallyPrecedes($1) }
        guard let arguments else { continue }
        let action = arguments.isEmpty
          ? edge.label.action
          : "\(edge.label.action)(\(arguments.joined(separator: ",")))"
        transitions.insert(
          "\(sourceRepresentative) --\(action)--> \(canonicalState(target))"
        )
      }
    }
    return CanonicalGraph(
      states: Set(graph.states.values.map(canonicalState)),
      transitions: transitions
    )
  }

  private func permutationMappings(_ groups: [[TLAValue]]) -> [[TLAValue: TLAValue]] {
    groups.reduce([[:]]) { partial, group in
      partial.flatMap { existing in
        permutations(group).map { permutation in
          existing.merging(Dictionary(uniqueKeysWithValues: zip(group, permutation))) { current, _ in current }
        }
      }
    }
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

  private func explorationGraphs(for spec: TLASpec) throws -> (raw: StateGraph, reduced: StateGraph) {
    let compilation = try spec.compile()
    return (
      raw: try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100_000, symmetryReduction: .disabled)
      ).exploreGraph(),
      reduced: try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(
          maximumStateLimit: 100_000,
          symmetryReduction: .enabled(maximumPermutationCount: 100_000))
      ).exploreGraph()
    )
  }

  private func storesOneRepresentativePerOrbit(_ graph: StateGraph, groups: [[TLAValue]]) -> Bool {
    let orbits = graph.states.values.map {
      independentlyCanonicalizedState($0, groups: groups)
    }
    return Set(orbits).count == graph.states.count
  }

  @Test("Reduced transitions retain the executed symmetric member")
  func reducedTransitionsRetainExecutedMember() throws {
    let members = SymmetricCollectionVar<Device, Int>("members")
    let spec = TLASpec("MemberActions") {
      SymmetricCollection(members, verificationScope: 2, initial: 0)
      CollectionAction("mark", on: members) { member in
        (members[member] == 0) && members.update(member, to: 1)
      }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try FiniteExplorationConfiguration(
        maximumStateLimit: 100,
        symmetryReduction: .enabled(maximumPermutationCount: 2)
      )
    ).explore()
    let initial = try #require(exploration.initialStateIDs.first)
    let transitions = try #require(exploration.graph.transitions[initial])
    #expect(transitions.count == 2)
    #expect(Set(transitions.flatMap(\.label.arguments)) == Set(spec.symmetricCollections[0].metadata.members))
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
    let graphs = try explorationGraphs(for: symmetric)
    let groups = symmetric.symmetricCollections.map { $0.metadata.members }
    #expect(storesOneRepresentativePerOrbit(graphs.reduced, groups: groups))
    #expect(independentlyCanonicalizedGraph(graphs.raw, groups: groups)
      == independentlyCanonicalizedGraph(graphs.reduced, groups: groups))
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
      let graphs = try explorationGraphs(for: symmetric)
      let groups = symmetric.symmetricCollections.map { $0.metadata.members }
      #expect(storesOneRepresentativePerOrbit(graphs.reduced, groups: groups))
      #expect(independentlyCanonicalizedGraph(graphs.raw, groups: groups)
        == independentlyCanonicalizedGraph(graphs.reduced, groups: groups))
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
    #expect(bundle.tla.contains("\"DevicePhasesMember0\"") == false)
  }

  @Test("Compiled symmetric collections retain their declared variable identity")
  func symmetricCollectionUsesCompiledVariableIdentity() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let compilation = try TLASpec("DeviceIdentity") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
    }.compile()

    let collection = try #require(compilation.semantics.symmetricCollections.first)
    let variable = try #require(compilation.layout.testVariableID(named: devices.name))
    #expect(collection.variable == variable)
    #expect(collection.domainSymbol == "DevicesKeys")
  }
}
