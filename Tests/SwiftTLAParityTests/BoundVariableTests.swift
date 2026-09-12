@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct BoundVariableTests { @Test("Function literal with bound variable evaluates correctly")
  func functionLiteralWithBoundVar() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 2).raw)
    let functionValue = try compiledValue(fun)
    guard case .function(let mapping) = functionValue else {
      #expect(Bool(false))
      return
    }
    #expect(mapping[.int(1)] == .int(2))
    #expect(mapping[.int(2)] == .int(4))
    #expect(mapping[.int(3)] == .int(6))
  }

  @Test("Function apply on constructed function")
  func functionApply() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let apply = StateExpr.functionApply(fun, .value(.int(2)))
    let appliedValue = try compiledValue(apply)
    #expect(appliedValue == .int(20))
  }

  @Test("Function EXCEPT updates a key")
  func functionExcept() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let updated = StateExpr.except(fun, .value(.int(1)), .value(.int(99)))
    let updatedFunction = try compiledValue(updated)
    guard case .function(let mapping) = updatedFunction else {
      #expect(Bool(false))
      return
    }
    #expect(mapping[.int(1)] == .int(99))
    #expect(mapping[.int(2)] == .int(20))
  }

  @Test("Function EXCEPT preserves its domain")
  func functionExceptPreservesDomain() throws {
    let p = Var<Int>("p")
    let function = StateExpr.functionLiteral(p, in: StateExpr.set([1]), (p * 10).raw)
    let updated = StateExpr.except(function, .int(2), .int(99))

    guard case .function(let mapping) = try compiledValue(updated) else {
      #expect(Bool(false))
      return
    }
    #expect(mapping == [.int(1): .int(10)])
  }

  @Test("Partial function override does not read its missing entry")
  func partialFunctionOverrideDoesNotReadMissingEntry() throws {
    let empty = StateExpr.value(.function([:]))
    let first = StateExpr.partialFunctionOverriding(empty, key: .int(1), value: .int(0))

    guard case .function(let mapping) = try compiledValue(first) else {
      #expect(Bool(false))
      return
    }
    #expect(mapping == [.int(1): .int(0)])
  }

  @Test("Partial function override preserves entries")
  func partialFunctionOverridePreservesEntries() throws {
    let empty = StateExpr.value(.function([:]))
    let first = StateExpr.partialFunctionOverriding(empty, key: .int(1), value: .int(0))
    let second = StateExpr.partialFunctionOverriding(first, key: .int(2), value: .int(1))

    guard case .function(let mapping) = try compiledValue(second) else {
      #expect(Bool(false))
      return
    }
    #expect(mapping == [.int(1): .int(0), .int(2): .int(1)])
  }

  @Test("Partial function override renders a domain-preserving conditional")
  func partialFunctionOverrideRendersConditional() throws {
    let expression = StateExpr.partialFunctionOverriding(
      .value(.function([:])), key: .int(1), value: .int(0))
    let rendered = try renderedStateExpression(expression)

    #expect(rendered.contains("__typedPartialFunctionOverrideEntry"))
    #expect(rendered.contains("DOMAIN"))
    #expect(rendered.contains("IF"))
  }

  @Test("Partial function override avoids free names")
  func partialFunctionOverrideAvoidsCapture() {
    let function = Expr<PartialFunction<PartialFunctionKey, Int>>(.variable("entries"))
    let probe = function.overriding(.one, with: 0)
    guard case .functionLiteral(_, let preferred, _) = probe.raw else {
      #expect(Bool(false))
      return
    }
    let key = Expr<PartialFunctionKey>(.variable(preferred))
    let value = Expr<Int>(.variable(preferred))
    let override = function.overriding(key, with: value)

    guard case .functionLiteral(_, let binder, _) = override.raw else {
      #expect(Bool(false))
      return
    }
    #expect(binder == "\(preferred)_1")
  }

  @Test("Nested EXCEPT chains correctly")
  func nestedExcept() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, p.stateExpr)
    let expr = StateExpr.except(
      StateExpr.except(fun, .value(.int(1)), .value(.int(10))),
      .value(.int(2)), .value(.int(20))
    )
    let nestedFunction = try compiledValue(expr)
    guard case .function(let mapping) = nestedFunction else {
      #expect(Bool(false))
      return
    }
    #expect(mapping[.int(1)] == .int(10))
    #expect(mapping[.int(2)] == .int(20))
  }

  @Test("FunctionApply with bound variable predicate evaluates")
  func forAllWithBoundVar() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let predicate = StateExpr.forAll(
      p, in: domain, StateExpr.greaterThan(p.stateExpr, StateExpr.value(.int(0))))
    #expect(try compiledValue(predicate) == .bool(true))
  }

  @Test("exists with bound variable finds matching element")
  func existsWithBoundVar() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let predicate = StateExpr.exists(
      p, in: domain, StateExpr.equal(p.stateExpr, StateExpr.value(.int(2))))
    #expect(try compiledValue(predicate) == .bool(true))
  }

  @Test("Sequence variable append and read in model checker")
  func sequenceVariableAppendRead() throws {
    let seq = Var<TupleExpr<Int>>("seq")
    let result = Var<Int>("result")
    let spec = TLASpec("SeqTest") {
      Variable(seq, TupleExpr<Int>())
      Variable(result, 0)
      Action("push") {
        seq.becomes(Expr<TupleExpr<Int>>(seq.stateExpr.appending(42))).when(seq.expr.count == 0)
          && result.stays
      }
      Action("pop") { seq.stateExpr.count > 0 && result.becomes(Expr<Int>(seq.stateExpr.at(1))) }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
    ).explore()
    let resultToken = try #require(TLAStateProjection.Token(validating: "result"))
    let results = Set(exploration.graph.states.values.compactMap { $0.value(for: resultToken) })
    #expect(results.contains(.int(0)))
    #expect(results.contains(.int(42)))
  }

  @Test("Function-typed variable stores and retrieves values")
  func functionVariable() throws {
    let clock = Var<Function<FunctionVariableKey, Int>>("clock")
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let spec = TLASpec("FuncTest") {
      Variable(clock, Function<FunctionVariableKey, Int>.literal((.one, 0), (.two, 0)))
      Action("init") {
        let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
        clock.becomes(Expr<Function<FunctionVariableKey, Int>>(fun)).when(clock[.one] == 0)
      }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
    ).explore()
    let clockToken = try #require(TLAStateProjection.Token(validating: "clock"))
    var found = false
    for state in exploration.graph.states.values {
      if case .function(let m)? = state.value(for: clockToken) {
        if m[.int(1)] == .int(10) && m[.int(2)] == .int(20) {
          found = true
        }
      }
    }
    #expect(found)
  }

  @Test("bound choice produces nondeterministic assignment")
  func boundChoiceUpdatesSelectedMember() throws {
    let picked = Var<Int>("picked")
    let source = Var<SetExpr<Int>>("source")
    let spec = TLASpec("ChooseTest") {
      Variable(picked, 0)
      Variable(source, SetExpr(1, 2, 3))
      Action("pick") {
        source.stateExpr.cardinality > 0
          && ActionExpr.exists("selected", from: source) { selected in
            picked.becomes(Expr<Int>(selected))
              && source.becomes(Expr(.setDifference(source.stateExpr, StateExpr.singleton(selected))))
          }
      }
    }
    if case .ok(let count) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).check() {
      #expect(count > 0)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("SpecParser preserves explicit choice binders")
  func specParserBoundChoiceCall() throws {
    let source = "ActionExpr.exists(\"selected\", from: q) { member in picked.becomes(Expr<Int>(member)) }"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
    let decodedAction = SpecParser.decodeActionExpr(expr)
    #expect(decodedAction == ActionExpr.existsAction("selected", .variable("q"),
      .assign(.named("picked"), .variable("selected"))))
  }

  @Test("SpecParser parses singleton()")
  func specParserSingleton() throws {
    let source = "StateExpr.singleton(x)"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
    let decodedState = SpecParser.decodeStateExpr(expr)
    #expect(decodedState == StateExpr.setLiteral([.variable("x")]))
  }

  @Test("SpecParser parses functionLiteral(p, in: domain, body)")
  func specParserFunctionLiteral() throws {
    let source = "StateExpr.functionLiteral(StateExpr.set([1]), \"value\", value + 3)"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
    let decodedFunction = SpecParser.decodeStateExpr(expr)
    #expect(decodedFunction == .functionLiteral(
      .setLiteral([.int(1)]),
      "value",
      .add(.variable("value"), .int(3))
    ))
  }

  @Test("Compiled function literals render with their canonical binder")
  func functionTLAOutput() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let spec = TLASpec("FunctionLiteral") {
      FormalDefinition("Double", parameters: [], body: fun)
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("Double == [p \\in {1, 2} |-> (p * 10)]"))
  }
}
