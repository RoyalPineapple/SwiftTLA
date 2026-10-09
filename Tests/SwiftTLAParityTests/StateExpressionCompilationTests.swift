@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct StateExpressionCompilationTests {
  @Test("compiled rendering accepts every state expression case")
  func compiledRenderingAcceptsEveryStateExpressionCase() throws {
    let cases: [StateExpr] = [
      .value(.int(1)), .value(.bool(true)), .value(.string("x")),
      .variable("v"),
      .add(.int(1), .int(1)), .subtract(.int(1), .int(1)),
      .multiply(.int(1), .int(1)), .divide(.int(1), .int(1)),
      .modulo(.int(1), .int(1)), .negate(.int(1)),
      .integerDivide(.int(4), .int(2)),
      .equal(.int(1), .int(1)), .notEqual(.int(1), .int(2)),
      .lessThan(.int(1), .int(2)), .lessOrEqual(.int(1), .int(2)),
      .greaterThan(.int(2), .int(1)), .greaterOrEqual(.int(2), .int(1)),
      .and(.bool(true), .bool(true)), .or(.bool(true), .bool(true)),
      .not(.bool(true)),
      .ifThenElse(.bool(true), .int(1), .int(2)),
      .setLiteral([.int(1)]), .in(.int(1), .setLiteral([.int(1)])),
      .subset(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .union(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .intersection(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .setDifference(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .cardinality(.setLiteral([.int(1)])),
      .setFilter(.setLiteral([.int(1)]), "x0", .bool(true)),
      .setMap(.variable("x"), "x0", .setLiteral([.int(1)])),
      .powerSet(.setLiteral([.int(1)])),
      .unionAll(.setLiteral([.setLiteral([.int(1)])])),
      .tupleLiteral([.int(1)]), .tupleAccess(.tupleLiteral([.int(1)]), 0),
      .tupleLength(.tupleLiteral([.int(1)])),
      .tupleAppend(.tupleLiteral([.int(1)]), .int(2)),
      .tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)])),
      StateExpr.record(["k": .int(1)]), .recordAccess(StateExpr.record(["k": .int(1)]), "k"),
      .domain(StateExpr.record(["k": .int(1)])),
      .functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")),
      .functionApply(.functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")), .int(1)),
      .except(.functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")), .int(1), .int(2)),
      .caseExpr([.bool(true), .int(1)], .int(0)),
      .forAll(.setLiteral([.int(1)]), "x0", .bool(true)),
      .exists(.setLiteral([.int(1)]), "x0", .bool(true)),
      .choose(.setLiteral([.int(1)]), "x0", .bool(true)),
      .enabledAction("Foo")
    ]
    let spec = TLASpec(
      name: "StateExpressionCases",
      variables: [NamedVar(name: "v", initial: .int(0)), NamedVar(name: "x", initial: .int(0))],
      actions: [NamedAction(name: "Foo", body: .guard_(.bool(true)))],
      invariants: cases.enumerated().map { .init(name: "Case\($0.offset)", body: $0.element) }
    )
    #expect(try spec.compile().semantics.behavior.invariants.count == cases.count)
  }

  @Test("StateExpr evaluates correctly in state")
  func evaluatesInState() throws {
    let e: StateExpr = .add(.variable("x"), .int(1))
    let v = try compiledValue(e, values: [("x", .int(5))])
    #expect(v == .int(6))
  }
}
