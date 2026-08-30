@testable import SwiftTLA
import SwiftTLAMacros
import Testing

@TLAModel
private struct GeneratedHigherOrderFormalModel {
  enum Step: String, CaseIterable { case advance }

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
      Algorithm("GeneratedHigherOrderFormalModel", scoped: { scope in
        let counter = scope.sharedVar("counter", initial: 0)
        Do(Step.advance) {
          Assign(counter, to: counter.expr + 1)
        }
      })
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
  }

  @Test("a #spec higher-order formal definition preserves parser and builder trees")
  func generatedHigherOrderFormalDefinitionPreservesParserFidelity() throws {

    var machine = try GeneratedHigherOrderFormalModel.makeMachine()
    let transition = try machine.send(.advance)
    #expect(transition.after.counter == 1)
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

  @Test("a formal lambda application renders as a scoped TLA+ value expression")
  func rendersFormalLambdaApplication() throws {
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

    #expect(rendered.contains("(LET value == counter IN (value + 1))"))
  }

  @Test("compilation rejects formal operator arity mismatches")
  func rejectsFormalOperatorArityMismatches() {
    let specifications = [
      TLASpec(
        name: "LambdaArity",
        variables: [.init(name: "counter", initial: .int(0))],
        actions: [.init(name: "advance", body: .assign(
          .named("counter"),
          .operatorApplication(.lambda(.init(parameters: ["value"], body: .variable("value"))), [])
        ))],
        invariants: []
      ),
      TLASpec(
        name: "ReferenceArity",
        variables: [.init(name: "counter", initial: .int(0))],
        actions: [.init(name: "advance", body: .assign(
          .named("counter"),
          .operatorApplication(.reference("increment", arity: 0), [])
        ))],
        invariants: [],
        formalOperatorDefinitions: [.init(
          name: "increment",
          parameters: [.value("value")],
          body: .add(.variable("value"), .int(1))
        )]
      ),
      TLASpec(
        name: "RecursiveArity",
        variables: [.init(name: "counter", initial: .int(0))],
        actions: [.init(name: "advance", body: .assign(
          .named("counter"),
          .recursiveCall("increment", [])
        ))],
        invariants: [],
        recursiveFuncs: [.init(
          name: "increment",
          params: ["value"],
          body: .add(.variable("value"), .int(1))
        )]
      )
    ]

    for specification in specifications {
      do {
        _ = try specification.compile()
        Issue.record("Expected compilation to reject the formal operator call")
      } catch let diagnostic as CompilationDiagnostic {
        #expect(diagnostic.code == .invalidFormalOperatorApplication)
      } catch {
        Issue.record("Expected CompilationDiagnostic, got \(error)")
      }
    }
  }

  @Test("a formal reference resolves through the formal operator environment")
  func appliesNamedFormalOperator() throws {
    let expression = StateExpr.operatorApplication(
      .reference("increment", arity: 1),
      [.value(.int(4))]
    )
    let increment = FormalOperatorDefinition(
      name: "increment",
      parameters: [.value("value")],
      body: .add(.variable("value"), .int(1))
    )

    #expect(try compiledValue(expression, formalOperators: [increment]) == .int(5))
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

  @Test("unused formal value arguments remain unevaluated")
  func formalValueArgumentsAreLazy() throws {
    let first = FormalOperatorDefinition(
      name: "first",
      parameters: [.value("value"), .value("unused")],
      body: .variable("value")
    )
    let expression = StateExpr.operatorApplication(
      .reference("first", arity: 2),
      [.value(.int(42)), .value(.divide(.int(1), .int(0)))]
    )

    #expect(try compiledValue(expression, formalOperators: [first]) == .int(42))
  }

  @Test("exploration and compiled execution apply a specification-owned formal operator")
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
    let initial = try firstCompiledState(in: compilation)
    let successor = try #require(try compiledSuccessors(named: "advance", arguments: [], in: compilation, from: initial).first)
    #expect(try renderedValue(named: "counter", in: successor, compilation: compilation) == .int(2))
    let outcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = outcome { true } else { false } }())
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
    let initial = try firstCompiledState(in: compilation)
    let successor = try #require(try compiledSuccessors(named: "advance", arguments: [], in: compilation, from: initial).first)
    #expect(try renderedValue(named: "counter", in: successor, compilation: compilation) == .int(2))
    let outcome = try ModelChecker(compilation: try consumer.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = outcome { true } else { false } }())
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
        formalOperators: try FormalModuleClosure.resolve(root: Folds.module)
          .linkedOperators.formalOperatorDefinitions
      ) == .int(6)
    )
    let rendered = try Folds.module.compile().renderedTLAModuleBundle().tla
    #expect(rendered.contains("MapThenFoldSet(op(_, _),"))
    #expect(rendered.contains("choose(_),"))
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

    let functions = try FormalModuleClosure.resolve(root: FunctionsModule.module)
      .linkedOperators.formalOperatorDefinitions
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

    let util = try FormalModuleClosure.resolve(root: KeyValueStoreUtil.module)
      .linkedOperators.formalOperatorDefinitions
    #expect(try compiledValue(reduced, formalOperators: util) == .int(6))
    #expect(try compiledValue(index, formalOperators: util) == .int(2))
    #expect(try compiledValue(sequenceSet, formalOperators: util) == .set([.int(1), .int(2)]))
    #expect(try compiledValue(permutations, formalOperators: util) == .set([
      .tuple([.int(1), .int(2)]), .tuple([.int(2), .int(1)])
    ]))
    #expect(try KeyValueStoreUtil.module.compile().renderedTLAModuleBundle().tla.contains(
      "ReduceSet(op(_, _),"
    ))
  }
}
