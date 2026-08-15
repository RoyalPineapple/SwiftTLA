import SwiftTLA
import Testing

@Suite("Formal operators")
struct FormalOperatorTests {
  @Test("a formal lambda is applied by the evaluator, not by Swift")
  func appliesFormalLambda() throws {
    let expression = StateExpr.operatorApplication(
      .lambda(FormalLambda(
        parameters: ["left", "right"],
        body: .add(.variable("left"), .variable("right"))
      )),
      [.value(.int(2)), .value(.int(3))]
    )

    #expect(try expression.evaluate(in: [:]) == .int(5))
  }

  @Test("a formal reference resolves through the formal operator environment")
  func appliesNamedFormalOperator() throws {
    let expression = StateExpr.operatorApplication(
      .reference("increment", arity: 1),
      [.value(.int(4))]
    )
    let increment = RecursiveFunc(
      name: "increment",
      params: ["value"],
      body: .add(.variable("value"), .int(1))
    )

    #expect(try expression.evaluate(in: [:], recursiveFuncs: [increment]) == .int(5))
  }

  @Test("a formal definition receives an operator as formal data")
  func appliesHigherOrderFormalDefinition() throws {
    let applyTwice = FormalOperatorDefinition(
      name: "applyTwice",
      parameters: [.operator("operation", arity: 1), .value("initial")],
      body: .operatorApplication(
        .reference("operation", arity: 1),
        [.value(.operatorApplication(
          .reference("operation", arity: 1),
          [.value(.variable("initial"))]
        ))]
      )
    )
    let increment = FormalOperator.lambda(FormalLambda(
      parameters: ["value"],
      body: .add(.variable("value"), .int(1))
    ))
    let expression = StateExpr.operatorApplication(
      .reference("applyTwice", arity: 2),
      [.operator(increment), .value(.int(4))]
    )

    #expect(
      try expression.evaluate(in: [:], formalOperatorDefinitions: [applyTwice]) == .int(6)
    )
  }
}
