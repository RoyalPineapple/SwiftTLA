import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct GeneratedTypedLocalRecursionModel {
  static var spec: TLASpec {
    #spec("GeneratedTypedLocalRecursionModel") {
      FormalDefinition(
        "CountDown",
        parameters: [],
        body: LetRec("Count", over: IntRange(0, through: 4), taking: Int.self, { (recursion: LocalRecursion<Int, Int>, number: WithValue<Int>) in
          If(number == 0, then: 0, else: recursion(number.expr - 1))
        }, in: { recursion in recursion(4) })
      )
      Algorithm("GeneratedTypedLocalRecursionModel") {
        let counter = SharedVar(initial: 0)
        Do("advance") {
          Assign(counter, to: counter.expr + 1)
        }
      }
    }
  }
}

@TLAModel
private struct GeneratedTypedFormalDefinitionAlgorithm {
  static var spec: TLASpec {
    #spec("GeneratedTypedFormalDefinitionAlgorithm") {
      Algorithm("GeneratedTypedFormalDefinitionAlgorithm") {
        FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
          LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
            If(current == 0, then: true, else: recursion(current.expr - 1))
          }, in: { recursion in recursion(ballot.expr) })
        }
        let counter = SharedVar(initial: 0)
        Do("advance") {
          Assign(counter, to: counter.expr + 1)
        }
      }
    }
  }
}

@Suite("Local TLA+ operators")
struct LocalOperatorTests {
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

    #expect(try expression.stateExpr.evaluate(in: ["limit": .int(4)]) == .int(0))
    #expect(expression.stateExpr.description.contains("SumTo["))
  }

  @Test("#spec preserves typed local recursion through generated model parsing")
  func generatedModelRetainsTypedLocalRecursion() throws {
    GeneratedTypedLocalRecursionModel._checkParserTree()
    let body = try #require(GeneratedTypedLocalRecursionModel.spec.formalOperatorDefinitions.first?.body)
    #expect(body.description.contains("Count[number \\in 0..4]"))
    #expect(body.description.contains("IN Count[4]"))

    var model = GeneratedTypedLocalRecursionModel()
    #expect(try model.apply(.advance).after.counter == 1)
  }

  @Test("typed formal closures retain local recursion through #spec and Algorithm")
  func generatedAlgorithmRetainsTypedFormalDefinition() throws {
    GeneratedTypedFormalDefinitionAlgorithm._checkParserTree()
    let definition = try #require(
      GeneratedTypedFormalDefinitionAlgorithm.spec.formalOperatorDefinitions.first
    )
    #expect(definition.parameters == [.value("value0"), .value("value1")])
    #expect(definition.body.description.contains("LET RECURSIVE SA"))

    var model = GeneratedTypedFormalDefinitionAlgorithm()
    #expect(try model.apply(.advance).after.counter == 1)
  }

  @Test("typed local recursion is parser-fidelitous and preserves ForAll and Exists")
  func parserRetainsTypedLocalRecursion() {
    let source = """
    {
      FormalDefinition(
        "Bounded",
        parameters: [.value("limit")],
        body: LetRec("AtMost", over: IntRange(0, through: limit), taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, number: WithValue<Int>) in
          If(number == 0, then: true, else: Exists(in: IntRange(0, through: number.expr - 1)) { prior in
            recursion(prior.expr) && ForAll(in: IntRange(0, through: number.expr)) { candidate in
              candidate <= number.expr
            }
          })
        }, in: { recursion in recursion(limit) })
      )
    }
    """
    let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
    #expect(parsed.formalOperatorDefinitions.count == 1)
    let body = parsed.formalOperatorDefinitions[0].body
    guard case .letIn(let operators, let call) = body else {
      Issue.record("Expected a local LET expression")
      return
    }
    #expect(operators.count == 1)
    #expect(operators[0].name == "AtMost")
    #expect(operators[0].parameters == ["number"])
    #expect(operators[0].domain == .integerRange(.int(0), .variable("limit")))
    #expect(operators[0].body.description.contains("\\E"))
    #expect(operators[0].body.description.contains("\\A"))
    #expect(operators[0].body.description.contains("AtMost["))
    #expect(call.description == "AtMost[limit]")
  }

  @Test("bounded LET rejects arguments outside its declared domain")
  func boundedLocalRecursionRejectsOutOfDomainArgument() {
    let expression: StateExpr = .letIn([
      LocalOperator("OnlyZero", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .variable("value"))
    ], .recursiveCall("OnlyZero", [.int(1)]))

    #expect(throws: EvalError.self) {
      try expression.evaluate(in: [:])
    }
  }

  @Test("bounded LET lowering respects an inner operator shadow")
  func boundedLocalRecursionLoweringRespectsInnerShadow() throws {
    let expression: StateExpr = .letIn([
      LocalOperator("Loop", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .int(0))
    ], .letIn([
      LocalOperator("Loop", parameters: ["value"], domain: .setLiteral([.int(0)]), body: .add(.variable("value"), .int(10)))
    ], .functionApply(.variable("Loop"), .int(0))))

    #expect(try expression.evaluate(in: [:]) == .int(10))
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

    #expect(try expression.evaluate(in: [:]) == .int(20))
  }

  @Test("malformed typed local recursion is rejected structurally")
  func parserRejectsMalformedTypedLocalRecursion() {
    let source = """
    {
      FormalDefinition("Bad", parameters: [], body: LetRec("Loop", over: IntRange(0, through: 1), taking: Int.self, { recursion in recursion(0) }, in: { recursion in recursion(0) }))
    }
    """
    let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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

    #expect(try expression.evaluate(in: [:]) == .int(10))
    #expect(expression.description.contains("LET RECURSIVE SumTo(_)"))
    #expect(expression.description.contains("SumTo(number) =="))
  }

  @Test("LET operators are emitted as executable TLA+ source")
  func emitsLetInSource() {
    let local = LocalOperator("AddOne", parameters: ["number"], body: .add(.variable("number"), .int(1)))
    let spec = TLASpec("LocalOperatorSource") {
      Definition("Answer") {
        .letIn([local], .recursiveCall("AddOne", [.int(41)]))
      }
    }

    #expect(spec.tlaModule.contains("Answer == LET AddOne(number) == (number + 1)"))
    #expect(spec.tlaModule.contains("IN AddOne(41)"))
  }

  @Test("the macro parser retains LET operator definitions")
  func parserRetainsLocalOperators() {
    let source = "StateExpr.letIn([LocalOperator(\"Truth\", parameters: [\"value\"], domain: StateExpr.integerRange(0, 1), body: true)], true)"
    let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
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
  func rejectsWrongArity() {
    let operation = LocalOperator("Only", parameters: ["value"], body: .variable("value"))
    let expression: StateExpr = .letIn([operation], .recursiveCall("Only", []))

    #expect(throws: EvalError.self) {
      try expression.evaluate(in: [:])
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

    #expect(try expression.evaluate(in: ["value": .int(0)]) == .int(5))
    #expect(try substituted.evaluate(in: ["value": .int(0)]) == .int(5))
    #expect(expression.description == "LET value == 4 IN (value + 1)")
    #expect(expression.swiftSource.contains("StateExpr.letValue(\"value\", 4,"))
  }
}
