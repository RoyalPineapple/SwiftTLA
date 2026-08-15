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

  @Test("formal value parameters shadow state variables")
  func formalParametersAreLexicallyScoped() throws {
    let identity = FormalOperatorDefinition(
      name: "identity",
      parameters: [.value("value")],
      body: .variable("value")
    )
    let expression = StateExpr.operatorApplication(
      .reference("identity", arity: 1),
      [.value(.int(4))]
    )

    #expect(
      try expression.evaluate(
        in: ["value": .int(99)],
        formalOperatorDefinitions: [identity]
    ) == .int(4)
    )
  }

  @Test("model checking and runtime apply a spec-owned formal operator")
  func appliesFormalOperatorAtTheTransitionBoundary() throws {
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
    let spec = TLASpec(
      name: "FormalTransition",
      variables: [NamedVar(name: "counter", initial: .int(0))],
      actions: [NamedAction(
        name: "advance",
        body: .assign(
          "counter",
          .operatorApplication(
            .reference("applyTwice", arity: 2),
            [.operator(increment), .value(.variable("counter"))]
          )
        )
      )],
      invariants: [NamedInvariant(
        name: "bounded",
        body: .lessOrEqual(.variable("counter"), .int(2))
      )],
      constraint: .lessOrEqual(.variable("counter"), .int(2)),
      formalOperatorDefinitions: [applyTwice]
    )

    let runtime = SpecRuntime(spec: spec)
    let initial = try #require(runtime.initialStates().first)
    #expect(try runtime.apply(.init(name: "advance"), to: initial)["counter"] == .int(2))
    let result = try ModelChecker(spec: spec, maxStates: 10).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("an imported module exports executable formal operators")
  func resolvesImportedFormalOperators() throws {
    let increment = FormalOperator.lambda(FormalLambda(
      parameters: ["value"],
      body: .add(.variable("value"), .int(1))
    ))
    let library = TLASpec(
      name: "FormalLibrary",
      variables: [],
      actions: [],
      invariants: [],
      formalOperatorDefinitions: [FormalOperatorDefinition(
        name: "applyTwice",
        parameters: [.operator("operation", arity: 1), .value("initial")],
        body: .operatorApplication(
          .reference("operation", arity: 1),
          [.value(.operatorApplication(
            .reference("operation", arity: 1),
            [.value(.variable("initial"))]
          ))]
        )
      )]
    )
    let consumer = TLASpec(
      name: "FormalConsumer",
      variables: [NamedVar(name: "counter", initial: .int(0))],
      actions: [NamedAction(
        name: "advance",
        body: .assign(
          "counter",
          .operatorApplication(
            .reference("applyTwice", arity: 2),
            [.operator(increment), .value(.variable("counter"))]
          )
        )
      )],
      invariants: [],
      constraint: .lessOrEqual(.variable("counter"), .int(2)),
      imports: [library]
    )

    let runtime = SpecRuntime(spec: consumer)
    let initial = try #require(runtime.initialStates().first)
    #expect(try runtime.apply(.init(name: "advance"), to: initial)["counter"] == .int(2))
    let result = try ModelChecker(spec: consumer, maxStates: 10).check()
    #expect({ if case .ok = result { true } else { false } }())
  }
}
