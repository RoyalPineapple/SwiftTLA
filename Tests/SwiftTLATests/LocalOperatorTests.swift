@testable import SwiftTLAPlugin
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
  ).compile().render().tlaBundle.tla
}

private func compiledLocalOperatorSpecification(_ body: StateExpr) throws -> CompiledSpecification {
  try TLASpec(
    name: "LocalOperatorCompilation",
    variables: [],
    actions: [],
    invariants: [],
    formalOperatorDefinitions: [.init(name: "Compiled", parameters: [], body: body)]
  ).compile()
}

private func renderedLocalOperatorDefinitions(_ definitions: [FormalOperatorDefinition]) throws -> String {
  try TLASpec(
    name: "LocalOperatorRendering",
    variables: [],
    actions: [],
    invariants: [],
    formalOperatorDefinitions: definitions
  ).compile().render().tlaBundle.tla
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
  @Test("LET result types follow the body independently of recursive output")
  func localRecursionPreservesBodyResultType() throws {
    let predicate: Expr<Bool> = LetRec("Constant", over: IntRange(0, through: 1), taking: Int.self,
      { (_: LocalRecursion<Int, Int>, _: WithValue<Int>) in 7 },
      in: { recursion in recursion(0) == 7 })
    #expect(try compiledValue(predicate.stateExpr) == .bool(true))

    let message: Expr<String> = LetRec("Constant", over: IntRange(0, through: 1), taking: Int.self,
      { (_: LocalRecursion<Int, Int>, _: WithValue<Int>) in 7 },
      in: { _ in "finished" })
    #expect(try compiledValue(message.stateExpr) == .string("finished"))
  }

  @Test("local operator parsing rejects undecodable declarations", arguments: [
    "parameters: externalParameters, body: 7",
    "parameters: [], domain: makeDomain(), body: 7"
  ])
  func rejectsUndecodableLocalDeclarations(_ declaration: String) throws {
    let expression = try parseExpression("""
      StateExpr.letIn([
        LocalOperator("Bounded", \(declaration))
      ], StateExpr.operatorApplication(.reference("Bounded", arity: 0), []))
      """)
    #expect(SpecParser.decodeStateExpr(expression) == nil)
  }

  @Test("an explicitly absent local operator domain remains unbounded")
  func explicitAbsentLocalDomain() throws {
    let expression = try parseExpression("""
      StateExpr.letIn([
        LocalOperator("Constant", parameters: [], domain: nil, body: 7)
      ], StateExpr.operatorApplication(.reference("Constant", arity: 0), []))
      """)
    let decoded = try #require(SpecParser.decodeStateExpr(expression))
    #expect(try compiledValue(decoded) == .int(7))
  }

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

    let parsedCompilation = try compiledLocalOperatorSpecification(parsed)
    let builtCompilation = try compiledLocalOperatorSpecification(built)
    let parsedRendering = try renderedLocalOperatorExpression(parsed)
    let builtRendering = try renderedLocalOperatorExpression(built)
    #expect(parsedRendering == builtRendering)
    let parsedDefinitionID = try #require(parsedCompilation.semantics.operators.formalDefinitionIDs.first)
    let parsedDefinition = try #require(parsedCompilation.semantics.operators[parsedDefinitionID])
    let builtDefinitionID = try #require(builtCompilation.semantics.operators.formalDefinitionIDs.first)
    let builtDefinition = try #require(builtCompilation.semantics.operators[builtDefinitionID])
    guard case .letIn(let parsedOperators) = parsedDefinition.body.operation,
              case .functionApply = parsedDefinition.body.children[0].operation,
              case .operatorReference(let parsedCall) = parsedDefinition.body.children[0].children[0].operation,
              case .value(.integer(4)) = parsedDefinition.body.children[0].children[1].operation,
          case .letIn(let builtOperators) = builtDefinition.body.operation,
              case .functionApply = builtDefinition.body.children[0].operation,
              case .operatorReference(let builtCall) = builtDefinition.body.children[0].children[0].operation,
              case .value(.integer(4)) = builtDefinition.body.children[0].children[1].operation,
          let parsedID = parsedOperators.first,
          let parsedOperator = parsedCompilation.semantics.operators[parsedID],
          let builtID = builtOperators.first,
          let builtOperator = builtCompilation.semantics.operators[builtID],
          case .ifThenElse = parsedOperator.body.operation,
              case .functionApply = parsedOperator.body.children[2].operation,
              case .operatorReference(let parsedRecursion) = parsedOperator.body.children[2].children[0].operation,
          case .ifThenElse = builtOperator.body.operation,
              case .functionApply = builtOperator.body.children[2].operation,
              case .operatorReference(let builtRecursion) = builtOperator.body.children[2].children[0].operation else {
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

    let parsedCompilation = try compiledLocalOperatorSpecification(parsed)
    let builtCompilation = try compiledLocalOperatorSpecification(built)
    let parsedRendering = try renderedLocalOperatorExpression(parsed)
    let builtRendering = try renderedLocalOperatorExpression(built)
    #expect(parsedRendering == builtRendering)
    let parsedDefinitionID = try #require(parsedCompilation.semantics.operators.formalDefinitionIDs.first)
    let parsedDefinition = try #require(parsedCompilation.semantics.operators[parsedDefinitionID])
    let builtDefinitionID = try #require(builtCompilation.semantics.operators.formalDefinitionIDs.first)
    let builtDefinition = try #require(builtCompilation.semantics.operators[builtDefinitionID])
    guard case .letIn(let parsedOperators) = parsedDefinition.body.operation,
              case .operatorApplication(.reference(let parsedCall, _), let parsedArguments) = parsedDefinition.body.children[0].operation,
          case .letIn(let builtOperators) = builtDefinition.body.operation,
              case .operatorApplication(.reference(let builtCall, _), let builtArguments) = builtDefinition.body.children[0].operation,
          let parsedID = parsedOperators.first,
          let parsedOperator = parsedCompilation.semantics.operators[parsedID],
          let builtID = builtOperators.first,
          let builtOperator = builtCompilation.semantics.operators[builtID],
          parsedArguments.count == 1,
          builtArguments.count == 1,
          case .some(let expression25) = parsedArguments.first,
              case .value(let expression26) = expression25,
              case .value(.integer(41)) = expression26.operation,
          case .some(let expression27) = builtArguments.first,
              case .value(let expression28) = expression27,
              case .value(.integer(41)) = expression28.operation else {
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

  @Test("#spec parsing preserves typed local recursion")
  func sourceSpecificationRetainsTypedLocalRecursion() throws {
    let body = try #require(GeneratedTypedLocalRecursionModel.spec.formalOperatorDefinitions.first?.body)
    guard case .letIn(let operators, let call) = body else {
      Issue.record("Expected a compiled local operator")
      return
    }
    #expect(operators.first?.domain == .integerRange(.int(0), .int(4)))
    #expect(call == .recursiveCall("Count", [.int(4)]))
    let compilation = try GeneratedTypedLocalRecursionModel.spec.compile()
    let compiledDefinitionID = try #require(compilation.semantics.operators.formalDefinitionIDs.first)
    let compiledDefinition = try #require(compilation.semantics.operators[compiledDefinitionID])
    guard case .letIn(let compiledOperators) = compiledDefinition.body.operation,
              case .functionApply = compiledDefinition.body.children[0].operation,
              case .operatorReference(let callID) = compiledDefinition.body.children[0].children[0].operation,
              case .value(.integer(4)) = compiledDefinition.body.children[0].children[1].operation else {
      Issue.record("Expected a bound local operator application")
      return
    }
    #expect(callID == compiledOperators.first)
    let rendered = try compilation.render().tlaBundle.tla
    #expect(rendered.contains("LET Count["))
    #expect(!rendered.contains("LET RECURSIVE Count"))

    var machine = try GeneratedTypedLocalRecursionModel.makeMachine()
    #expect(try machine.send(.advance).after.counter == 1)
  }

  @Test("typed formal closures retain local recursion through #spec and Algorithm")
  func generatedAlgorithmRetainsTypedFormalDefinition() throws {
    let definition = try #require(
      GeneratedTypedFormalDefinitionAlgorithm.spec.formalOperatorDefinitions.first
    )
    #expect(definition.parameters == [.value("value0", typeName: "Int"), .value("value1", typeName: "Int")])
    let compilation = try GeneratedTypedFormalDefinitionAlgorithm.spec.compile()
    let compiledDefinitionID = try #require(compilation.semantics.operators.formalDefinitionIDs.first)
    let compiledDefinition = try #require(compilation.semantics.operators[compiledDefinitionID])
    guard case .letIn(let operators) = compiledDefinition.body.operation else {
      Issue.record("Expected a compiled local operator")
      return
    }
    let id = try #require(operators.first)
    let operation = try #require(compilation.semantics.operators[id])
    #expect(operation.isRecursive)

    var machine = try GeneratedTypedFormalDefinitionAlgorithm.makeMachine()
    #expect(try machine.send(.advance).after.counter == 1)
  }

  @Test("captured formal definitions survive compilation, rendering, and generated execution")
  func generatedTopLevelTypedFormalDefinitionRetainsCapture() throws {
    let definition = try #require(
      GeneratedTopLevelTypedFormalDefinitionModel.spec.formalOperatorDefinitions.first
    )
    #expect(definition.parameters == [.value("value0", typeName: "Int")])
    let rendered = try GeneratedTopLevelTypedFormalDefinitionModel.spec.compile().render().tlaBundle.tla
    #expect(rendered.contains("0..bound"))
    #expect(rendered.contains("SA[value0]"))

    var machine = try GeneratedTopLevelTypedFormalDefinitionModel.makeMachine()
    #expect(try machine.send(.advance).after.counter == 1)
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
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

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
    let compiledDefinitionID = try #require(compilation.semantics.operators.formalDefinitionIDs.first)
    let compiledDefinition = try #require(compilation.semantics.operators[compiledDefinitionID])
    guard case .letIn(let compiledOperators) = compiledDefinition.body.operation,
              case .functionApply = compiledDefinition.body.children[0].operation,
              case .operatorReference(let callID) = compiledDefinition.body.children[0].children[0].operation,
              case .boundValue = compiledDefinition.body.children[0].children[1].operation else {
      Issue.record("Expected a bound local operator application")
      return
    }
    #expect(callID == compiledOperators.first)
    let rendered = try compilation.render().tlaBundle.tla
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
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

    #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
    let definition = try #require(parsed.formalOperatorDefinitions.first)
    let rendered = try renderedLocalOperatorDefinitions([definition])
    #expect(rendered.contains("SA[value0]"))
    #expect(rendered.contains("<<"))
  }

  @Test("bounded calls evaluate the domain before the argument and validate membership before the body")
  func boundedCallFailureOrder() {
    let division = StateExpr.divide(.int(1), .int(0))
    let choice = StateExpr.choose(.setLiteral([]), "item", .value(.bool(true)))
    func call(domain: StateExpr, argument: StateExpr) -> StateExpr {
      .letIn([
        LocalOperator("Bounded", parameters: ["value"], domain: domain, body: division)
      ], .recursiveCall("Bounded", [argument]))
    }
    #expect(throws: EvalError.divisionByZero) {
      try compiledValue(call(domain: division, argument: choice))
    }
    #expect(throws: EvalError.divisionByZero) {
      try compiledValue(call(domain: .int(0), argument: division))
    }
    #expect(throws: EvalError.expected(.set, actual: [.integer(0)])) {
      try compiledValue(call(domain: .int(0), argument: .int(1)))
    }
    #expect(throws: EvalError.recursiveArgumentOutsideDomain) {
      try compiledValue(call(domain: .setLiteral([]), argument: .int(1)))
    }
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
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

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

    #expect(try spec.compile().render().tlaBundle.tla.contains(
      "Answer == LET AddOne(number) == (number + 1)"
    ))
    #expect(!(try spec.compile().render().tlaBundle.tla.contains("RECURSIVE AddOne")))
    #expect(try spec.compile().render().tlaBundle.tla.contains("IN AddOne(41)"))
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
    #expect(try compilation.render().tlaBundle.tla.contains("LET RECURSIVE SumTo(_)"))

    let definitionID = try #require(compilation.semantics.operators.formalDefinitionIDs.first)
    let definition = try #require(compilation.semantics.operators[definitionID])
    guard case .letIn(let operators) = definition.body.operation else {
      Issue.record("Expected a compiled local operator")
      return
    }
    let id = try #require(operators.first)
    let operation = try #require(compilation.semantics.operators[id])
    #expect(operation.isRecursive)
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
