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
    let graph1 = try ModelChecker(compilation: try spec1.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    let graph2 = try ModelChecker(compilation: try spec2.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph1.states.count == graph2.states.count)
    #expect(graph1.states.count == 6)
    let result1 = try ModelChecker(compilation: try spec1.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    let result2 = try ModelChecker(compilation: try spec2.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    if case .ok(let c1) = result1, case .ok(let c2) = result2 {
      #expect(c1 == c2)
    } else {
      #expect(Bool(false), "Invariants should hold in both specs")
    }
  }
}
