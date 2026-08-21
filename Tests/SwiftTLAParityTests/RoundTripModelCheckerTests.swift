import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

private func compiledSuccessors(
  for action: ActionExpr,
  from values: [(String, TLAValue)]
) throws -> (CompiledSpecification, [CompiledState]) {
  let spec = TLASpec(
    name: "ActionExpressionFixture",
    variables: values.sorted { $0.0 < $1.0 }.map { NamedVar(name: $0.0, initial: $0.1) },
    actions: [NamedAction(name: "step", body: action)],
    invariants: []
  )
  let compilation = try spec.compile()
  let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
  let step = try #require(compilation.layout.actionID(named: "step"))
  let states = try CompiledRuntime(compilation: compilation).successors(for: step, from: initial).map(\.state)
  return (compilation, states)
}

private func value(
  named name: String,
  in state: CompiledState,
  compilation: CompiledSpecification
) throws -> TLAValue {
  let variable = try #require(compilation.layout.variableID(named: name))
  return try state.value(for: variable).rendered(using: compilation.layout)
}

// MARK: - TLA+ module: section coverage

@Suite(.serialized) struct TLAModuleMatrix {
  @Test func constantsAndAssume() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends(.naturals)
      Constant("N", 10)
      Assume(StateExpr.greaterOrEqual(.variable("N"), .value(.int(1))))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("CONSTANTS N"))
    #expect(tla.contains("ASSUME"))
  }

  @Test func fairnessWF() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("advance") { x.becomes(x + 1).when(x < 3) }
      WeakFairnessNext()
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("WF_x(Next)"))  // single var → no tuple brackets
  }

  @Test func generatedCfgReferencesNamedDefinitions() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Config") {
      Variable(x, 0)
      Action("advance") { x.becomes(x + 1).when(x < 2) }
      Invariant("TypeOK") { x >= 0 }
      Constraint(x <= 2)
      WeakFairnessNext()
    }

    #expect(try spec.compile().renderedTLAModuleBundle().cfg.contains("CONSTRAINT StateConstraint"))
    #expect(!(try spec.compile().renderedTLAModuleBundle().cfg.contains("CONSTRAINT (")))
    #expect(!(try spec.compile().renderedTLAModuleBundle().cfg.contains("WF_")))
  }

  @Test func generatedCfgAssignsConstants() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("ConstantsConfig") {
      Constant("N", 3)
      Variable(x, 0)
    }

    #expect(try spec.compile().renderedTLAModuleBundle().cfg.contains("CONSTANT N = 3"))
  }

  @Test func theoremOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
      Theorem(name: "Safety", always: x >= 0)
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("THEOREM"))
  }

  @Test func definitionsOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      FormalDefinition("Min", parameters: [.value("m"), .value("n")], body: .ifThenElse(.lessThan(.variable("m"), .variable("n")), .variable("m"), .variable("n")))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("Min(m, n) =="))
  }

  @Test func extendsNaturals() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends(.naturals)
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("EXTENDS Naturals"))
  }
}

// MARK: - Core example parity (same shapes as Examples/)

@Suite(.serialized) struct GoldenTests {
  @Test("HourClock = 12 states")
  func hourClock12() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("HCnxt") {
        (hr != 12) && hr.becomes(hr + 1) || (hr == 12) && hr.becomes(1)
      }
      Invariant("HCini") { hr >= 1 && hr <= 12 }
    }
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph().states.count == 12)
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("DieHard = 16 states")
  func dieHard16() throws {
    let big = Var<Int>("big")
    let small = Var<Int>("small")
    let spec = TLASpec("DieHard") {
      Variable(big, 0)
      Variable(small, 0)
      Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
      Action("FillSmallJug") { small.becomes(3) }
      Action("FillBigJug") { big.becomes(5) }
      Action("EmptySmallJug") { small.becomes(0) }
      Action("EmptyBigJug") { big.becomes(0) }
      Action("SmallToBig") {
        (big + small <= 5) && big.becomes(big + small) && small.becomes(0)
          || (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
      }
      Action("BigToSmall") {
        (big + small <= 3) && small.becomes(big + small) && big.becomes(0)
          || (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
      }
    }
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph().states.count == 16)
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("Allocator = 4 states")
  func allocator4() throws {
    let a = Var<Int>("available")
    let b = Var<Int>("allocated")
    let spec = TLASpec("allocator") {
      Variable(a, 3)
      Variable(b, 0)
      Action("Allocate") { a.becomes(a - 1).when(a > 0) && b.becomes(b + 1) }
      Action("Deallocate") { a.becomes(a + 1).when(b > 0) && b.becomes(b - 1) }
      Invariant("ResourceCount") { a + b == 3 }
    }
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph().states.count == 4)
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("CoffeeCan MaxBeanCount=5 = 20 states (parity catalog)")
  func coffeeCanMax5() throws {
    let count = try ModelChecker(compilation: try Example.coffeeCanMax5.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500))
      .exploreGraph().states.count
    #expect(count == 20)
  }

  @Test("Moving cat CatEvenBoxes = 48 states (parity catalog)")
  func movingCatEven() throws {
    let count = try ModelChecker(compilation: try Example.catEvenBoxes.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500))
      .exploreGraph().states.count
    #expect(count == 48)
  }

  @Test("Deadlock detected with DeadlockCheck()")
  func deadlock() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("once") { x.becomes(1).when(x == 0) }
      DeadlockCheck()
    }
    let r = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    if case .deadlocked(let state) = r {
      let token = try #require(TLAStateProjection.Token(validating: "x"))
      #expect(state.value(for: token) == .int(1))
    } else {
      #expect(Bool(false))
    }
  }

  @Test("Majority Boyer-Moore shape explores")
  func majority() throws {
    let cand = Var<Int>("cand")
    let cnt = Var<Int>("cnt")
    let i = Var<Int>("i")
    let spec = TLASpec("Majority") {
      Variable(cand, 0)
      Variable(cnt, 0)
      Variable(i, 1)
      Invariant("TypeOK") {
        i >= 1 && i <= 4 && cand >= 0 && cand <= 3 && cnt >= 0 && cnt <= 3
      }
      Action("Next") {
        (i <= 3) && i.becomes(i + 1)
          && (cnt == 0 && cand.becomes(i) && cnt.becomes(1)
            || cnt != 0 && cand == i && cnt.becomes(cnt + 1)
            || cnt != 0 && cand != i && cnt.becomes(cnt - 1))
      }
    }
    let count = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph().states.count
    #expect(count >= 1)
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("Multi-choose is Cartesian product")
  func multiChooseProduct() throws {
    let action: ActionExpr = .and(
      .chooseAction("x", .setLiteral([.value(.int(1)), .value(.int(2))])),
      .chooseAction("y", .setLiteral([.value(.int(10)), .value(.int(20))]))
    )
    let (compilation, states) = try compiledSuccessors(
      for: action,
      from: [("x", .int(0)), ("y", .int(0))]
    )
    #expect(states.count == 4)
    let pairs = try Set(states.map {
      "\(try value(named: "x", in: $0, compilation: compilation))-\(try value(named: "y", in: $0, compilation: compilation))"
    })
    #expect(pairs == Set(["1-10", "1-20", "2-10", "2-20"]))
  }
}

// MARK: - Compiled execution

@Suite(.serialized) struct CompiledExecutionTests {
  private func successor(
    _ compilation: CompiledSpecification,
    named name: String,
    arguments: [TLAValue] = [],
    from state: TLAStateProjection
  ) throws -> TLAStateProjection {
    let action = try #require(compilation.layout.actionID(named: name))
    return try #require(try compilation.successors(for: action, arguments: arguments, from: state).first)
  }

  private func successors(
    _ compilation: CompiledSpecification,
    from state: TLAStateProjection
  ) throws -> [(action: String, arguments: [TLAValue], state: TLAStateProjection)] {
    let formalState = try CompiledState(projection: state, compilation: compilation)
    return try CompiledRuntime(compilation: compilation)
      .successors(from: formalState)
      .map { successor in
        (
          action: compilation.layout.actions[successor.action.ordinal].declaration.name,
          arguments: successor.arguments,
          state: try successor.state.projection(using: compilation.layout)
        )
      }
  }

  private func value(_ name: String, in state: TLAStateProjection) throws -> TLAValue {
    guard let token = TLAStateProjection.Token(validating: name),
          let value = state.value(for: token) else {
      throw TLAStateProjectionDiagnostic.missingValue(path: name)
    }
    return value
  }

  @Test("compiled execution applies an action")
  func applyAction() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let compilation = try spec.compile()
    let state = try #require(try compilation.initialStateProjections().first)
    let next = try successor(compilation, named: "Tick", from: state)
    #expect(try value("hr", in: next) == .int(2))
  }

  @Test("compiled execution checks invariants")
  func checkInvariant() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
      Invariant("Positive") { hr > 0 }
    }
    let compilation = try spec.compile()
    let state = try #require(try compilation.initialStateProjections().first)
    #expect(compilation.propertyOutcomes(in: state) == [.satisfied(name: "Positive")])
  }

  @Test("compiled execution lists available actions")
  func availableActions() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let compilation = try spec.compile()
    let state = try #require(try compilation.initialStateProjections().first)
    let available = try successors(compilation, from: state).map(\.action)
    #expect(available.contains("Tick"))
  }

  @Test("compiled successor relation matches checked transitions from every reachable state")
  func runtimeSuccessorsMatchCheckedTransitions() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("ConstrainedParameterizedCounter") {
      Constant("limit", 2)
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step)
      }
      Constraint(counter <= StateExpr.value(.constant("limit")))
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: .standard).exploreGraph()
    let compilation = try spec.compile()

    for (sourceID, source) in graph.states {
      let checked = (graph.transitions[sourceID] ?? []).compactMap { transition -> (action: String, arguments: [TLAValue], state: TLAStateProjection)? in
        guard let successor = graph.states[transition.target] else { return nil }
        return (transition.label.action, transition.label.arguments, successor)
      }
      let runtimeSuccessors = try successors(compilation, from: source)

      #expect(multiset(runtimeSuccessors) == multiset(checked))
    }
  }

  private func multiset(
    _ transitions: [(action: String, arguments: [TLAValue], state: TLAStateProjection)]
  ) -> [String: Int] {
    Dictionary(
      transitions.map { ("\($0.action):\($0.arguments) -> \($0.state)", 1) },
      uniquingKeysWith: +
    )
  }

  @Test("compiled execution preserves parameter domains and disabled successors")
  func compiledExecutionPreservesParameterDomainsAndDisabledSuccessors() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("RuntimeErrors") {
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step).when(counter == 0)
      }
    }
    let compilation = try spec.compile()
    let initial = try #require(try compilation.initialStateProjections().first)
    let available = [
      (action: "advance", arguments: [.int(1)]),
      (action: "advance", arguments: [.int(2)])
    ]

    #expect(try successors(compilation, from: initial).map { ($0.action, $0.arguments) } == available)

    let advanced = try successor(compilation, named: "advance", arguments: [.int(1)], from: initial)
    let action = try #require(compilation.layout.actionID(named: "advance"))
    #expect(try compilation.successors(for: action, arguments: [.int(1)], from: advanced).isEmpty)
    #expect(try compilation.successors(for: action, arguments: [.int(3)], from: initial).isEmpty)
  }

  @Test("free action reference blocks compilation")
  func freeActionReferenceBlocksCompilation() {
    let counter = Var<Int>("counter")
    let spec = TLASpec("InvalidAvailability") {
      Variable(counter, 0)
      Action("advance") { counter.becomes(counter + 1).when(StateExpr.variable("missing")) }
    }
    do {
      _ = try spec.compile()
      Issue.record("Expected a binding diagnostic")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .unknownReference)
      #expect(diagnostic.stage == .binding)
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }

  @Test("compiled execution applies a declared action")
  func appliesDeclaredAction() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let compilation = try spec.compile()
    let state = try #require(try compilation.initialStateProjections().first)
    let next = try successor(compilation, named: "Tick", from: state)
    #expect(try value("hr", in: next) == .int(2))
  }
}

@Suite(.serialized) struct CheckerSelfProofTests {
  @Test("All explored states are reachable from initial")
  func reachability() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 4) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph.states.count == 5)  // 0,1,2,3,4
    let values = try Set(graph.states.values.compactMap { try value("x", in: $0) })
    #expect(values == Set([.int(0), .int(1), .int(2), .int(3), .int(4)]))
  }

  @Test("No transition targets unknown states")
  func noDanglingTransitions() throws {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    let spec = TLASpec("Test") {
      Variable(a, 0)
      Variable(b, 0)
      Action("incA") { a.becomes(a + 1).when(a < 3) }
      Action("incB") { b.becomes(b + 1).when(b < 3) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    for (_, ts) in graph.transitions {
      for t in ts {
        #expect(graph.states[t.target] != nil)
      }
    }
  }

  @Test("States <= maxStates + 1 (stops after processing)")
  func maxStatesBound() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1) }
    }
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5)).exploreGraph()
    // maxStates limits processed, last state may discover one extra
    #expect(g.states.count <= 5 + 1)
  }

  @Test("Invariant checked on all states")
  func invariantChecked() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("nonNeg") { x >= 0 }
    }
    if case .ok(let c) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check() {
      #expect(c == 6)
    } else {
      #expect(Bool(false))
    }
  }
}

@Suite(.serialized) struct EdgeCaseTests {
  @Test("3-level nested OR in AND")
  func nestedOrL3() throws {
    let a: ActionExpr = .and(
      .assign("x", .value(.int(1))),
      .or(
        .or(.assign("y", .value(.int(2))), .assign("y", .value(.int(3)))),
        .assign("y", .value(.int(4))))
    )
    let (_, successors) = try compiledSuccessors(
      for: a,
      from: [("x", .int(0)), ("y", .int(0)), ("z", .int(0))]
    )
    #expect(successors.count == 3)
  }

  @Test("Deadlock when guard fails at init")
  func deadlockAtInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(2).when(x == 1) }
      DeadlockCheck()
    }
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    var dead = false
    if case .deadlocked = result { dead = true } else { dead = false }
    #expect(dead)
  }

  @Test("Deadlock at terminal linear state")
  func deadlockTerminal() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(x + 1).when(x < 2) }
      DeadlockCheck()
    }
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    var val: TLAValue = .int(-1)
    if case .deadlocked(let s) = result { val = s["x"] ?? .int(-1) }
    #expect(val == .int(2))
  }

  @Test("No deadlock on cyclic spec")
  func noDeadlockCyclic() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes((x + 1) % 2) }
      DeadlockCheck()
    }
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    var ok = false
    if case .ok = result { ok = true }
    #expect(ok)
  }

  @Test("maxStates=1 bounds state count")
  func maxStatesOne() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(x + 1) }
    }
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1)).exploreGraph()
    #expect(g.states.count <= 2)
  }
}

@Suite(.serialized) struct CompiledExpressionEvaluationTests {
  @Test("CHOOSE + functionApply + EXCEPT in single action enumerates correctly")
  func chooseWithFunctionApply() throws {
    let chosenProcess: ActionExpr = .chooseAction(
      "process", .setLiteral([.value(.int(1)), .value(.int(2))]))
    let readState: ActionExpr = .guard_(
      .equal(
        .functionApply(.variable("programCounter"), .variable("process")),
        .value(.string("initial"))
      ))
    let updateState: ActionExpr = .assign(
      "programCounter",
      .except(.variable("programCounter"), .variable("process"), .value(.string("done")))
    )
    let unchanged: ActionExpr = .unchanged("sent")
    let action = ActionExpr.and(
      chosenProcess, ActionExpr.and(readState, ActionExpr.and(updateState, unchanged)))
    let (compilation, successors) = try compiledSuccessors(for: action, from: [
      ("programCounter", .function([.int(1): "initial", .int(2): "initial"])),
      ("sent", .set([])),
      ("process", .int(0))
    ])
    #expect(successors.count == 2)
    for s in successors {
      let pc = try value(named: "programCounter", in: s, compilation: compilation)
      let proc = try value(named: "process", in: s, compilation: compilation)
      guard case .function(let mapping) = pc else {
        #expect(Bool(false))
        return
      }
      if case .int(1) = proc {
        #expect(mapping[.int(1)] == "done")
        #expect(mapping[.int(2)] == "initial")
      }
    }
  }

  @Test("RecursiveFunction builtins evaluate correctly")
  func recursiveBuiltins() throws {
    let result = try compiledValue(.recursiveCall(
      "SeqFromSet", [.value(.set([.int(3), .int(1), .int(2)]))]
    ))
    #expect(result == .tuple([.int(1), .int(2), .int(3)]))
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
    let result = try compiledValue(
      .recursiveCall("SfS", [.value(.set([.int(3), .int(1), .int(2)]))]),
      recursiveFunctions: [fn]
    )
    guard case .tuple(let tv) = result else {
      #expect(Bool(false))
      return
    }
    #expect(Set(tv) == Set([.int(1), .int(2), .int(3)]))
  }

  @Test("TLAValue.function Comparable ordering")
  func functionComparable() {
    let small = TLAValue.function([.int(1): "a"])
    let large = TLAValue.function([.int(1): "a", .int(2): "b"])
    #expect(small < large)
    #expect(!(large < small))
  }

  @Test("raw function AST construction remains explicit")
  func rawFunctionASTConstruction() {
    let rawFunction = Var<TLAValue>("rawFunction")
    let selfProcess = Var<Int>("self")
    let read = StateExpr.functionApply(rawFunction.stateExpr, selfProcess.stateExpr)
    let result = StateExpr.except(rawFunction.stateExpr, selfProcess.stateExpr, .value(.string("done")))
    #expect(read == .functionApply(.variable("rawFunction"), .variable("self")))
    let expected: StateExpr = .except(.variable("rawFunction"), .variable("self"), .value(.string("done")))
    #expect(result == expected)
  }

  @Test("Function-typed variable works end-to-end in ModelChecker")
  func functionVariableEndToEnd() throws {
    let programCounter = Var<TLAValue>("programCounter")
    let selfProcess = Var<Int>("selfProcess")
    let spec = TLASpec("FuncEndToEnd") {
      Variable(programCounter, TLAValue.function([.int(1): "initial", .int(2): "initial"]))
      Variable(selfProcess, 0)
      Action("process") {
        choose(selfProcess, from: StateExpr.set([1, 2]))
          && StateExpr.functionApply(programCounter.stateExpr, selfProcess.stateExpr) == "initial"
          && .assign(
            programCounter.name,
            .except(programCounter.stateExpr, selfProcess.stateExpr, .value(.string("done")))
          )
      }
    }
    if case .ok(let count) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50)).check() {
      #expect(count >= 2)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("compiled execution handles function-typed variables")
  func functionTypeCompiledExecution() throws {
    let programCounter = Var<TLAValue>("programCounter")
    let spec = TLASpec("FuncGen") {
      Variable(programCounter, TLAValue.function([:]))
      Action("init") {
        let domain = StateExpr.set([1])
        let p = Var<Int>("p")
        let fun = StateExpr.functionLiteral(p, in: domain, "ready")
        programCounter.becomes(Expr<TLAValue>(fun)).when(
          programCounter.stateExpr.domain.cardinality == 0)
      }
    }
    let compilation = try spec.compile()
    let action = try #require(compilation.layout.actionID(named: "init"))
    let state = try #require(try compilation.initialStateProjections().first)
    let next = try #require(try compilation.successors(for: action, arguments: [], from: state).first)
    let programCounter = try #require(TLAStateProjection.Token(validating: "programCounter"))
    if next.value(for: programCounter) == nil {
      Issue.record("Expected programCounter in successor")
    }
  }
}
