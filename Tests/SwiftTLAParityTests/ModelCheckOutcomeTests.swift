import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct ModelCheckOutcomeTests {
  private func checker(_ specification: TLASpec) throws -> ModelChecker {
    try ModelChecker(
      compilation: specification.compile(),
      configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
    )
  }

  @Test("an empty initial-state relation has a typed outcome")
  func emptyInitialStateRelation() throws {
    let value = Var<Int>("value")
    let outcome = try checker(TLASpec("EmptyInitialStateRelation") {
      Variable(value, in: [Int]())
    }).check()

    guard case .noInitialStates = outcome else {
      Issue.record("Expected noInitialStates, received \(outcome)")
      return
    }
    #expect(outcome.diagnostic?.kind == .initialState)
  }

  @Test("a false compiled assumption has a typed outcome")
  func falseCompiledAssumption() throws {
    let value = Var<Int>("value")
    let outcome = try checker(TLASpec("FalseCompiledAssumption") {
      Assume(false)
      Variable(value, 0)
    }).check()

    guard case .assumptionViolated = outcome else {
      Issue.record("Expected assumptionViolated, received \(outcome)")
      return
    }
    #expect(outcome.diagnostic?.kind == .assumption)
  }
}
