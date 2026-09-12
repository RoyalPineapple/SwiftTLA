@testable import SwiftTLA
import Testing

@Suite("Scoped substitution")
struct ScopedSubstitutionTests {
    @Test("Substitution preserves malformed signatures for diagnostics")
    func malformedSignaturesRemainInvalid() {
        let body = StateExpr.add(.variable("number"), .variable("Base"))
        let values: [String: StateExpr] = ["Base": .variable("number")]
        let definition = FormalOperatorDefinition(name: "Invalid", parameters: [.value("number"), .value("number")], body: body)
        #expect(definition.substitutingVariables(values) == definition)
        let recursive = RecursiveFunc(name: "Invalid", params: ["number", "number"], body: body)
        #expect(recursive.substitutingVariables(values) == recursive)
        let lambda = FormalLambda(parameters: ["number", "number"], body: body)
        let expression = StateExpr.operatorApplication(.lambda(lambda), [.value(.value(.int(1))), .value(.value(.int(2)))])
        #expect(StateExpr.renamingRecursiveCalls(in: expression, using: { $0 }, lowerAnonymousLambdaApplications: true) == expression)
        guard case .operatorApplication(.lambda(let substituted), _) = StateExpr.substituteVariables(values, in: expression) else {
            Issue.record("Expected the invalid lambda to remain available to validation")
            return
        }
        #expect(substituted.sourceIssue != nil)
        #expect(substituted.parameters == lambda.parameters)
    }

    @Test("Function specialization preserves parameter scope and declaration metadata")
    func functionSpecializationPreservesScope() {
        let body = StateExpr.add(.variable("number"), .variable("Base"))
        let values: [String: StateExpr] = ["number": .value(.int(99)), "Base": .variable("number")]
        let recursive = RecursiveFunc(name: "AddBase", params: ["number"], body: body).substitutingVariables(values)
        let definition = FormalOperatorDefinition(name: "AddBase", parameters: [.value("number")], body: body,
            plusCalPhase: .define, plusCalDependencies: ["Base"]).substitutingVariables(values)
        #expect(recursive.params == ["number_1"])
        #expect(definition.parameters == [.value("number_1")])
        #expect(recursive.body == .add(.variable("number_1"), .variable("number")))
        #expect(definition.body == recursive.body)
        #expect(definition.plusCalPhase == .define)
        #expect(definition.plusCalDependencies == ["Base"])
    }

    @Test("Action substitution preserves caller references under existential and local binders")
    func actionSubstitutionAvoidsCapture() {
        let body = ActionExpr.guard_(.equal(.variable("first"), .variable("second")))
        let replacements: [String: StateExpr] = ["first": .variable("second"), "second": .value(.int(7))]
        let expectedBody = ActionExpr.guard_(.equal(.variable("second"), .variable("second_1")))
        let existential = ActionExpr.existsAction("second", .variable("second"), body)
        let local = ActionExpr.define("second", .variable("second"), body)
        #expect(existential.substitutingVariables(replacements) == .existsAction("second_1", .value(.int(7)), expectedBody))
        #expect(local.substitutingVariables(replacements) == .define("second_1", .value(.int(7)), expectedBody))
        #expect(body.substitutingVariables(replacements) == .guard_(.equal(.variable("second"), .value(.int(7)))))
    }

    @Test("Simultaneous substitution respects shadowing and avoids capturing inserted arguments")
    func simultaneousSubstitutionPreservesScope() {
        let expression = StateExpr.forAll(.variable("domain"), "second",
            .equal(.variable("first"), .variable("second")))
        let result = StateExpr.substituteVariables([
            "domain": .setLiteral([.value(.int(1))]),
            "first": .variable("second"),
            "second": .value(.int(7))
        ], in: expression)
        #expect(result == .forAll(.setLiteral([.value(.int(1))]), "second_1",
            .equal(.variable("second"), .variable("second_1"))))
    }

    @Test("Anonymous lambda arguments are substituted simultaneously")
    func lambdaArgumentsPreserveCallerBindings() {
        let lambda = FormalLambda(parameters: ["first", "second"], body: .subtract(.variable("first"), .variable("second")))
        let expression = StateExpr.operatorApplication(.lambda(lambda), [
            .value(.variable("second")), .value(.value(.int(7)))
        ])
        let lowered = StateExpr.renamingRecursiveCalls(in: expression, using: { $0 }, lowerAnonymousLambdaApplications: true)
        #expect(lowered == .subtract(.variable("second"), .value(.int(7))))
    }

    @Test("Statement macro arguments cannot rewrite earlier caller arguments")
    func macroArgumentsPreserveCallerBindings() {
        let compare = Macro { (first: MacroParameter<Int>, second: MacroParameter<Int>) in
            Assert(first != second)
        }
        let argument = Expr<Int>(.variable("__pcal_macro_parameter_1"))
        enum Label: String, CaseIterable, Sendable { case check }
        let algorithm = Algorithm("ArgumentScope") {
            Do(Label.check) { compare(argument, Expr<Int>(7)) }
        }
        guard case .step(let step) = algorithm.model.components.first else {
            Issue.record("Expected the expanded atomic step")
            return
        }
        #expect(step.statements == [
            .assert(.notEqual(.variable("__pcal_macro_parameter_1"), .value(.int(7))))
        ])
    }

  @Test("Action parameters do not replace a shadowing existential")
  func actionParameterRespectsExistentialScope() {
    let action: ActionExpr = .existsAction(
      "id",
      .setLiteral([.value(.int(1))]),
      .guard_(.equal(.variable("id"), .variable("outer")))
    )

    let substitutedAction = action.substitutingVariable("id", with: .value(.int(99)))

    #expect(substitutedAction == action)
  }

  @Test("State substitution does not enter a shadowing quantifier")
  func stateParameterRespectsQuantifierScope() {
    let expression: StateExpr = .forAll(
      .setLiteral([.value(.int(1))]),
      "id",
      .equal(.variable("id"), .variable("outer"))
    )

    let substitutedExpression = StateExpr.substituteVariable("id", .int(99), in: expression)

    #expect(substitutedExpression == expression)
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

    let substitutedExpression = StateExpr.substituteVariable("target", with: .variable("member"), in: expression)

    #expect(substitutedExpression == .forAll(
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

    let substitutedExpression = StateExpr.substituteVariable("item", with: .int(99), in: expression)

    #expect(substitutedExpression == expression)
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

    let substitutedExpression = StateExpr.substituteVariable("target", with: .variable("element"), in: expression)

    let expected: StateExpr = .foldFunction(
      FormalLambda(
        parameters: ["element_1", "accumulator"],
        body: .add(.variable("element"), .variable("element_1"))
      ),
      initial: .int(0),
      sequence: .tupleLiteral([.int(1)])
    )
    #expect(substitutedExpression == expected)
  }

  @Test("Local operator parameters are scoped independently")
  func substitutionAvoidsLocalOperatorCapture() {
    let expression: StateExpr = .letIn(
      [LocalOperator("keep", parameters: ["item"], body: .variable("target"))],
      .recursiveCall("keep", [.value(.int(0))])
    )

    let substitutedExpression = StateExpr.substituteVariable("target", with: .variable("item"), in: expression)

    #expect(substitutedExpression == .letIn(
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


    #expect(try compiledValue(exists.raw) == .bool(true))
    #expect(try compiledValue(all.raw) == .bool(true))
  }
}
