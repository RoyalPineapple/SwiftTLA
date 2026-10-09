@testable import SwiftTLA
import Testing

@Suite(.serialized) struct VarSpecComponentTests { @Test("Var(name, value) + Variable(ref) registers spec variable")
  func varAsSpecComponent() {
    let spec = TLASpec("VarTest") {
      let x = Var("x", 0)
      Variable(x)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    #expect(spec.variables.count == 1)
    #expect(spec.variables[0].name == "x")
    #expect(spec.variables[0].initialization == .value(.int(0)))
  }
}
