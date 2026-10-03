import Testing
@testable import SwiftTLA
@testable import UpstreamParity

@Suite("Least Circular Substring corpus module contract")
struct LeastCircularSubstringCorpusModuleContractTests {
  @Test("emits the upstream dependency as a separate module with its scoped finite configuration")
  func emitsModuleBundle() throws {
    let scenarios = try LeastCircularSubstringModel.validationScenarios()
    let scenario = try #require(scenarios.first)
    let bundle = try scenario.render().tlaBundle
    guard let config = bundle.root.cfg else {
      Issue.record("The root module needs a TLC configuration.")
      return
    }

    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(bundle.root.tla.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    #expect(bundle.root.tla.contains("ZSequencesNat == 0..MaxStringLength"))
    #expect(config.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    #expect(config.contains("INVARIANT TypeInvariant"))
    #expect(config.contains("INVARIANT Correctness"))
  }

  @Test("preserves both upstream configurations and typed initial values")
  func retainsUpstreamConfigurations() throws {
    let scenarios = try LeastCircularSubstringModel.validationScenarios()
    #expect(scenarios.count == 2)
    for (scenario, expected) in zip(scenarios, [(2, 6, 127), (3, 8, 9_841)]) {
      let machines = try scenario.initialMachines()
      #expect(machines.count == expected.2)
      for machine in machines {
        #expect(machine.state.n == machine.state.b.count)
        #expect(machine.state.b.values.allSatisfy { $0 >= 0 && $0 < expected.0 })
        #expect(machine.state.b.count <= expected.1)
        #expect(machine.state.f == Dictionary(uniqueKeysWithValues: (0...machine.state.n * 2).map { ($0, -1) }))
        #expect(machine.state.i == -1 && machine.state.j == 1 && machine.state.k == 0)
      }
    }
    #expect(try LeastCircularSubstringModel.spec.compile().description.actions.map(\.name) == [
      "L3", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12", "L13", "L14", "LVR", "Terminating"
    ])
  }
}
