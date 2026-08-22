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
    let initialState = try #require(try compilation.initialStateProjections().first)
    let begin = try #require(compilation.actionID(named: "begin"))
    let successors = try compilation.successors(for: begin, arguments: [], from: initialState)
    #expect(successors.count == 2)
    for successor in successors {
      let phaseValue = try #require(value("phases", in: successor))
      guard case .function(let values) = phaseValue else {
        Issue.record("Expected the symmetric collection state to be a function")
        return
      }
      #expect(values.values.filter { $0 == .int(1) }.count == 1)
      #expect(values.values.filter { $0 == .int(0) }.count == 1)
    }
  }

  @Test("SymmetricCollection initialized variable produces correct name and initial")
  func stateVarOverload() {
    let initialState = Var("phases", 0)
    let decl = SymmetricCollection(initialState, verificationScope: 3, elementType: Device.self)

    #expect(decl.name == "phases")
    #expect(decl.initial == .int(0))
    #expect(decl.verificationScope == 3)
  }
}
