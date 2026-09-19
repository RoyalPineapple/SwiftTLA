@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct VariableOperatorTests {
  @Test(
    "Arithmetic",
    arguments: [
      ("+", 3, "(x + 3)"),
      ("-", 1, "(x - 1)"),
      ("*", 2, "(x * 2)"),
      ("%", 5, "(x % 5)")
    ])
  func arithmetic(_ op: String, _ val: Int, _ expected: String) throws {
    let x = Var<Int>("x")
    let expression: StateExpr
    switch op {
    case "+": expression = (x + val).raw
    case "-": expression = (x - val).raw
    case "*": expression = (x * val).raw
    case "%": expression = (x % val).raw
    default: expression = .int(0)
    }
    #expect(try renderedStateExpression(expression).contains("Rendered == \(expected)"))
  }

  @Test(
    "Comparison matrix",
    arguments: [
      ("==", 0, "(x = 0)"),
      ("==", 1, "(x = 1)"),
      ("!=", 0, "(x /= 0)"),
      ("<", 5, "(x < 5)"),
      ("<=", 5, "(x <= 5)"),
      (">", 0, "(x > 0)"),
      (">=", 1, "(x >= 1)")
    ])
  func comparison(_ op: String, _ val: Int, _ expected: String) throws {
    let x = Var<Int>("x")
    let expression: Expr<Bool>
    switch op {
    case "==": expression = x == val
    case "\u{21}=": expression = x != val
    case "<": expression = x < val
    case "<=": expression = x <= val
    case ">": expression = x > val
    case ">=": expression = x >= val
    default: expression = false
    }
    #expect(try renderedStateExpression(expression.raw).contains("Rendered == \(expected)"))
  }

  @Test(
    "Compiled action variants",
    arguments: [
      ("simpleAssign", 1),
      ("guardTrue", 1),
      ("guardFalse", 0),
      ("orBranches", 2),
      ("twoVars", 1)
    ] as [(String, Int)])
  func actionMatrix(_ variant: String, _ expected: Int) throws {
    let s: [(String, TLAValue)] = [("x", .int(0)), ("y", .int(0))]
    let action: ActionExpr
    switch variant {
    case "simpleAssign": action = .assign(.named("x"), .value(.int(42)))
    case "guardTrue":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(0)))), .assign(.named("x"), .value(.int(1))))
    case "guardFalse":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(1)))), .assign(.named("x"), .value(.int(2))))
    case "orBranches": action = .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2))))
    case "twoVars": action = .and(.assign(.named("x"), .value(.int(1))), .assign(.named("y"), .value(.int(2))))
    default: action = .assign(.named("x"), .value(.int(0)))
    }
    let r = try compiledActionProjections(action, from: s, variables: ["x", "y"])
    #expect(r.count == expected)
  }

  @Test("Compiled action execution accepts wide lowered simultaneous updates")
  func wideAssignmentsPreserveOneCommitment() throws {
    let depth = 256
    let assignment = ActionExpr.assign(.named("x"), .value(.int(1)))
    let action = (0..<depth).reduce(assignment) { partial, _ in
      .and(partial, assignment)
    }

    let successors = try compiledActionProjections(
      action,
      from: [("x", .int(0))],
      variables: ["x"]
    )
    let x = try #require(TLAStateProjection.Token(validating: "x"))
    #expect(successors.count == 1)
    #expect(successors.first?.value(for: x) == .int(1))
  }

  @Test(
    "StateExpr cases",
    arguments: [
      ("valueInt", "42"),
      ("valueBool", "TRUE"),
      ("valueString", "\"hi\""),
      ("variable", "x"),
      ("add", "(1 + 2)"),
      ("subtract", "(5 - 3)"),
      ("multiply", "(2 * 3)"),
      ("modulo", "(7 % 3)"),
      ("negate", "(-1)"),
      ("equal", "(1 = 1)"),
      ("notEqual", "(1 /= 2)"),
      ("lessThan", "(1 < 2)"),
      ("greaterThan", "(2 > 1)"),
      ("setLiteral", "{1, 2}"),
      ("inSet", "(1 \\in {1, 2})"),
      ("tupleLiteral", "<<1, 2>>"),
      ("ifThen", "(IF TRUE THEN 1 ELSE 2)"),
      ("enabled", "ENABLED Tick")
    ] as [(String, String)])
  func stateExprMatrix(_ caseName: String, _ expected: String) throws {
    let e: StateExpr
    switch caseName {
    case "valueInt": e = .value(.int(42))
    case "valueBool": e = .value(.bool(true))
    case "valueString": e = .value(.string("hi"))
    case "variable": e = .variable("x")
    case "add": e = .add(.int(1), .int(2))
    case "subtract": e = .subtract(.int(5), .int(3))
    case "multiply": e = .multiply(.int(2), .int(3))
    case "modulo": e = .modulo(.int(7), .int(3))
    case "negate": e = .negate(.int(1))
    case "equal": e = .equal(.int(1), .int(1))
    case "notEqual": e = .notEqual(.int(1), .int(2))
    case "lessThan": e = .lessThan(.int(1), .int(2))
    case "greaterThan": e = .greaterThan(.int(2), .int(1))
    case "setLiteral": e = .setLiteral([.int(1), .int(2)])
    case "inSet": e = .in(.int(1), .setLiteral([.int(1), .int(2)]))
    case "tupleLiteral": e = .tupleLiteral([.int(1), .int(2)])
    case "ifThen": e = .ifThenElse(.bool(true), .int(1), .int(2))
    case "enabled": e = .enabledAction("Tick")
    default: e = .value(.int(0))
    }
    #expect(try renderedStateExpression(e).contains("Rendered == \(expected)"))
  }

  @Test func varVsVar() throws {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    #expect(try renderedStateExpression((a == b).raw).contains("Rendered == (a = b)"))
    #expect(try renderedStateExpression(.notEqual(a.stateExpr, b.stateExpr)).contains("Rendered == (a /= b)"))
    #expect(try renderedStateExpression((a < b).raw).contains("Rendered == (a < b)"))
  }

  @Test func prefix() throws {
    let x = Var<Int>("x")
    #expect(try renderedStateExpression(.negate(x.stateExpr)).contains("Rendered == (-x)"))
  }

  @Test func stringComparison() throws {
    let s = Var<String>("s")
    #expect(try renderedStateExpression((s == "right").raw).contains("Rendered == (s = \"right\")"))
  }

  @Test func assignmentAndWhen() throws {
    let x = Var<Int>("x")
    let a = x.becomes(1)
    #expect(try renderedActionExpression(a).contains("x' = 1"))
    let g = x.becomes(1).when(x == 0)
    let guarded = try renderedActionExpression(g)
    #expect(guarded.contains("(x = 0)") && guarded.contains("x' = 1"))
    let s = x.stays
    #expect(try renderedActionExpression(s).contains("UNCHANGED x"))
  }
}
