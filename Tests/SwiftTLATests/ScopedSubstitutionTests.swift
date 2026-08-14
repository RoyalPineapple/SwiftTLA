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

    let result = substituteVar("id", with: .int(99), in: action)

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

    #expect(substituteVar("id", with: .int(7), in: action) == expected)
  }
}
