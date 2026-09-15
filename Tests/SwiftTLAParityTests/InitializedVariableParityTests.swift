import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct InitializedVariableParityTests { @Test("initialized and explicitly declared variables produce the same StateGraph")
  func initializedVarVsExplicitVariable() throws {
    let x = Var<Int>("x")
    let spec1 = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("ok") { x >= 0 && x <= 5 }
    }
    let sv = Var("x", 0)
    let spec2 = TLASpec("Test") {
      Variable(sv)
      Action("inc") { sv.becomes(sv + 1).when(sv < 5) }
      Invariant("ok") { sv >= 0 && sv <= 5 }
    }
    let first = try ModelChecker(compilation: spec1.compile(), configuration: .init(maximumStateLimit: 100, symmetryReduction: .disabled)).explore()
    let second = try ModelChecker(compilation: spec2.compile(), configuration: .init(maximumStateLimit: 100, symmetryReduction: .disabled)).explore()
    #expect(try FormalGraphExporter().export(first).graph == FormalGraphExporter().export(second).graph)
    for exploration in [first, second] {
      #expect(exploration.isComplete)
      #expect(exploration.graph.states.count == 6)
      #expect(exploration.safetyViolations.map { $0.diagnostic?.kind } == [.deadlock])
    }
  }
}
