import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct CompiledExpressionEvaluationTests {
  @Test("parameterized function update enumerates correctly")
  func chooseWithFunctionApply() throws {
    let phases = Var<Function<FunctionProcess, FunctionPhase>>("phases")
    let process = Expr<FunctionProcess>(.variable("process"))
    let spec = TLASpec("ParameterizedFunctionUpdate") {
      Variable(phases, Function<FunctionProcess, FunctionPhase>.literal(
        (.first, .initial), (.second, .initial)))
      Action(
        "advance",
        parameters: [ActionParameter("process", values: FunctionProcess.allCases)]
      ) {
        phases.becomes(phases.updating(process, to: .done))
          .when(phases[process] == FunctionPhase.initial)
      }
    }
    let compilation = try spec.compile()
    let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let advance = try #require(compilation.layout.testActionID(named: "advance"))
    let successors = try CompiledRuntime(compilation: compilation)
      .successors(for: advance, from: initial)
    #expect(successors.count == 2)
    let observed = try Set(successors.map { successor in
      try successor.state.value(for: #require(compilation.layout.testVariableID(named: "phases")))
        .rendered(using: compilation.layout)
    })
    #expect(observed == Set<TLAValue>([
      .function([.string("first"): .string("done"), .string("second"): .string("initial")]),
      .function([.string("first"): .string("initial"), .string("second"): .string("done")])
    ]))
  }

  @Test("sequence-from-set evaluates correctly")
  func recursiveBuiltins() throws {
    let sequenceValue = try compiledValue(.sequenceFromSet(.value(.set([.int(3), .int(1), .int(2)]))))
    #expect(sequenceValue == .tuple([.int(1), .int(2), .int(3)]))
  }

  @Test("DefineRecursive DSL body evaluates with depth tracking")
  func recursiveDSLEval() throws {
    let body: StateExpr = .ifThenElse(
      .equal(.setLiteral([]), .variable("S")),
      .tupleLiteral([]),
      .tupleConcatenate(
        .tupleLiteral([.any(from: .variable("S"))]),
        .recursiveCall(
          "SfS",
          [
            .setDifference(
              .variable("S"),
              .setLiteral([.any(from: .variable("S"))])
            )
          ])
      )
    )
    let fn = RecursiveFunc(name: "SfS", params: ["S"], body: body)
    let recursiveValue = try compiledValue(
      .recursiveCall("SfS", [.value(.set([.int(3), .int(1), .int(2)]))]),
      recursiveFunctions: [fn]
    )
    guard case .tuple(let values) = recursiveValue else {
      #expect(Bool(false))
      return
    }
    #expect(Set(values) == Set([.int(1), .int(2), .int(3)]))
  }

  @Test("nonterminating recursive operators stop at the recursion-depth limit")
  func nonterminatingRecursiveOperator() throws {
    let function = RecursiveFunc(
      name: "Loop",
      params: ["value"],
      body: .recursiveCall("Loop", [.variable("value")])
    )

    #expect(throws: EvalError.recursionDepthExceeded(4_096)) {
      try compiledValue(
        .recursiveCall("Loop", [.value(0)]),
        recursiveFunctions: [function]
      )
    }
  }

  @Test("TLAValue.function Comparable ordering")
  func functionComparable() {
    let small = TLAValue.function([.int(1): "a"])
    let large = TLAValue.function([.int(1): "a", .int(2): "b"])
    #expect(small < large)
    #expect(!(large < small))
  }

  @Test("typed function reads and updates lower structurally")
  func rawFunctionASTConstruction() {
    let phases = Var<Function<FunctionProcess, FunctionPhase>>("phases")
    #expect(phases[.first].raw == .functionApply(.variable("phases"), .value("first")))
    #expect(
      phases.updating(.first, to: FunctionPhase.done).raw
        == .except(.variable("phases"), .value("first"), .value("done")))
  }

  @Test("Function-typed variable works end-to-end in ModelChecker")
  func functionVariableEndToEnd() throws {
    let phases = Var<Function<FunctionProcess, FunctionPhase>>("phases")
    let process = Expr<FunctionProcess>(.variable("process"))
    let spec = TLASpec("FuncEndToEnd") {
      Variable(phases, Function<FunctionProcess, FunctionPhase>.literal(
        (.first, .initial), (.second, .initial)))
      Action(
        "process",
        parameters: [ActionParameter("process", values: FunctionProcess.allCases)]
      ) {
        phases.becomes(phases.updating(process, to: .done))
          .when(phases[process] == FunctionPhase.initial)
      }
    }
    if case .ok(let count) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50, symmetryReduction: .disabled)).check() {
      #expect(count >= 2)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("compiled execution handles function-typed variables")
  func functionTypeCompiledExecution() throws {
    let phases = Var<Function<FunctionProcess, FunctionPhase>>("phases")
    let spec = TLASpec("FuncGen") {
      Variable(phases, Function<FunctionProcess, FunctionPhase>.literal(
        (.first, .initial), (.second, .initial)))
      Action("init") {
        phases.becomes(Function<FunctionProcess, FunctionPhase>.mapping { _ in .done })
          .when(phases[.first] == FunctionPhase.initial)
      }
    }
    let compilation = try spec.compile()
    let action = try #require(compilation.layout.testActionID(named: "init"))
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let next = try #require(try CompiledRuntime(compilation: compilation)
      .successors(for: action, from: state)
      .first?.state)
    let phasesID = try #require(compilation.layout.testVariableID(named: "phases"))
    #expect(
      try next.value(for: phasesID).rendered(using: compilation.layout)
        == .function(["first": "done", "second": "done"]))
  }
}
