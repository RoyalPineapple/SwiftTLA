import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct VarSpecComponentTests { @Test("Var(name, value) + Variable(ref) registers spec variable")
  func varAsSpecComponent() throws {
    let spec = TLASpec("VarTest") {
      let x = Var("x", 0)
      Variable(x)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    #expect(spec.variables.count == 1)
    #expect(spec.variables[0].name == "x")
    #expect(spec.variables[0].initialization == .value(.int(0)))
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).exploreGraph().states.count == 4)
  }
}
