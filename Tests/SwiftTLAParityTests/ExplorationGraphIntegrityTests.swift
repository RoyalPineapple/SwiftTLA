import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ExplorationGraphIntegrityTests {
  @Test("Exploration rejects non-positive resource limits")
  func rejectsNonPositiveResourceLimits() {
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(0)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: 0,
        symmetryReduction: .disabled)
    }
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(-1)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: -1,
        symmetryReduction: .disabled)
    }
    #expect(throws: FiniteExplorationConfigurationError.nonPositivePermutationLimit(0)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: 1,
        symmetryReduction: .enabled(maximumPermutationCount: 0))
    }
  }

  @Test("All explored states are reachable from initial")
  func reachability() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 4) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 5)  // 0,1,2,3,4
    let values = try Set(graph.states.values.map { try #require(try value("x", in: $0)) })
    #expect(values == Set([.int(0), .int(1), .int(2), .int(3), .int(4)]))
  }

  @Test("No transition targets unknown states")
  func noDanglingTransitions() throws {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    let spec = TLASpec("Test") {
      Variable(a, 0)
      Variable(b, 0)
      Action("incA") { a.becomes(a + 1).when(a < 3) }
      Action("incB") { b.becomes(b + 1).when(b < 3) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    for (_, ts) in graph.transitions {
      for t in ts {
        #expect(graph.states[t.target] != nil)
      }
    }
  }

  @Test("States <= maxStates + 1 (stops after processing)")
  func maxStatesBound() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1) }
    }
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5, symmetryReduction: .disabled)).exploreGraph()
    // maxStates limits processed, last state may discover one extra
    #expect(g.states.count <= 5 + 1)
  }

  @Test("Invariant checked on all states")
  func invariantChecked() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("nonNeg") { x >= 0 }
    }
    if case .ok(let c) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check() {
      #expect(c == 6)
    } else {
      #expect(Bool(false))
    }
  }
}
