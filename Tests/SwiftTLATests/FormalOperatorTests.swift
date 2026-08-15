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
      [.int(2), .int(3)]
    )

    #expect(try expression.evaluate(in: [:]) == .int(5))
  }

  @Test("a formal reference resolves through the formal operator environment")
  func appliesNamedFormalOperator() throws {
    let expression = StateExpr.operatorApplication(
      .reference("increment", arity: 1),
      [.int(4)]
    )
    let increment = RecursiveFunc(
      name: "increment",
      params: ["value"],
      body: .add(.variable("value"), .int(1))
    )

    #expect(try expression.evaluate(in: [:], recursiveFuncs: [increment]) == .int(5))
  }
}
