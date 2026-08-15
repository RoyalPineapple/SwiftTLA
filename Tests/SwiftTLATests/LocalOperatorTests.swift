import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

@Suite("Local TLA+ operators")
struct LocalOperatorTests {
  @Test("LET operators evaluate recursively and shadow outer operators")
  func evaluatesLocalRecursiveOperator() throws {
    let sumTo = LocalOperator(
      "SumTo",
      parameters: ["number"],
      body: .ifThenElse(
        .equal(.variable("number"), .int(0)),
        .int(0),
        .add(
          .variable("number"),
          .recursiveCall("SumTo", [.subtract(.variable("number"), .int(1))])
        )
      )
    )
    let expression: StateExpr = .letIn([sumTo], .recursiveCall("SumTo", [.int(4)]))

    #expect(try expression.evaluate(in: [:]) == .int(10))
    #expect(expression.description.contains("LET RECURSIVE SumTo(_)"))
    #expect(expression.description.contains("SumTo(number) =="))
  }

  @Test("LET operators are emitted as executable TLA+ source")
  func emitsLetInSource() {
    let local = LocalOperator("AddOne", parameters: ["number"], body: .add(.variable("number"), .int(1)))
    let spec = TLASpec("LocalOperatorSource") {
      Definition("Answer") {
        .letIn([local], .recursiveCall("AddOne", [.int(41)]))
      }
    }

    #expect(spec.tlaModule.contains("Answer == LET AddOne(number) == (number + 1)"))
    #expect(spec.tlaModule.contains("IN AddOne(41)"))
  }

  @Test("the macro parser retains LET operator definitions")
  func parserRetainsLocalOperators() {
    let source = "StateExpr.letIn([LocalOperator(\"Truth\", body: true)], true)"
    let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let parsed = SpecParser.decodeStateExpr(syntax)
    let expected: StateExpr = .letIn(
      [LocalOperator("Truth", body: .bool(true))],
      .bool(true)
    )

    #expect(parsed == expected)
  }

  @Test("local operator calls validate their arity")
  func rejectsWrongArity() {
    let operation = LocalOperator("Only", parameters: ["value"], body: .variable("value"))
    let expression: StateExpr = .letIn([operation], .recursiveCall("Only", []))

    #expect(throws: EvalError.self) {
      try expression.evaluate(in: [:])
    }
  }

  @Test("LET value bindings are lexical, capture-safe, and emitted")
  func evaluatesScopedValueBinding() throws {
    let expression: StateExpr = .letValue(
      "value",
      .int(4),
      .add(.variable("value"), .int(1))
    )
    let substituted = StateExpr.substituteVariable(
      "value",
      .int(99),
      in: expression
    )

    #expect(try expression.evaluate(in: ["value": .int(0)]) == .int(5))
    #expect(try substituted.evaluate(in: ["value": .int(0)]) == .int(5))
    #expect(expression.description == "LET value == 4 IN (value + 1)")
    #expect(expression.swiftSource.contains("StateExpr.letValue(\"value\", 4,"))
  }
}
