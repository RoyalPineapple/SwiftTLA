import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLAModels
import Testing
import UpstreamParity

// MARK: - .tlaModule: section coverage

@Suite(.serialized) struct TLAModuleMatrix {
  @Test func constantsAndAssume() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends("Naturals")
      Constant("N", 10)
      Assume(StateExpr.greaterOrEqual(.variable("N"), .value(.int(1))))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = spec.tlaModule
    #expect(tla.contains("CONSTANTS N"))
    #expect(tla.contains("ASSUME"))
  }

  @Test func fairnessWF() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("Next") { x.becomes(x + 1).when(x < 3) }
      WeakFairness("Next")
    }
    let tla = spec.tlaModule
    #expect(tla.contains("WF_x(Next)"))  // single var → no tuple brackets
  }

  @Test func generatedCfgReferencesNamedDefinitions() {
    let x = Var<Int>("x")
    let spec = TLASpec("Config") {
      Variable(x, 0)
      Action("Next") { x.becomes(x + 1).when(x < 2) }
      Invariant("TypeOK") { x >= 0 }
      Constraint(x <= 2)
      WeakFairness("Next")
    }

    #expect(spec.tlaCfg.contains("CONSTRAINT StateConstraint"))
    #expect(!spec.tlaCfg.contains("CONSTRAINT ("))
    #expect(!spec.tlaCfg.contains("WF_"))
  }

  @Test func generatedCfgAssignsConstants() {
    let x = Var<Int>("x")
    let spec = TLASpec("ConstantsConfig") {
      Constant("N", 3)
      Variable(x, 0)
    }

    #expect(spec.tlaCfg.contains("CONSTANT N = 3"))
  }

  @Test func theoremOutput() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
      Theorem("Spec => [](x >= 0)")
    }
    let tla = spec.tlaModule
    #expect(tla.contains("THEOREM"))
  }

  @Test func definitionsOutput() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Definition("Min(m,n) == IF m < n THEN m ELSE n")
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = spec.tlaModule
    #expect(tla.contains("Min(m,n) =="))
  }

  @Test func extendsNaturals() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends("Naturals")
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = spec.tlaModule
    #expect(tla.contains("EXTENDS Naturals"))
  }
}

// MARK: - .swiftSource: output coverage

@Suite(.serialized) struct SwiftSourceMatrix {
  @Test func roundTripStructure() {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Action("reset") { x.becomes(0) }
      Invariant("ok") { x >= 0 }
    }
    let src = spec.swiftSource
    #expect(src.contains("@TLAModel"))
    #expect(src.contains("struct Test"))
    #expect(src.contains("Action(\"inc\")"))
    #expect(src.contains("Action(\"reset\")"))
    #expect(src.contains("Invariant(\"ok\")"))
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
    #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 12)
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
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
    #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 16)
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
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
    #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 4)
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("CoffeeCan MaxBeanCount=5 = 20 states (parity catalog)")
  func coffeeCanMax5() throws {
    let count = try ModelChecker(spec: Example.coffeeCanMax5.spec, maxStates: 500)
      .exploreGraph().states.count
    #expect(count == 20)
  }

  @Test("Moving cat CatEvenBoxes = 48 states (parity catalog)")
  func movingCatEven() throws {
    let count = try ModelChecker(spec: Example.catEvenBoxes.spec, maxStates: 500)
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
    let r = try ModelChecker(spec: spec, maxStates: 100).check()
    if case .deadlocked(let s) = r { #expect(s["x"] == .int(1)) } else { #expect(Bool(false)) }
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
    let count = try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count
    #expect(count >= 1)
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("Multi-choose is Cartesian product")
  func multiChooseProduct() throws {
    let action: ActionExpr = .and(
      .chooseAction("x", .setLiteral([.value(.int(1)), .value(.int(2))])),
      .chooseAction("y", .setLiteral([.value(.int(10)), .value(.int(20))]))
    )
    let states = try ActionEnumerator.enumerate(
      action,
      from: ["x": .int(0), "y": .int(0)],
      varNames: ["x", "y"]
    )
    #expect(states.count == 4)
    let pairs = Set(states.map { "\($0["x"]!)-\($0["y"]!)" })
    #expect(pairs == Set(["1-10", "1-20", "2-10", "2-20"]))
  }
}

// MARK: - SpecRuntime: thin interpreter over ActionEnumerator/Evaluator

@Suite(.serialized) struct RuntimeTests {
  @Test("Runtime applies action and produces new state")
  func applyAction() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let rt = SpecRuntime(spec: spec)
    let state = rt.initialStates().first!
    let next = try rt.apply(.init(name: "Tick"), to: state)
    #expect(next["hr"] == .int(2))
  }

  @Test("Runtime checks invariants")
  func checkInvariant() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
      Invariant("Positive") { hr > 0 }
    }
    let rt = SpecRuntime(spec: spec)
    let state = rt.initialStates().first!
    #expect(try rt.check("Positive", in: state) == true)
  }

  @Test("Runtime lists available actions")
  func availableActions() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let rt = SpecRuntime(spec: spec)
    let state = rt.initialStates().first!
    let available = try rt.availableInvocations(in: state)
    #expect(available.contains(.init(name: "Tick")))
  }

  @Test("Runtime errors retain invocation and complete availability context")
  func runtimeErrorsRetainInvocationAndAvailabilityContext() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("RuntimeErrors") {
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step).when(counter == 0)
      }
    }
    let runtime = SpecRuntime(spec: spec)
    let initial = try #require(runtime.initialStates().first)
    let available = [
      TLAActionInvocation(name: "advance", arguments: [.int(1)]),
      TLAActionInvocation(name: "advance", arguments: [.int(2)])
    ]

    do {
      _ = try runtime.apply(.init(name: "advance", arguments: [.int(3)]), to: initial)
      Issue.record("Expected invalid arguments")
    } catch let error as SpecRuntime.RuntimeError {
      guard case .invalidActionArguments(let invocation, let actualAvailable) = error else {
        Issue.record("Expected invalidActionArguments, got \(error)")
        return
      }
      #expect(invocation == .init(name: "advance", arguments: [.int(3)]))
      #expect(actualAvailable == available)
    }

    let advanced = try runtime.apply(.init(name: "advance", arguments: [.int(1)]), to: initial)
    do {
      _ = try runtime.apply(.init(name: "advance", arguments: [.int(1)]), to: advanced)
      Issue.record("Expected disabled action")
    } catch let error as SpecRuntime.RuntimeError {
      guard case .actionNotEnabled(let invocation, let actualAvailable) = error else {
        Issue.record("Expected actionNotEnabled, got \(error)")
        return
      }
      #expect(invocation == .init(name: "advance", arguments: [.int(1)]))
      #expect(actualAvailable.isEmpty)
    }
  }

  @Test("Runtime reports availability evaluation failures with invocation context")
  func runtimePropagatesAvailabilityEvaluationFailures() throws {
    let counter = Var<Int>("counter")
    let spec = TLASpec("InvalidAvailability") {
      Variable(counter, 0)
      Action("advance") { counter.becomes(counter + 1).when(StateExpr.variable("missing")) }
    }
    let runtime = SpecRuntime(spec: spec)
    let state = runtime.initialStates().first!

    do {
      _ = try runtime.availableInvocations(in: state)
      Issue.record("Expected availability evaluation failure")
    } catch let error as SpecRuntime.RuntimeError {
      guard case .enumerationFailed(let requested, let evaluated, let underlying) = error else {
        Issue.record("Expected enumerationFailed, got \(error)")
        return
      }
      #expect(requested == nil)
      #expect(evaluated == .init(name: "advance"))
      guard case .undefinedVariable("missing") = underlying as? EvalError else {
        Issue.record("Expected missing-variable evaluator error, got \(underlying)")
        return
      }
    }

    do {
      _ = try runtime.apply(.init(name: "unknown"), to: state)
      Issue.record("Expected availability evaluation failure during application")
    } catch let error as SpecRuntime.RuntimeError {
      guard case .enumerationFailed(let requested, let evaluated, let underlying) = error else {
        Issue.record("Expected enumerationFailed, got \(error)")
        return
      }
      #expect(requested == .init(name: "unknown"))
      #expect(evaluated == .init(name: "advance"))
      guard case .undefinedVariable("missing") = underlying as? EvalError else {
        Issue.record("Expected missing-variable evaluator error, got \(underlying)")
        return
      }
    }
  }

  @Test("Runtime step validates + applies")
  func step() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, 1)
      Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }
    }
    let rt = SpecRuntime(spec: spec)
    let state = rt.initialStates().first!
    let result = try rt.step(.init(name: "Tick"), from: state)
    if case .ok(let next) = result {
      #expect(next["hr"] == .int(2))
    } else {
      #expect(Bool(false))
    }
  }
}

// MARK: - Checker self-proof: BFS invariants verified on our own checker

@Suite(.serialized) struct CheckerSelfProofTests {
  @Test("BFSExplorer model-checks with sets")
  func bfsExplorer1to1() throws {
    let result = try ModelChecker(spec: BFSExplorer.spec, maxStates: 200).check()
    switch result {
    case .ok(let count):
      #expect(count > 0)
    case .invariantViolated(let name, let state, let trace):
      print("Invariant \(name) violated at state: \(state)")
      for step in trace { print("  \(step)") }
      #expect(Bool(false), "Invariant \(name) violated")
    default:
      #expect(Bool(false), "Unexpected: \(result)")
    }
  }

  @Test("BFSExplorer TLA+ output structure")
  func bfsExplorerTLA() {
    let tla = BFSExplorer.spec.tlaModule
    #expect(tla.contains("q"))
    #expect(tla.contains("visited"))
    #expect(tla.contains("explored"))
    #expect(tla.contains("picked"))
  }

  @Test("Bootstrap composition: bfsChecker ⋊ user")
  func checkerComposition() throws {
    let counter = Var<Int>("counter")
    let userSpec = TLASpec("Counter") {
      Variable(counter, 0)
      Action("increment") { counter.becomes(counter + 1).when(counter < 10) }
      Invariant("counterNonNegative") { counter >= 0 }
    }
    let graph = try ModelChecker.compose(
      .bfsChecker(maxStates: 5),
      userSpec
    ).exploreGraph()
    #expect(graph.states.count > 0)
    #expect(graph.variableNames.contains("phase"))
    #expect(graph.variableNames.contains("processed"))
    #expect(graph.variableNames.contains("queued"))
    #expect(graph.variableNames.contains("counter"))
  }

  @Test("BFSChecker @TLAModel exposes SpecRuntime")
  func bfsCheckerRuntime() throws {
    let rt = BFSChecker.runtime
    let state = rt.initialStates().first!
    #expect(state["phase"] == .int(0))
    let next = try rt.apply(.init(name: "StepDiscover"), to: state)
    #expect(next["processed"] == .int(1))
  }

  @Test("checkComposed works with plain TLASpec")
  func checkComposedSpec() throws {
    let s1 = TLASpec("A") {
      let x = Var<Int>("x")
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 2) }
    }
    let result = try ModelChecker.checkComposed(
      checker: TLASpec.bfsChecker(maxStates: 10),
      user: s1,
      maxStates: 500
    )
    #expect({ if case .ok = result { true } else { false } }())
  }

  @Test("All explored states are reachable from initial")
  func reachability() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 4) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
    #expect(graph.states.count == 5)  // 0,1,2,3,4
    let values = Set(graph.states.values.compactMap { $0["x"] })
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
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
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
    let g = try ModelChecker(spec: spec, maxStates: 5).exploreGraph()
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
    if case .ok(let c) = try ModelChecker(spec: spec, maxStates: 100).check() {
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
    let s: [String: TLAValue] = ["x": .int(0), "y": .int(0), "z": .int(0)]
    let r = try ActionEnumerator.enumerate(a, from: s, varNames: ["x", "y", "z"])
    #expect(r.count == 3)
  }

  @Test("Deadlock when guard fails at init")
  func deadlockAtInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("T") {
      Variable(x, 0)
      Action("a") { x.becomes(2).when(x == 1) }
      DeadlockCheck()
    }
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
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
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
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
    let result = try ModelChecker(spec: spec, maxStates: 100).check()
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
    let g = try ModelChecker(spec: spec, maxStates: 1).exploreGraph()
    #expect(g.states.count <= 2)
  }
}
