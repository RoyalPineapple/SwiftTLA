import Testing
@testable import SwiftTLA

@Suite(.serialized)
struct SymmetricCollectionDeclarationTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test(
    "A symmetric collection lowers declaration, predicates, and selected updates to existing AST forms"
  )
  func declarationLowersToFunctionQuantifierAndExcept() throws {
    let phases = SymmetricCollectionVar<Device, Int>("phases")
    let spec = TLASpec("Phases") {
      SymmetricCollection(phases, verificationScope: 2, initial: 0)
      CollectionAction("begin", on: phases) { member in
        phases[member] == 0 && phases.update(member, to: 1)
      }
      Invariant("valid") {
        phases.allSatisfy { phase in phase >= 0 && phase <= 1 }
          && phases.contains(where: { $0 == 0 })
      }
    }

    #expect(spec.symmetricCollections.count == 1)
    #expect(spec.symmetricCollections[0].name == "phases")
    #expect(spec.symmetricCollections[0].verificationScope == 2)
    #expect(spec.variables.map(\.name) == ["phases"])

    guard case .function(let initial) = spec.variables[0].initial else {
      Issue.record("Expected the symmetric collection initializer to be a function")
      return
    }
    #expect(initial.count == 2)
    #expect(Set(initial.values) == Set([TLAValue.int(0)]))

    let compilation = try spec.compile()
    let initialState = try firstCompiledState(in: compilation)
    let successors = try spec.symmetricCollections[0].metadata.members.flatMap { member in
      try compiledSuccessors(named: "begin", arguments: [member], in: compilation, from: initialState)
    }
    #expect(successors.count == 2)
    for successor in successors {
      let phaseValue = try renderedValue(named: "phases", in: successor, compilation: compilation)
      guard case .function(let values) = phaseValue else {
        Issue.record("Expected the symmetric collection state to be a function")
        return
      }
      #expect(values.values.filter { $0 == .int(1) }.count == 1)
      #expect(values.values.filter { $0 == .int(0) }.count == 1)
    }
  }
}
