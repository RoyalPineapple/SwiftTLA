import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

private enum FunctionProcess: String, CaseIterable, FiniteTLAValueDomain {
  case first
  case second

  static let finiteValues = allCases
  static let defaultValue = FunctionProcess.first
}

private enum FunctionPhase: String, CaseIterable, FiniteTLAValueDomain {
  case initial
  case done

  static let finiteValues = allCases
  static let defaultValue = FunctionPhase.initial
}

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
  let step = try #require(compilation.layout.testActionID(named: "step"))
  let states = try CompiledRuntime(compilation: compilation).successors(for: step, from: initial).map(\.state)
  return (compilation, states)
}

private func value(
  named name: String,
  in state: CompiledState,
  compilation: CompiledSpecification
) throws -> TLAValue {
  let variable = try #require(compilation.layout.testVariableID(named: name))
  return try state.value(for: variable).rendered(using: compilation.layout)
}

@Suite(.serialized)
struct ModelCheckOutcomeTests {
  private func checker(_ specification: TLASpec) throws -> ModelChecker {
    try ModelChecker(
      compilation: specification.compile(),
      configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
    )
  }

  @Test("an empty initial-state relation has a typed outcome")
  func emptyInitialStateRelation() throws {
    let value = Var<Int>("value")
    let outcome = try checker(TLASpec("EmptyInitialStateRelation") {
      Variable(value, in: [Int]())
    }).check()

    guard case .noInitialStates = outcome else {
      Issue.record("Expected noInitialStates, received \(outcome)")
      return
    }
    #expect(outcome.diagnostic?.kind == .initialState)
  }

  @Test("a false compiled assumption has a typed outcome")
  func falseCompiledAssumption() throws {
    let value = Var<Int>("value")
    let outcome = try checker(TLASpec("FalseCompiledAssumption") {
      Assume(false)
      Variable(value, 0)
    }).check()

    guard case .assumptionViolated = outcome else {
      Issue.record("Expected assumptionViolated, received \(outcome)")
      return
    }
    #expect(outcome.diagnostic?.kind == .assumption)
  }
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

  @Test func invariantOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
      Invariant("Safety") { x >= 0 }
    }
    let bundle = try spec.compile().renderedTLAModuleBundle()
    #expect(bundle.tla.contains("Safety == (x >= 0)"))
    #expect(bundle.cfg.contains("INVARIANT Safety"))
  }

  @Test func definitionsOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      FormalDefinition("Min", parameters: [.value("m"), .value("n")], body: .ifThenElse(.lessThan(.variable("m"), .variable("n")), .variable("m"), .variable("n")))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("Min(m, n) == (IF (m < n) THEN m ELSE n)"))
  }

  @Test func extendsNaturals() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends(.naturals)
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("Naturals"))
  }
}

@Suite(.serialized) struct ReachableGraphContractTests {
  @Test("HourClock canonical model has its declared reachable graph")
  func hourClockCanonicalGraph() throws {
    let fixture = Example.hourClock
    let graph = try ModelChecker(
      compilation: fixture.spec.compile(),
      configuration: try .init(maximumStateLimit: fixture.maximumStateLimit, symmetryReduction: .disabled)
    ).exploreGraph()
    #expect(graph.states.count == fixture.expectedDistinct)
  }

  @Test("DieHard canonical model has its declared reachable graph")
  func dieHardCanonicalGraph() throws {
    let fixture = Example.dieHardTypeOK
    let graph = try ModelChecker(
      compilation: fixture.spec.compile(),
      configuration: try .init(maximumStateLimit: fixture.maximumStateLimit, symmetryReduction: .disabled)
    ).exploreGraph()
    #expect(graph.states.count == fixture.expectedDistinct)
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
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph().states.count == 4)
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = checkOutcome { true } else { false } }())
  }

  @Test("CoffeeCan MaxBeanCount=5 = 20 states (parity catalog)")
  func coffeeCanMax5() throws {
    let count = try ModelChecker(compilation: try Example.coffeeCanMax5.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled))
      .exploreGraph().states.count
    #expect(count == 20)
  }

  @Test("Chameneos has every typed initial creature-color assignment")
  func chameneosInitialStates() throws {
    let compilation = try Example.chameneosM4N4.spec.compile()
    let states = try CompiledRuntime(compilation: compilation).initialStates()
    #expect(states.count == 81)
  }

  @Test("Moving cat CatEvenBoxes = 48 states (parity catalog)")
  func movingCatEven() throws {
    let count = try ModelChecker(compilation: try Example.catEvenBoxes.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled))
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
    let r = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
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
    let count = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph().states.count
    #expect(count >= 1)
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = checkOutcome { true } else { false } }())
  }

  @Test("Multi-choose is Cartesian product")
  func multiChooseProduct() throws {
    let action: ActionExpr = .and(
      .chooseAction(.named("x"), .setLiteral([.value(.int(1)), .value(.int(2))])),
      .chooseAction(.named("y"), .setLiteral([.value(.int(10)), .value(.int(20))]))
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
    from state: CompiledState
  ) throws -> CompiledState {
    let action = try #require(compilation.layout.testActionID(named: name))
    return try #require(try CompiledRuntime(compilation: compilation)
      .successors(for: action, from: state)
      .first { successor in
        try successor.arguments.map { try $0.rendered(using: compilation.layout) } == arguments
      }?.state)
  }

  private func successors(
    _ compilation: CompiledSpecification,
    from state: CompiledState
  ) throws -> [(action: String, arguments: [TLAValue], state: TLAStateProjection)] {
    return try CompiledRuntime(compilation: compilation)
      .successors(from: state)
      .map { successor in
        (
          action: compilation.layout.actions[successor.action.ordinal].declaration.name,
          arguments: try successor.arguments.map { try $0.rendered(using: compilation.layout) },
          state: try successor.state.projection(using: compilation.layout)
        )
      }
  }

  private func value(
    _ name: String,
    in state: CompiledState,
    compilation: CompiledSpecification
  ) throws -> TLAValue {
    let variable = try #require(compilation.layout.testVariableID(named: name))
    return try state.value(for: variable).rendered(using: compilation.layout)
  }

  @Test("compiled execution applies an action")
  func applyAction() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("IncrementingCounter") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let next = try successor(compilation, named: "increment", from: state)
    #expect(try value("count", in: next, compilation: compilation) == .int(2))
  }

  @Test("compiled execution checks invariants")
  func checkInvariant() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("PositiveCounter") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
      Invariant("Positive") { count > 0 }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let invariant = try #require(compilation.semantics.invariants.first)
    #expect(try CompiledRuntime(compilation: compilation).invariantHolds(invariant, in: state))
  }

  @Test("compiled execution lists available actions")
  func availableActions() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("AvailableAction") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let available = try successors(compilation, from: state).map(\.action)
    #expect(available.contains("increment"))
  }

  @Test("compiled successor relation matches checked transitions from every reachable state")
  func runtimeSuccessorsMatchCheckedTransitions() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("ConstrainedParameterizedCounter") {
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step)
      }
      Constraint(counter <= 2)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
    ).explore()
    let graph = exploration.graph

    for sourceID in graph.states.keys {
      let checked = try (graph.transitions[sourceID] ?? []).compactMap { transition -> (action: String, arguments: [TLAValue], state: TLAStateProjection)? in
        guard let successor = graph.states[transition.target] else { return nil }
        return (
          transition.label.action,
          try transition.label.formalArguments(using: compilation.layout),
          successor
        )
      }
      let runtimeState = try #require(exploration.compiledStates[sourceID])
      let runtimeSuccessors = try successors(compilation, from: runtimeState)

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
    let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let available: [(action: String, arguments: [TLAValue])] = [
      (action: "advance", arguments: [.int(1)]),
      (action: "advance", arguments: [.int(2)])
    ]

    let discovered = try successors(compilation, from: initial)
    #expect(discovered.count == available.count)
    for (actual, expected) in zip(discovered, available) {
      #expect(actual.action == expected.action)
      #expect(actual.arguments == expected.arguments)
    }

    let advanced = try successor(compilation, named: "advance", arguments: [.int(1)], from: initial)
    let action = try #require(compilation.layout.testActionID(named: "advance"))
    let runtime = CompiledRuntime(compilation: compilation)
    #expect(try runtime.successors(for: action, from: advanced).contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) } == [.int(1)]
    } == false)
    #expect(try runtime.successors(for: action, from: initial).contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) } == [.int(3)]
    } == false)
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

}

@Suite(.serialized) struct CheckerSelfProofTests {
  @Test("Exploration rejects non-positive resource limits")
  func rejectsNonPositiveResourceLimits() {
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(0)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: 0,
        symmetryReduction: .disabled)
    }
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(-1)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: -1,
        symmetryReduction: .disabled)
    }
    #expect(throws: FiniteExplorationConfigurationError.nonPositivePermutationLimit(0)) {
      _ = try FiniteExplorationConfiguration(
        maximumStateLimit: 1,
        symmetryReduction: .enabled(maximumPermutationCount: 0))
    }
  }

  @Test("All explored states are reachable from initial")
  func reachability() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 4) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
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
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5, symmetryReduction: .disabled)).exploreGraph()
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
    if case .ok(let c) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check() {
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
      .assign(.named("x"), .value(.int(1))),
      .or(
        .or(.assign(.named("y"), .value(.int(2))), .assign(.named("y"), .value(.int(3)))),
        .assign(.named("y"), .value(.int(4))))
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
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    var dead = false
    if case .deadlocked = checkOutcome { dead = true } else { dead = false }
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
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    let xToken = try #require(TLAStateProjection.Token(validating: "x"))
    var val: TLAValue = .int(-1)
    if case .deadlocked(let state) = checkOutcome { val = state.value(for: xToken) ?? .int(-1) }
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
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    var ok = false
    if case .ok = checkOutcome { ok = true }
    #expect(ok)
  }

  @Test("maxStates=1 bounds state count")
  func maxStatesOne() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(x + 1) }
    }
    let g = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1, symmetryReduction: .disabled)).exploreGraph()
    #expect(g.states.count <= 2)
  }
}

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
