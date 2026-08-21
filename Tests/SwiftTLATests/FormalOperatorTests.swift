@testable import SwiftTLA
import SwiftTLAMacros
import Testing

@TLAModel
private struct GeneratedHigherOrderFormalModel {
  static var spec: TLASpec {
    #spec("GeneratedHigherOrderFormalModel") {
      FormalDefinition(
        "applyTwice",
        parameters: [.operator("operation", arity: 1), .value("initial")],
        body: StateExpr.operatorApplication(
          .reference("operation", arity: 1),
          [.value(StateExpr.operatorApplication(
            .reference("operation", arity: 1),
            [.value(StateExpr.variable("initial"))]
          ))]
        )
      )
      Algorithm("GeneratedHigherOrderFormalModel") {
        let counter = SharedVar("counter", initial: 0)
        Do(TestControlLabel.advance) {
          Assign(counter, to: counter.expr + 1)
        }
      }
    }
  }
}

@Suite("Formal operators")
struct FormalOperatorTests {
  @Test("a nullary formal operator uses standard TLA+ syntax")
  func rendersNullaryFormalOperatorWithoutParentheses() throws {
    let initialState = FormalOperatorDefinition(
      name: "InitialState",
      parameters: [],
      body: .int(0)
    )
    let spec = TLASpec(
      name: "NullaryFormal",
      variables: [],
      actions: [],
      invariants: [],
      formalOperatorDefinitions: [initialState]
    )

    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("InitialState == 0"))
    #expect(
      StateExpr.operatorApplication(.reference("InitialState", arity: 0), []).description
        == "InitialState"
    )
  }

  @Test("a #spec higher-order formal definition preserves parser and builder trees")
  func generatedHigherOrderFormalDefinitionPreservesParserFidelity() throws {
    GeneratedHigherOrderFormalModel._checkParserTree()

    var model = try GeneratedHigherOrderFormalModel.makeMachine()
    let result = try model.apply(.advance)
    #expect(result.after.counter == 1)
  }

  @Test("a formal lambda is applied by the evaluator, not by Swift")
  func appliesFormalLambda() throws {
    let expression = StateExpr.operatorApplication(
      .lambda(FormalLambda(
        parameters: ["left", "right"],
        body: .add(.variable("left"), .variable("right"))
      )),
      [.value(.int(2)), .value(.int(3))]
    )

    #expect(try compiledValue(expression) == .int(5))
  }

  @Test("a formal lambda application renders through local bindings")
  func rendersFormalLambdaApplicationThroughLocalBindings() throws {
    let lambda = FormalOperator.lambda(.init(
      parameters: ["value"],
      body: .add(.variable("value"), .int(1))
    ))
    let spec = TLASpec(
      name: "LambdaApplication",
      variables: [.init(name: "counter", initial: .int(0))],
      actions: [.init(
        name: "advance",
        body: .assign(.named("counter"), .operatorApplication(lambda, [.value(.variable("counter"))]))
      )],
      invariants: []
    )

    let rendered = try spec.compile().renderedTLAModuleBundle().root.tla

    #expect(rendered.contains("LET "))
    #expect(rendered.contains("(LAMBDA") == false)
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

    #expect(try compiledValue(expression, recursiveFunctions: [increment]) == .int(5))
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
      try compiledValue(expression, formalOperators: [applyTwice]) == .int(6)
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
      try compiledValue(expression, values: [("value", .int(99))], formalOperators: [identity]) == .int(4)
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
          .named("counter"),
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

    let compilation = try spec.compile()
    let action = try #require(compilation.layout.actionID(named: "advance"))
    let initial = try #require(try compilation.initialStateProjections().first)
    let successor = try #require(try compilation.successors(for: action, arguments: [], from: initial).first)
    let token = try #require(TLAStateProjection.Token(validating: "counter"))
    #expect(successor.value(for: token) == .int(2))
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).check()
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
          .named("counter"),
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

    let compilation = try consumer.compile()
    let action = try #require(compilation.layout.actionID(named: "advance"))
    let initial = try #require(try compilation.initialStateProjections().first)
    let successor = try #require(try compilation.successors(for: action, arguments: [], from: initial).first)
    let token = try #require(TLAStateProjection.Token(validating: "counter"))
    #expect(successor.value(for: token) == .int(2))
    let result = try ModelChecker(compilation: try consumer.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("Folds is executable after import, not only emitted source")
  func executesImportedMapThenFoldSet() throws {
    let add = FormalOperator.lambda(FormalLambda(
      parameters: ["left", "right"],
      body: .add(.variable("left"), .variable("right"))
    ))
    let chooseMember = FormalOperator.lambda(FormalLambda(
      parameters: ["members"],
      body: .choose(.variable("members"), "member", .bool(true))
    ))
    let expression = StateExpr.operatorApplication(
      .reference("MapThenFoldSet", arity: 5),
      [
        .operator(add),
        .value(.int(0)),
        .operator(.lambda(FormalLambda(parameters: ["value"], body: .variable("value")))),
        .operator(chooseMember),
        .value(.setLiteral([.int(1), .int(2), .int(3)]))
      ]
    )

    #expect(
      try compiledValue(
        expression,
        formalOperators: try Folds.module.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
      ) == .int(6)
    )
    #expect(try Folds.module.compile().renderedTLAModuleBundle().tla.contains("MapThenFoldSet(op(_, _), base, f(_), choose(_), S) =="))
  }

  @Test("Functions definitions execute through the imported formal environment")
  func executesFunctionsModuleDefinitions() throws {
    let function: StateExpr = .functionLiteral(
      .setLiteral([.int(1), .int(2), .int(3)]),
      "key",
      .multiply(.variable("key"), .int(10))
    )
    let restrict = StateExpr.operatorApplication(
      .reference("Restrict", arity: 2),
      [.value(function), .value(.setLiteral([.int(1), .int(3)]))]
    )
    let range = StateExpr.operatorApplication(
      .reference("Range", arity: 1), [.value(function)]
    )
    let pointwise = StateExpr.operatorApplication(
      .reference("Pointwise", arity: 3), [
        .value(function),
        .value(.functionLiteral(
          .setLiteral([.int(1), .int(2), .int(3)]),
          "key",
          .variable("key")
        )),
        .operator(.lambda(.init(
          parameters: ["left", "right"],
          body: .add(.variable("left"), .variable("right"))
        )))
      ]
    )

    let functions = try FunctionsModule.module.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
    #expect(try compiledValue(restrict, formalOperators: functions) == .function([
      .int(1): .int(10), .int(3): .int(30)
    ]))
    #expect(try compiledValue(range, formalOperators: functions) == .set([
      .int(10), .int(20), .int(30)
    ]))
    #expect(try compiledValue(pointwise, formalOperators: functions) == .function([
      .int(1): .int(11), .int(2): .int(22), .int(3): .int(33)
    ]))
    #expect(try FunctionsModule.module.compile().renderedTLAModuleBundle().tla.contains("Restrict(f, S) =="))
  }

  @Test("Util definitions execute without flattening their Functions dependency")
  func executesUtilModuleDefinitions() throws {
    let add = FormalOperator.lambda(.init(
      parameters: ["left", "right"],
      body: .add(.variable("left"), .variable("right"))
    ))
    let reduced = StateExpr.operatorApplication(
      .reference("ReduceSet", arity: 3), [
        .operator(add),
        .value(.setLiteral([.int(1), .int(2), .int(3)])),
        .value(.int(0))
      ]
    )
    let index = StateExpr.operatorApplication(
      .reference("Index", arity: 2), [
        .value(.tupleLiteral([.value(.string("a")), .value(.string("b"))])),
        .value(.value(.string("b")))
      ]
    )
    let sequenceSet = StateExpr.operatorApplication(
      .reference("SeqToSet", arity: 1), [
        .value(.tupleLiteral([.int(2), .int(1), .int(2)]))
      ]
    )
    let permutations = StateExpr.operatorApplication(
      .reference("PermSeqs", arity: 1), [
        .value(.setLiteral([.int(1), .int(2)]))
      ]
    )

    let util = try KeyValueStoreUtil.module.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
    #expect(try compiledValue(reduced, formalOperators: util) == .int(6))
    #expect(try compiledValue(index, formalOperators: util) == .int(2))
    #expect(try compiledValue(sequenceSet, formalOperators: util) == .set([.int(1), .int(2)]))
    #expect(try compiledValue(permutations, formalOperators: util) == .set([
      .tuple([.int(1), .int(2)]), .tuple([.int(2), .int(1)])
    ]))
    #expect(try KeyValueStoreUtil.module.compile().renderedTLAModuleBundle().tla.contains("ReduceSet(op(_, _), set, base) =="))
  }
}
