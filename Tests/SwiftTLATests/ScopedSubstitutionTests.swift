import SwiftTLA
import Testing

@Suite("Scoped substitution")
struct ScopedSubstitutionTests {
  @Test("Action parameters do not replace a shadowing existential")
  func actionParameterRespectsExistentialScope() {
    let action: ActionExpr = .existsAction(
      "id",
      .setLiteral([.value(.int(1))]),
      .guard_(.equal(.variable("id"), .variable("outer")))
    )

    let result = action.substitutingVariable("id", with: .value(.int(99)))

    #expect(result == action)
  }

  @Test("State substitution does not enter a shadowing quantifier")
  func stateParameterRespectsQuantifierScope() {
    let expression: StateExpr = .forAll(
      .setLiteral([.value(.int(1))]),
      "id",
      .equal(.variable("id"), .variable("outer"))
    )

    let result = StateExpr.substituteVariable("id", .int(99), in: expression)

    #expect(result == expression)
  }

  @Test("Substitution still reaches free references beside a binder")
  func substitutionRetainsFreeReferences() {
    let action: ActionExpr = .and(
      .guard_(.equal(.variable("id"), .value(.int(7)))),
      .existsAction("id", .setLiteral([.value(.int(1))]), .guard_(.variable("id")))
    )

    let expected: ActionExpr = .and(
      .guard_(.equal(.value(.int(7)), .value(.int(7)))),
      .existsAction("id", .setLiteral([.value(.int(1))]), .guard_(.variable("id")))
    )

    #expect(action.substitutingVariable("id", with: .value(.int(7))) == expected)
  }

  @Test("Substitution renames a quantifier binder before a free replacement can capture it")
  func substitutionAvoidsQuantifierCapture() {
    let expression: StateExpr = .forAll(
      .setLiteral([.value(.int(1))]),
      "member",
      .equal(.variable("target"), .variable("member"))
    )

    let result = StateExpr.substituteVariable("target", with: .variable("member"), in: expression)

    #expect(result == .forAll(
      .setLiteral([.value(.int(1))]),
      "member_1",
      .equal(.variable("member"), .variable("member_1"))
    ))
  }

  @Test("Substitution respects the binding side of a set comprehension")
  func substitutionRespectsSetMapScope() {
    let expression: StateExpr = .setMap(
      .add(.variable("item"), .variable("offset")),
      "item",
      .setLiteral([.value(.int(1))])
    )

    let result = StateExpr.substituteVariable("item", with: .int(99), in: expression)

    #expect(result == expression)
  }

  @Test("Formal lambda parameters are renamed before substitution")
  func substitutionAvoidsFormalLambdaCapture() {
    let expression: StateExpr = .foldFunction(
      FormalLambda(
        parameters: ["element", "accumulator"],
        body: .add(.variable("target"), .variable("element"))
      ),
      initial: .int(0),
      sequence: .tupleLiteral([.int(1)])
    )

    let result = StateExpr.substituteVariable("target", with: .variable("element"), in: expression)

    #expect(result == .foldFunction(
      FormalLambda(
        parameters: ["element_1", "accumulator"],
        body: .add(.variable("element"), .variable("element_1"))
      ),
      initial: .int(0),
      sequence: .tupleLiteral([.int(1)])
    ))
  }

  @Test("Local operator parameters are scoped independently")
  func substitutionAvoidsLocalOperatorCapture() {
    let expression: StateExpr = .letIn(
      [LocalOperator("keep", parameters: ["item"], body: .variable("target"))],
      .recursiveCall("keep", [.value(.int(0))])
    )

    let result = StateExpr.substituteVariable("target", with: .variable("item"), in: expression)

    #expect(result == .letIn(
      [LocalOperator("keep", parameters: ["item_1"], body: .variable("item"))],
      .recursiveCall("keep", [.value(.int(0))])
    ))
  }

  @Test("two-value quantifiers lower to independently scoped binders")
  func evaluatesMultiBindingQuantifiers() throws {
    let values = SetExpr<Int>.literal(1, 2)
    let exists = Exists(in: values, and: values) { left, right in
      left.expr + right.expr == 3
    }
    let all = ForAll(in: values, and: values) { left, right in
      left.expr <= 2 && right.expr <= 2
    }
    let condition = All(in: values, and: values) { left, right in
      left.expr + right.expr <= 4
    }

    #expect(try compiledValue(exists.raw) == .bool(true))
    #expect(try compiledValue(all.raw) == .bool(true))
    #expect(try compiledValue(condition) == .bool(true))
  }
}
