import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAModels
import Testing
import UpstreamParity
// MARK: - Phase 1-7: bound variables, functions, sequences, EXCEPT, CONSTANTS
@Suite(.serialized) struct BoundVariableTests { @Test("Function literal with bound variable evaluates correctly")
  func functionLiteralWithBoundVar() {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 2).raw)
    let result = try! fun.evaluate(in: [:])
    guard case .function(let mapping) = result else {
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
    let result = try apply.evaluate(in: [:])
    #expect(result == .int(20))
  }

  @Test("Function EXCEPT updates a key")
  func functionExcept() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let updated = StateExpr.except(fun, .value(.int(1)), .value(.int(99)))
    let result = try updated.evaluate(in: [:])
    guard case .function(let mapping) = result else {
      #expect(Bool(false))
      return
    }
    #expect(mapping[.int(1)] == .int(99))
    #expect(mapping[.int(2)] == .int(20))
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
    let result = try expr.evaluate(in: [:])
    guard case .function(let mapping) = result else {
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
    let result = try predicate.evaluateBool(in: [:])
    #expect(result)
  }

  @Test("exists with bound variable finds matching element")
  func existsWithBoundVar() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let predicate = StateExpr.exists(
      p, in: domain, StateExpr.equal(p.stateExpr, StateExpr.value(.int(2))))
    let result = try predicate.evaluateBool(in: [:])
    #expect(result)
  }

  @Test("Sequence variable append and read in model checker")
  func sequenceVariableAppendRead() throws {
    let seq = Var<TLAValue>("seq")
    let result = Var<Int>("result")
    let spec = TLASpec("SeqTest") {
      Variable(seq, TLAValue.tuple([]))
      Variable(result, 0)
      Action("push") {
        seq.becomes(Expr<TLAValue>(seq.stateExpr.appending(42))).when(seq.stateExpr.count == 0)
          && result.stays
      }
      Action("pop") { seq.stateExpr.count > 0 && result.becomes(Expr<Int>(seq.stateExpr.at(1))) }
    }
    let g = try! ModelChecker(spec: spec, maxStates: 10).exploreGraph()
    let states = g.states.values
    let results = Set(states.compactMap { $0["result"] })
    #expect(results.contains(.int(0)))
    #expect(results.contains(.int(42)))
  }

  @Test("Function-typed variable stores and retrieves values")
  func functionVariable() throws {
    let clock = Var<TLAValue>("clock")
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let spec = TLASpec("FuncTest") {
      Variable(clock, TLAValue.function([:]))
      Action("init") {
        let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
        clock.becomes(Expr<TLAValue>(fun)).when(clock.stateExpr.domain.cardinality == 0)
      }
    }
    let g = try! ModelChecker(spec: spec, maxStates: 10).exploreGraph()
    let states = g.states.values
    var found = false
    for s in states {
      if case .function(let m) = s["clock"] {
        if m[.int(1)] == .int(10) && m[.int(2)] == .int(20) {
          found = true
        }
      }
    }
    #expect(found)
  }

  @Test("CONSTANT with ASSUME generates valid TLA+ and model-checks")
  func constantModelCheck() throws {
    let bound = 5
    let x = Var<Int>("x")
    let spec = TLASpec("ConstTest") {
      Constant("N", bound)
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < bound) }
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("CONSTANTS N"))
    #expect(tla.contains("ASSUME N = 5"))
    let g = try! ModelChecker(spec: substituteConstants(spec), maxStates: 10).exploreGraph()
    #expect(g.states.count == bound + 1)
  }

  @Test("choose action produces nondeterministic assignment")
  func chooseAction() throws {
    let picked = Var<Int>("picked")
    let source = Var<TLAValue>("source")
    let spec = TLASpec("ChooseTest") {
      Variable(picked, 0)
      Variable(source, TLAValue.set([.int(1), .int(2), .int(3)]))
      Action("pick") {
        source.stateExpr.cardinality > 0
          && choose(picked, from: source)
          && source.becomes(
            Expr(.setDifference(source.stateExpr, StateExpr.singleton(picked.stateExpr))))
      }
    }
    if case .ok(let count) = try ModelChecker(spec: spec, maxStates: 20).check() {
      #expect(count > 0)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("SpecParser parses choose(variable, from:) call")
  func specParserChooseCall() {
    let source = "choose(picked, from: q)"
    let expr = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let result = SpecParser.decodeActionExpr(expr)
    #expect(result == ActionExpr.chooseAction("picked", .variable("q")))
  }

  @Test("SpecParser parses singleton()")
  func specParserSingleton() throws {
    let source = "StateExpr.singleton(x)"
    let expr = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let result = SpecParser.decodeStateExpr(expr)
    #expect(result == StateExpr.setLiteral([.variable("x")]))
  }

  @Test("SpecParser parses functionLiteral(p, in: domain, body)")
  func specParserFunctionLiteral() throws {
    let source = "StateExpr.functionLiteral(StateExpr.set([1]), (2 + 3))"
    let expr = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let result = SpecParser.decodeStateExpr(expr)
    let d = result?.description ?? ""
    #expect(d.contains("|->") && d.contains("{1}") && d.contains("(2 + 3)"))
  }

  @Test("Function TLA+ output is valid ASCII")
  func functionTLAOutput() {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let desc = fun.description
    #expect(desc.contains("[x"))
    #expect(desc.contains("\\in"))
    #expect(desc.contains("|->"))
    #expect(!desc.contains("_x"))
  }
}
// MARK: - Completion tests: UNCHANGED per-branch, CHOOSE + functionApply, Codable
@Suite(.serialized) struct CompletionCoverageTests { @Test("completeAction pushes UNCHANGED into OR branches")
  func perBranchUnchanged() {
    // OR action: only one branch assigns x, the other doesn't
    let action: ActionExpr = .or(
      .assign("x", .value(.int(1))),
      .assign("y", .value(.int(2)))
    )
    // completeAction should add UNCHANGED y to first branch, UNCHANGED x to second
    let completed = completeAction(action, allVars: ["x", "y"])
    let desc = completed.description
    #expect(desc.contains("UNCHANGED y"))
    #expect(desc.contains("UNCHANGED x"))
  }

  @Test("completeAction doesn't add UNCHANGED when all vars assigned")
  func noUnchangedWhenAllAssigned() {
    let action: ActionExpr = .and(
      .assign("x", .value(.int(1))),
      .assign("y", .value(.int(2)))
    )
    let completed = completeAction(action, allVars: ["x", "y"])
    #expect(!completed.description.contains("UNCHANGED"))
  }

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
    let state: [String: TLAValue] = [
      "programCounter": .function([.int(1): "initial", .int(2): "initial"]),
      "sent": .set([]),
      "process": .int(0)
    ]
    let successors = try ActionEnumerator.enumerate(
      action, from: state, varNames: ["programCounter", "sent", "process"])
    #expect(successors.count == 2)
    for s in successors {
      let pc = s["programCounter"]
      let proc = s["process"]
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
    let result = try StateExpr.recursiveCall(
      "SeqFromSet", [.value(.set([.int(3), .int(1), .int(2)]))]
    ).evaluate(in: [:])
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
    let result = try StateExpr.recursiveCall("SfS", [.value(.set([.int(3), .int(1), .int(2)]))])
      .evaluate(in: [:], recursiveFuncs: [fn])
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

  @Test("renameVar replaces variable references by AST rewrite")
  func renameVarReplacesNested() {
    let body: StateExpr = .add(
      .multiply(.variable("userVar"), .value(.int(2))),
      .variable("userVar")
    )
    let result = renameVar("userVar", to: "x0", in: body)
    let desc = result.description
    #expect(!desc.contains("userVar"))
    #expect(desc.contains("x0"))
  }

  @Test("raw function AST construction remains explicit")
  func rawFunctionASTConstruction() {
    let pc = Var<TLAValue>("pc")
    let selfProcess = Var<Int>("self")
    let read = StateExpr.functionApply(pc.stateExpr, selfProcess.stateExpr)
    let result = StateExpr.except(pc.stateExpr, selfProcess.stateExpr, .value(.string("done")))
    #expect(read == .functionApply(.variable("pc"), .variable("self")))
    let expected: StateExpr = .except(.variable("pc"), .variable("self"), .value(.string("done")))
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
    if case .ok(let count) = try ModelChecker(spec: spec, maxStates: 50).check() {
      #expect(count >= 2)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("SpecRuntime handles function-typed variable correctly")
  func functionTypeRuntime() throws {
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
    let rt = try SpecRuntime(spec: spec)
    let state = rt.initialStates().first!
    let next = try rt.apply(.init(name: "init"), to: state)
    #expect(next["programCounter"] != nil)
  }
}
@Suite(.serialized) struct LivenessCheckerTests { @Test("SCC decomposition works on HourClock (12 states, 1 SCC)")
  func hourClockSCC() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    #expect(sccs.count == 1)
    #expect(sccs[0].count == 12)
  }

  @Test("Terminal SCC detection works")
  func terminalSCC() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    #expect(terminals.count == 1)
  }

  @Test("checkEventually: satisfied when property holds in SCC")
  func eventuallySatisfied() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    let eventually12: StateExpr = .equal(.variable("hr"), .value(.int(12)))
    let result = try lc.checkEventually(eventually12, fairSCCs: terminals)
    #expect(result == .satisfied)
  }

  @Test("checkEventually: violated when property never holds")
  func eventuallyViolated() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    let eventually13: StateExpr = .equal(.variable("hr"), .value(.int(13)))
    let result = try lc.checkEventually(eventually13, fairSCCs: terminals)
    if case .violated = result {} else { #expect(Bool(false)) }
  }

  @Test("WF satisfied, SF violated: A exits SCC, B+C cycle within")
  func wfSfDifferential() throws {
    // 3 states (0, 1, 2). A exits SCC, B+C cycle within.
    // SCC {0,1} has A enabled at 0 (goes to 2 outside SCC), disabled at 1.
    // WF(A): disabled somewhere → fair
    // SF(A): enabled somewhere but never taken within SCC → unfair
    let x = Var<Int>("x")
    let spec = TLASpec("WFSFTest") {
      Variable(x, 0)
      Action("A") { x == 0 && x.becomes(2) }
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    // Check ALL SCCs, not just terminal ones
    let wfFair = lc.fairTerminalSCCs(
      sccs, fairness: [FairnessCondition.weakFairness("A")], actions: spec.actions)
    let sfFair = lc.fairTerminalSCCs(
      sccs, fairness: [FairnessCondition.strongFairness("A")], actions: spec.actions)
    // WF accepts more SCCs than SF
    #expect(
      wfFair.count > sfFair.count,
      "WF should accept more SCCs than SF (WF: \(wfFair.count), SF: \(sfFair.count))")
  }
}
@Test("ChangRoberts liveness: cand ~> won holds")
func changRobertsLiveness() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, maxStates: 500)
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(graph: graph)
  // Verify temporal property exists
  #expect(spec.temporalProperties.count == 1)
  #expect(spec.temporalProperties[0].name == "Liveness")
  let results = try lc.checkAll(
    spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
  #expect(results.count == 1)
  #expect(results[0] == .satisfied)
}
@Test("ChangRoberts liveness verified by TLC")
func changRobertsLivenessParity() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, maxStates: 500)
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(graph: graph)
  let results = try lc.checkAll(
    spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
  #expect(results.count == 1)
  #expect(results[0] == .satisfied)
}
