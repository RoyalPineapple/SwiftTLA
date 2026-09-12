import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct EdgeCaseTests {
  @Test("3-level nested OR in AND")
  func nestedOrL3() throws {
    let a: ActionExpr = .and(
      .assign(.named("x"), .value(.int(1))),
      .or(
        .or(.assign(.named("y"), .value(.int(2))), .assign(.named("y"), .value(.int(3)))),
        .assign(.named("y"), .value(.int(4))))
    )
    let (_, successors) = try compiledSuccessors(
      for: a,
      from: [("x", .int(0)), ("y", .int(0)), ("z", .int(0))]
    )
    #expect(successors.count == 3)
  }

  @Test("Deadlock when guard fails at init")
  func deadlockAtInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(2).when(x == 1) }
      DeadlockCheck()
    }
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    var dead = false
    if case .deadlocked = checkOutcome { dead = true } else { dead = false }
    #expect(dead)
  }

  @Test("Deadlock at terminal linear state")
  func deadlockTerminal() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(x + 1).when(x < 2) }
      DeadlockCheck()
    }
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    let xToken = try #require(TLAStateProjection.Token(validating: "x"))
    var val: TLAValue = .int(-1)
    if case .deadlocked(let state) = checkOutcome { val = state.value(for: xToken) ?? .int(-1) }
    #expect(val == .int(2))
  }

  @Test("No deadlock on cyclic spec")
  func noDeadlockCyclic() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes((x + 1) % 2) }
      DeadlockCheck()
    }
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    var ok = false
    if case .ok = checkOutcome { ok = true }
    #expect(ok)
  }

  @Test("maxStates=1 bounds state count")
  func maxStatesOne() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(x + 1) }
    }
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1, symmetryReduction: .disabled)).exploreGraph()
    #expect(g.states.count <= 2)
  }
}
