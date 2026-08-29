import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
  try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

private func parseExpression(_ source: String) throws -> ExprSyntax {
  try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

private func renderedLocalOperatorExpression(_ body: StateExpr) throws -> String {
  try TLASpec(
    name: "LocalOperatorRendering",
    variables: [],
    actions: [],
    invariants: [],
    formalOperatorDefinitions: [.init(name: "Rendered", parameters: [], body: body)]
  ).compile().renderedTLAModuleBundle().tla
}

private func compiledLocalOperatorExpression(_ body: StateExpr) throws -> CompiledStateExpr {
  try #require(TLASpec(
    name: "LocalOperatorCompilation",
    variables: [],
    actions: [],
    invariants: [],
    formalOperatorDefinitions: [.init(name: "Compiled", parameters: [], body: body)]
  ).compile().semantics.formalOperatorDefinitions.first?.body)
}

private func renderedLocalOperatorDefinitions(_ definitions: [FormalOperatorDefinition]) throws -> String {
  try TLASpec(
    name: "LocalOperatorRendering",
    variables: [],
    actions: [],
    invariants: [],
    formalOperatorDefinitions: definitions
  ).compile().renderedTLAModuleBundle().tla
}

@TLAModel
private struct GeneratedTypedLocalRecursionModel {
  enum Step: String, CaseIterable { case advance }

  static var spec: TLASpec {
    #spec("GeneratedTypedLocalRecursionModel") {
      FormalDefinition(
        "CountDown",
        parameters: [],
        body: LetRec("Count", over: IntRange(0, through: 4), taking: Int.self, { (recursion: LocalRecursion<Int, Int>, number: WithValue<Int>) in
          If(number == 0, then: 0, else: recursion(number.expr - 1))
        }, in: { recursion in recursion(4) })
      )
      Algorithm("GeneratedTypedLocalRecursionModel", scoped: { scope in
        let counter = scope.sharedVar("counter", initial: 0)
        Do(Step.advance) {
          Assign(counter, to: counter.expr + 1)
        }
      })
    }
  }
}

@TLAModel
private struct GeneratedTypedFormalDefinitionAlgorithm {
  enum Step: String, CaseIterable { case advance }

  static var spec: TLASpec {
    #spec("GeneratedTypedFormalDefinitionAlgorithm") {
      FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
        LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
          If(current == 0, then: true, else: recursion(current.expr - 1))
        }, in: { recursion in recursion(ballot) })
      }
      Algorithm("GeneratedTypedFormalDefinitionAlgorithm", scoped: { scope in
        let counter = scope.sharedVar("counter", initial: 0)
        Do(Step.advance) {
          Assign(counter, to: counter.expr + 1)
        }
      })
    }
  }
}

@TLAModel
private struct GeneratedTopLevelTypedFormalDefinitionModel {
  enum Step: String, CaseIterable { case advance }

  static var spec: TLASpec {
    #spec("GeneratedTopLevelTypedFormalDefinitionModel") { scope in
      let bound = scope.sharedVar("bound", initial: 2)
      let counter = scope.sharedVar("counter", initial: 0)
      FormalDefinition("SafeAt", taking: Int.self) { ballot in
        LetRec("SA", over: IntRange(0, through: bound.expr), taking: Int.self, { recursion, current in
          If(current == 0, then: true, else: recursion(current.expr - 1))
        }, in: { recursion in recursion(ballot) })
      }
      Algorithm("GeneratedTopLevelTypedFormalDefinitionModel") {
        Do(Step.advance) {
          Assign(counter, to: counter.expr + 1)
        }
      }
    }
  }
}

@Suite("Local TLA+ operators")
struct LocalOperatorTests {
  @Test("bounded local calls compile identically from parser and builder syntax")
  func boundedLocalCallsHaveOneCompiledForm() throws {
    let parsed = try #require(SpecParser.decodeStateExpr(try parseExpression("""
      StateExpr.letIn([
        LocalOperator(
          "Count",
          parameters: ["number"],
          domain: StateExpr.integerRange(0, 4),
          body: If(
            StateExpr.variable("number") == 0,
            then: 0,
            else: StateExpr.variable("Count").applying(StateExpr.variable("number") - 1)
          )
        )
      ], StateExpr.variable("Count").applying(4))
      """)))
    let built = StateExpr.letIn([
      .init(
        "Count",
        parameters: ["number"],
        domain: .integerRange(.int(0), .int(4)),
        body: .ifThenElse(
          .equal(.variable("number"), .int(0)),
          .int(0),
          .recursiveCall("Count", [.subtract(.variable("number"), .int(1))])
        )
      )
    ], .recursiveCall("Count", [.int(4)]))

    let parsedCompilation = try compiledLocalOperatorExpression(parsed)
    let builtCompilation = try compiledLocalOperatorExpression(built)
    let parsedRendering = try renderedLocalOperatorExpression(parsed)
    let builtRendering = try renderedLocalOperatorExpression(built)
    #expect(parsedRendering == builtRendering)
    guard case .letIn(let parsedOperators, .functionApply(.operatorReference(let parsedCall), .value(.integer(4)))) = parsedCompilation,
          case .letIn(let builtOperators, .functionApply(.operatorReference(let builtCall), .value(.integer(4)))) = builtCompilation,
          let parsedOperator = parsedOperators.first,
          let builtOperator = builtOperators.first,
          case .ifThenElse(_, _, .functionApply(.operatorReference(let parsedRecursion), _)) = parsedOperator.body,
          case .ifThenElse(_, _, .functionApply(.operatorReference(let builtRecursion), _)) = builtOperator.body else {
      Issue.record("Expected one bounded compiled call")
      return
    }
    #expect(parsedCall == parsedOperator.id)
    #expect(parsedRecursion == parsedOperator.id)
    #expect(builtCall == builtOperator.id)
    #expect(builtRecursion == builtOperator.id)
  }

  @Test("operator calls compile identically from parser and builder syntax")
  func operatorCallsHaveOneCompiledForm() throws {
    let parsed = try #require(SpecParser.decodeStateExpr(try parseExpression("""
      StateExpr.letIn([
        LocalOperator(
          "AddOne",
          parameters: ["number"],
          body: StateExpr.variable("number") + 1
        )
      ], StateExpr.variable("AddOne").applying(41))
      """)))
    let operation = LocalOperator(
      "AddOne",
      parameters: ["number"],
      body: .add(.variable("number"), .int(1))
    )
    let built = StateExpr.letIn([operation], .recursiveCall("AddOne", [.int(41)]))

    let parsedCompilation = try compiledLocalOperatorExpression(parsed)
    let builtCompilation = try compiledLocalOperatorExpression(built)
    let parsedRendering = try renderedLocalOperatorExpression(parsed)
    let builtRendering = try renderedLocalOperatorExpression(built)
    #expect(parsedRendering == builtRendering)
    guard case .letIn(let parsedOperators, .recursiveCall(let parsedCall, let parsedArguments)) = parsedCompilation,
          case .letIn(let builtOperators, .recursiveCall(let builtCall, let builtArguments)) = builtCompilation,
          let parsedOperator = parsedOperators.first,
          let builtOperator = builtOperators.first,
          parsedArguments.count == 1,
          builtArguments.count == 1,
          case .some(.value(.integer(41))) = parsedArguments.first,
          case .some(.value(.integer(41))) = builtArguments.first else {
      Issue.record("Expected one operator-style compiled call")
      return
    }
    #expect(parsedCall == parsedOperator.id)
    #expect(builtCall == builtOperator.id)
  }

  @Test("typed unary LET recursion captures state and retains quantifier scope")
  func typedLocalRecursionUsesExistingLetInSemantics() throws {
    let limit = Var<Int>("limit")
    let expression: Expr<Int> = LetRec("SumTo", over: IntRange(0, through: limit), taking: Int.self, { (recursion: LocalRecursion<Int, Int>, number: WithValue<Int>) in
      If(
        number == limit,
        then: 0,
        else: recursion(number.expr + 1)
      )
    }, in: { recursion in
      recursion(0)
    })

    #expect(try compiledValue(expression.stateExpr, values: [("limit", .int(4))]) == .int(0))
  }

  @Test("#spec preserves typed local recursion through generated model parsing")
  func generatedModelRetainsTypedLocalRecursion() throws {
    let body = try #require(GeneratedTypedLocalRecursionModel.spec.formalOperatorDefinitions.first?.body)
    guard case .letIn(let operators, let call) = body else {
      Issue.record("Expected a compiled local operator")
      return
    }
    #expect(operators.first?.domain == .integerRange(.int(0), .int(4)))
    #expect(call == .recursiveCall("Count", [.int(4)]))
    let compilation = try GeneratedTypedLocalRecursionModel.spec.compile()
    let compiledDefinition = try #require(compilation.semantics.formalOperatorDefinitions.first)
    guard case .letIn(let compiledOperators, .functionApply(.operatorReference(let callID), .value(.integer(4)))) = compiledDefinition.body else {
      Issue.record("Expected a bound local operator application")
      return
    }
    #expect(callID == compiledOperators.first?.id)
    let rendered = compilation.renderedTLAModuleBundle().tla
    #expect(rendered.contains("LET Count["))
    #expect(!rendered.contains("LET RECURSIVE Count"))

    var model = try GeneratedTypedLocalRecursionModel.makeMachine()
    #expect(try model.send(.advance).after.counter == 1)
  }

  @Test("typed formal closures retain local recursion through #spec and Algorithm")
  func generatedAlgorithmRetainsTypedFormalDefinition() throws {
    let definition = try #require(
      GeneratedTypedFormalDefinitionAlgorithm.spec.formalOperatorDefinitions.first
    )
    #expect(definition.parameters == [.value("value0"), .value("value1")])
    let compilation = try GeneratedTypedFormalDefinitionAlgorithm.spec.compile()
    let compiledDefinition = try #require(compilation.semantics.formalOperatorDefinitions.first)
    guard case .letIn(let operators, _) = compiledDefinition.body else {
      Issue.record("Expected a compiled local operator")
      return
    }
    #expect(operators.first?.isRecursive == true)

    var model = try GeneratedTypedFormalDefinitionAlgorithm.makeMachine()
    #expect(try model.send(.advance).after.counter == 1)
  }

  @Test("captured formal definitions survive compilation, rendering, and generated execution")
  func generatedTopLevelTypedFormalDefinitionRetainsCapture() throws {
    let definition = try #require(
      GeneratedTopLevelTypedFormalDefinitionModel.spec.formalOperatorDefinitions.first
    )
    #expect(definition.parameters == [.value("value0")])
    let rendered = try GeneratedTopLevelTypedFormalDefinitionModel.spec.compile().renderedTLAModuleBundle().tla
    #expect(rendered.contains("0..bound"))
    #expect(rendered.contains("SA[value0]"))

    var model = try GeneratedTopLevelTypedFormalDefinitionModel.makeMachine()
    #expect(try model.send(.advance).after.counter == 1)
  }

  @Test("typed local recursion preserves quantified bindings")
  func typedLocalRecursionPreservesQuantifiedBindings() throws {
    let source = """
    {
      FormalDefinition("Bounded", taking: Int.self) { limit in
        LetRec("AtMost", over: IntRange(0, through: limit), taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, number: WithValue<Int>) in
          If(number == 0, then: true, else: Exists(in: IntRange(0, through: number.expr - 1)) { prior in
            recursion(prior.expr) && ForAll(in: IntRange(0, through: number.expr)) { candidate in
              candidate <= number.expr
            }
          })
        }, in: { recursion in recursion(limit) })
      }
    }
    """
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
    #expect(parsed.formalOperatorDefinitions.count == 1)
    let body = try #require(parsed.formalOperatorDefinitions.first?.body)
    guard case .letIn(let operators, let call) = body else {
      Issue.record("Expected a local LET expression")
      return
    }
    #expect(operators.count == 1)
    let operation = try #require(operators.first)
    #expect(operation.name == "AtMost")
    #expect(operation.parameters == ["number"])
    #expect(operation.domain == .integerRange(.int(0), .variable("value0")))
    #expect(call == .recursiveCall("AtMost", [.variable("value0")]))
    let compilation = try TLASpec(
      name: "BoundedLocalOperator",
      variables: [],
      actions: [],
      invariants: [],
      formalOperatorDefinitions: parsed.formalOperatorDefinitions
    ).compile()
    let compiledDefinition = try #require(compilation.semantics.formalOperatorDefinitions.first)
    guard case .letIn(let compiledOperators, .functionApply(.operatorReference(let callID), .boundValue)) = compiledDefinition.body else {
      Issue.record("Expected a bound local operator application")
      return
    }
    #expect(callID == compiledOperators.first?.id)
    let rendered = compilation.renderedTLAModuleBundle().tla
    #expect(rendered.contains("\\E"))
    #expect(rendered.contains("\\A"))
    #expect(rendered.contains("AtMost[value0]"))
  }

  @Test("bounded recursion retains scoped values through the general parser fallback")
  func parserRetainsScopedValuesInBoundedRecursion() throws {
    let source = """
    {
      FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, value in
        LetRec("SA", over: IntRange(0, through: value), taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, current) in
          current == 0 || Exists(in: IntRange(-1, through: current.expr - 1)) { prior in
            (recursion(prior.expr) && ForAll(in: IntRange(0, through: current.expr)) { candidate in
              Pair.literal(prior.expr, candidate.expr) == Pair.literal(ballot.expr, value.expr)
            })
          }
        }, in: { recursion in recursion(ballot.expr) })
      }
    }
    """
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
    let definition = try #require(parsed.formalOperatorDefinitions.first)
    let rendered = try renderedLocalOperatorDefinitions([definition])
    #expect(rendered.contains("SA[value0]"))
    #expect(rendered.contains("<<"))
  }

  @Test("bounded LET rejects arguments outside its declared domain")
  func boundedLocalRecursionRejectsOutOfDomainArgument() throws {
    let expression: StateExpr = .letIn([
      LocalOperator("OnlyZero", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .variable("value"))
    ], .recursiveCall("OnlyZero", [.int(1)]))

    #expect(throws: EvalError.self) {
      try compiledValue(expression)
    }
  }

  @Test("bounded LET exports a short-circuit guard before an out-of-domain recursive call")
  func boundedLocalRecursionExportsShortCircuitGuard() throws {
    let expression: StateExpr = .letIn([
      LocalOperator(
        "SA",
        parameters: ["ballot"],
        domain: .integerRange(.int(0), .int(2)),
        body: .exists(
          .integerRange(.int(-1), .int(0)),
          "prior",
          .or(
            .equal(.variable("prior"), .int(-1)),
            .functionApply(.variable("SA"), .variable("prior"))
          )
        )
      )
    ], .functionApply(.variable("SA"), .int(0)))

    #expect(try compiledValue(expression) == .bool(true))
    let rendered = try renderedLocalOperatorExpression(expression)
    #expect(rendered.contains("IF (prior = -1) THEN TRUE ELSE SA[prior]"))
  }

  @Test("bounded LET lowering respects an inner operator shadow")
  func boundedLocalRecursionLoweringRespectsInnerShadow() throws {
    let expression: StateExpr = .letIn([
      LocalOperator("Loop", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .int(0))
    ], .letIn([
      LocalOperator("Loop", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .add(.variable("value"), .int(10)))
    ], .functionApply(.variable("Loop"), .int(0))))

    #expect(try compiledValue(expression) == .int(10))
  }

  @Test("bounded LET lowering respects a shadowing value binding")
  func boundedLocalRecursionLoweringRespectsValueShadow() throws {
    let expression: StateExpr = .letIn([
      LocalOperator("Loop", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .int(0))
    ], .letValue(
      "Loop",
      .functionLiteral(.setLiteral([.int(0)]), "value", .add(.variable("value"), .int(20))),
      .functionApply(.variable("Loop"), .int(0))
    ))

    #expect(try compiledValue(expression) == .int(20))
  }

  @Test("malformed typed local recursion is rejected structurally")
  func parserRejectsMalformedTypedLocalRecursion() throws {
    let source = """
    {
      FormalDefinition("Bad", parameters: [], body: LetRec("Loop", over: IntRange(0, through: 1), taking: Int.self, { recursion in recursion(0) }, in: { recursion in recursion(0) }))
    }
    """
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.contains { $0.message.contains("FormalDefinition requires") })
  }

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

    #expect(try compiledValue(expression) == .int(10))
  }

  @Test("terminating recursive operators evaluate beyond host call depth")
  func evaluatesDeepTerminatingRecursion() throws {
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
    let expression = StateExpr.letIn([sumTo], .recursiveCall("SumTo", [.int(512)]))

    #expect(try compiledValue(expression) == .int(131_328))
  }

  @Test("LET operators are emitted as executable TLA+ source")
  func emitsLetInSource() throws {
    let local = LocalOperator("AddOne", parameters: ["number"], body: .add(.variable("number"), .int(1)))
    let spec = TLASpec("LocalOperatorSource") {
      FormalDefinition("Answer", parameters: [], body: .letIn([local], .recursiveCall("AddOne", [.int(41)])))
    }

    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains(
      "Answer == LET AddOne(number) == (number + 1)"
    ))
    #expect(!(try spec.compile().renderedTLAModuleBundle().tla.contains("RECURSIVE AddOne")))
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("IN AddOne(41)"))
  }

  @Test("compiled rendering declares recursive LET operators")
  func rendersRecursiveLetOperatorDeclaration() throws {
    let sumTo = LocalOperator(
      "SumTo",
      parameters: ["number"],
      body: .ifThenElse(
        .equal(.variable("number"), .int(0)),
        .int(0),
        .add(.variable("number"), .recursiveCall("SumTo", [.subtract(.variable("number"), .int(1))]))
      )
    )
    let spec = TLASpec("RecursiveLocalOperatorSource") {
      FormalDefinition("Answer", parameters: [], body: .letIn([sumTo], .recursiveCall("SumTo", [.int(4)])))
    }

    let compilation = try spec.compile()
    #expect(compilation.renderedTLAModuleBundle().tla.contains("LET RECURSIVE SumTo(_)"))

    let definition = try #require(compilation.semantics.formalOperatorDefinitions.first)
    guard case .letIn(let operators, _) = definition.body else {
      Issue.record("Expected a compiled local operator")
      return
    }
    #expect(try #require(operators.first).isRecursive)
  }

  @Test("the macro parser retains LET operator definitions")
  func parserRetainsLocalOperators() throws {
    let source = "StateExpr.letIn([LocalOperator(\"Truth\", parameters: [\"value\"], domain: StateExpr.integerRange(0, 1), body: true)], true)"
    let syntax = try parseExpression(source)
    let parsed = SpecParser.decodeStateExpr(syntax)
    let expected: StateExpr = .letIn(
      [LocalOperator(
        "Truth",
        parameters: ["value"],
        domain: .integerRange(.int(0), .int(1)),
        body: .bool(true)
      )],
      .bool(true)
    )

    #expect(parsed == expected)
  }

  @Test("local operator calls validate their arity")
  func rejectsWrongArity() throws {
    let operation = LocalOperator("Only", parameters: ["value"], body: .variable("value"))
    let expression: StateExpr = .letIn([operation], .recursiveCall("Only", []))

    #expect(throws: CompilationDiagnostic.self) {
      try compiledValue(expression)
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

    #expect(try compiledValue(expression, values: [("value", .int(0))]) == .int(5))
    #expect(try compiledValue(substituted, values: [("value", .int(0))]) == .int(5))
    let rendered = try renderedLocalOperatorExpression(expression)
    #expect(rendered.contains("LET value == 4 IN (value + 1)"))
  }
}
