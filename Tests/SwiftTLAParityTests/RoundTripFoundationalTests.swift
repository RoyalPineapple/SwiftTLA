import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLAModels
import Testing
import UpstreamParity

// MARK: - Var<T> operators: full matrix

@Suite(.serialized) struct VarOperatorMatrix {
  @Test(
    "Arithmetic",
    arguments: [
      ("+", 3, "(x + 3)"),
      ("-", 1, "(x - 1)"),
      ("*", 2, "(x * 2)"),
      ("%", 5, "(x % 5)")
    ])
  func arithmetic(_ op: String, _ val: Int, _ expected: String) {
    let x = Var<Int>("x")
    let result: String
    switch op {
    case "+": result = (x + val).raw.description
    case "-": result = (x - val).raw.description
    case "*": result = (x * val).raw.description
    case "%": result = (x % val).raw.description
    default: result = ""
    }
    #expect(result == expected)
  }

  @Test(
    "Comparison matrix",
    arguments: [
      ("==", 0, "(x = 0)"),
      ("==", 1, "(x = 1)"),
      ("!=", 0, "(x /= 0)"),
      ("<", 5, "(x < 5)"),
      ("<=", 5, "(x <= 5)"),
      (">", 0, "(x > 0)"),
      (">=", 1, "(x >= 1)")
    ])
  func comparison(_ op: String, _ val: Int, _ expected: String) {
    let x = Var<Int>("x")
    let result: String
    switch op {
    case "==": result = (x == val).description
    case "!=": result = (x != val).description
    case "<": result = (x < val).description
    case "<=": result = (x <= val).description
    case ">": result = (x > val).description
    case ">=": result = (x >= val).description
    default: result = ""
    }
    #expect(result == expected)
  }

  @Test(
    "ActionEnumerator variants",
    arguments: [
      ("simpleAssign", 1),
      ("guardTrue", 1),
      ("guardFalse", 0),
      ("orBranches", 2),
      ("twoVars", 1)
    ] as [(String, Int)])
  func actionMatrix(_ variant: String, _ expected: Int) throws {
    let s: [String: TLAValue] = ["x": .int(0), "y": .int(0)]
    let action: ActionExpr
    switch variant {
    case "simpleAssign": action = .assign("x", .value(.int(42)))
    case "guardTrue":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(0)))), .assign("x", .value(.int(1))))
    case "guardFalse":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(1)))), .assign("x", .value(.int(2))))
    case "orBranches": action = .or(.assign("x", .value(.int(1))), .assign("x", .value(.int(2))))
    case "twoVars": action = .and(.assign("x", .value(.int(1))), .assign("y", .value(.int(2))))
    default: action = .assign("x", .value(.int(0)))
    }
    let r = try ActionEnumerator.enumerate(action, from: s, varNames: ["x", "y"])
    #expect(r.count == expected)
  }

  @Test("Action assignment extraction accepts wide lowered simultaneous updates")
  func wideAssignmentsPreserveOneCommitment() throws {
    // This is deliberately large enough to exercise a lowered atomic block,
    // while keeping the recursive value-type teardown itself bounded.
    let depth = 256
    let assignment = ActionExpr.assign("x", .value(.int(1)))
    let action = (0..<depth).reduce(assignment) { partial, _ in
      .and(partial, assignment)
    }

    let result = try ActionEnumerator.extractAssignments(action)
    #expect(result.assignments == ["x": .value(.int(1))])
    #expect(result.guards.isEmpty)
  }

  @Test(
    "StateExpr cases",
    arguments: [
      ("valueInt", "42"),
      ("valueBool", "TRUE"),
      ("valueString", "\"hi\""),
      ("variable", "x"),
      ("add", "(1 + 2)"),
      ("subtract", "(5 - 3)"),
      ("multiply", "(2 * 3)"),
      ("modulo", "(7 % 3)"),
      ("negate", "(-1)"),
      ("equal", "(1 = 1)"),
      ("notEqual", "(1 /= 2)"),
      ("lessThan", "(1 < 2)"),
      ("greaterThan", "(2 > 1)"),
      ("setLiteral", "{1, 2}"),
      ("inSet", "(1 \\in {1, 2})"),
      ("tupleLiteral", "<<1, 2>>"),
      ("ifThen", "(IF TRUE THEN 1 ELSE 2)"),
      ("enabled", "ENABLED Tick")
    ] as [(String, String)])
  func stateExprMatrix(_ caseName: String, _ expected: String) {
    let e: StateExpr
    switch caseName {
    case "valueInt": e = .value(.int(42))
    case "valueBool": e = .value(.bool(true))
    case "valueString": e = .value(.string("hi"))
    case "variable": e = .variable("x")
    case "add": e = .add(.int(1), .int(2))
    case "subtract": e = .subtract(.int(5), .int(3))
    case "multiply": e = .multiply(.int(2), .int(3))
    case "modulo": e = .modulo(.int(7), .int(3))
    case "negate": e = .negate(.int(1))
    case "equal": e = .equal(.int(1), .int(1))
    case "notEqual": e = .notEqual(.int(1), .int(2))
    case "lessThan": e = .lessThan(.int(1), .int(2))
    case "greaterThan": e = .greaterThan(.int(2), .int(1))
    case "setLiteral": e = .setLiteral([.int(1), .int(2)])
    case "inSet": e = .in(.int(1), .setLiteral([.int(1), .int(2)]))
    case "tupleLiteral": e = .tupleLiteral([.int(1), .int(2)])
    case "ifThen": e = .ifThenElse(.bool(true), .int(1), .int(2))
    case "enabled": e = .enabledAction("Tick")
    default: e = .value(.int(0))
    }
    #expect(e.description == expected)
  }

  @Test func varVsVar() {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    #expect((a == b).description == "(a = b)")
    #expect((a != b).description == "(a /= b)")
    #expect((a < b).description == "(a < b)")
  }

  @Test func prefix() {
    let x = Var<Int>("x")
    #expect((-x).description == "(-x)")
  }

  @Test func stringComparison() {
    let s = Var<String>("s")
    #expect((s == "right").description == "(s = \"right\")")
  }

  @Test func assignmentAndWhen() {
    let x = Var<Int>("x")
    let a = x.becomes(1)
    #expect(a.description.contains("x' = 1"))
    let g = x.becomes(1).when(x == 0)
    #expect(g.description.contains("(x = 0)") && g.description.contains("x' = 1"))
    let s = x.stays
    #expect(s.description.contains("UNCHANGED x"))
  }
}

// MARK: - ActionExpr: full variant coverage

@Suite(.serialized) struct ActionExprMatrix {
  let s0: [String: TLAValue] = ["x": .int(0)]
  let s2: [String: TLAValue] = ["a": .int(0), "b": .int(0)]

  @Test func simpleAssign() throws {
    let r = try ActionEnumerator.enumerate(
      .assign("x", .value(.int(42))), from: s0, varNames: ["x"])
    #expect(r.count == 1 && r[0]["x"] == .int(42))
  }

  @Test func unchanged() throws {
    let r = try ActionEnumerator.enumerate(.unchanged("x"), from: s0, varNames: ["x"])
    #expect(r.count == 1 && r[0]["x"] == .int(0))
  }

  @Test func guardTrue() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))), .assign("x", .value(.int(1))))
    let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
    #expect(r.count == 1)
  }

  @Test func guardFalse() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(1)))), .assign("x", .value(.int(2))))
    let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
    #expect(r.isEmpty)
  }

  @Test func twoVars() throws {
    let a: ActionExpr = .and(.assign("a", .value(.int(1))), .assign("b", .value(.int(2))))
    let r = try ActionEnumerator.enumerate(a, from: s2, varNames: ["a", "b"])
    #expect(r.count == 1 && r[0]["a"] == .int(1) && r[0]["b"] == .int(2))
  }

  @Test func orBranches() throws {
    let a: ActionExpr = .or(.assign("x", .value(.int(1))), .assign("x", .value(.int(2))))
    let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
    #expect(r.count == 2)
  }

  @Test func nestedOr() throws {
    let a: ActionExpr = .or(
      .or(.assign("x", .value(.int(1))), .assign("x", .value(.int(2)))),
      .assign("x", .value(.int(3))))
    let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
    #expect(r.count == 3)
  }

  @Test func existentialRetainsItsSurroundingGuard() throws {
    let action: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))),
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign("x", .variable("candidate"))
      )
    )

    let blocked = try ActionEnumerator.enumerate(action, from: ["x": .int(1)], varNames: ["x"])
    #expect(blocked.isEmpty)

    let advanced = try ActionEnumerator.enumerate(action, from: s0, varNames: ["x"])
    #expect(advanced == [["x": .int(1)]])
  }

  @Test func equivalentAssignmentsAroundAnExistentialAgree() throws {
    let action: ActionExpr = .and(
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign("x", .variable("candidate"))
      ),
      .assign("x", .value(.int(1)))
    )

    let successors = try ActionEnumerator.enumerate(action, from: s0, varNames: ["x"])
    #expect(successors == [["x": .int(1)]])
  }

}

// MARK: - StateExpr: every case tested via CaseIterable

/// Every StateExpr variant must have a non-empty description and be Codable round-trippable
@Suite(.serialized) struct StateExprCompleteTests {
  @Test("Every StateExpr case has a description")
  func allCasesHaveDescriptions() {
    let cases: [StateExpr] = [
      .value(.int(1)), .value(.bool(true)), .value(.string("x")),
      .variable("v"),
      .add(.int(1), .int(1)), .subtract(.int(1), .int(1)),
      .multiply(.int(1), .int(1)), .divide(.int(1), .int(1)),
      .modulo(.int(1), .int(1)), .negate(.int(1)),
      .integerDivide(.int(4), .int(2)),
      .equal(.int(1), .int(1)), .notEqual(.int(1), .int(2)),
      .lessThan(.int(1), .int(2)), .lessOrEqual(.int(1), .int(2)),
      .greaterThan(.int(2), .int(1)), .greaterOrEqual(.int(2), .int(1)),
      .and(.bool(true), .bool(true)), .or(.bool(true), .bool(true)),
      .not(.bool(true)),
      .ifThenElse(.bool(true), .int(1), .int(2)),
      .setLiteral([.int(1)]), .in(.int(1), .setLiteral([.int(1)])),
      .subset(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .union(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .intersection(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .setDifference(.setLiteral([.int(1)]), .setLiteral([.int(1)])),
      .cardinality(.setLiteral([.int(1)])),
      .setFilter(.setLiteral([.int(1)]), "x0", .bool(true)),
      .setMap(.variable("x"), "x0", .setLiteral([.int(1)])),
      .powerSet(.setLiteral([.int(1)])),
      .unionAll(.setLiteral([.setLiteral([.int(1)])])),
      .tupleLiteral([.int(1)]), .tupleAccess(.tupleLiteral([.int(1)]), 0),
      .tupleLength(.tupleLiteral([.int(1)])),
      .tupleAppend(.tupleLiteral([.int(1)]), .int(2)),
      .tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)])),
      .recordLiteral(["k": .int(1)]), .recordAccess(.recordLiteral(["k": .int(1)]), "k"),
      .domain(.recordLiteral(["k": .int(1)])),
      .functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")),
      .functionApply(.functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")), .int(1)),
      .except(.functionLiteral(.setLiteral([.int(1)]), "x0", .variable("x")), .int(1), .int(2)),
      .caseExpr([.bool(true), .int(1)], .int(0)),
      .forAll(.setLiteral([.int(1)]), "x0", .bool(true)),
      .exists(.setLiteral([.int(1)]), "x0", .bool(true)),
      .choose(.setLiteral([.int(1)]), "x0", .bool(true)),
      .enabledAction("Foo")
    ]
    for e in cases {
      #expect(!e.description.isEmpty, "\(e) has no description")
    }
  }

  @Test("StateExpr evaluates correctly in state")
  func evaluatesInState() throws {
    let e: StateExpr = .add(.variable("x"), .int(1))
    let v = try e.evaluate(in: ["x": .int(5)])
    #expect(v == .int(6))
  }
}

// MARK: - TLAValue: every case

@Suite(.serialized) struct TLAValueTests {
  @Test(
    "Every TLAValue case has a description",
    arguments: [
      TLAValue.int(1), .bool(true), .string("hi"),
      .set([.int(1)]), .tuple([.int(1)]), .record(["k": .int(1)]),
      .constant("N")
    ] as [TLAValue])
  func descriptions(_ v: TLAValue) {
    #expect(!v.description.isEmpty)
  }

  @Test("TLAValue function apply lookup")
  func functionApplyLookup() throws {
    let v: TLAValue = .function([.int(1): .string("one")])
    let state: [String: TLAValue] = ["f": v, "k": .int(1)]
    let result = try StateExpr.functionApply(.variable("f"), .variable("k")).evaluate(in: state)
    #expect(result == .string("one"))
  }
}

// MARK: - ActionExpr: every case

@Suite(.serialized) struct ActionExprCompleteTests {
  @Test(
    "Every ActionExpr case enumerates correctly",
    arguments: [
      ("assign", ActionExpr.assign("x", .int(1)), 1),
      ("unchanged", ActionExpr.unchanged("x"), 1),
      ("simpleAnd", ActionExpr.and(.assign("x", .int(1)), .assign("y", .int(2))), 1),
      ("or", ActionExpr.or(.assign("x", .int(1)), .assign("x", .int(2))), 2),
      (
        "guarded", ActionExpr.and(.guard_(.equal(.variable("x"), .int(0))), .assign("x", .int(1))),
        1
      )
    ] as [(String, ActionExpr, Int)])
  func enumerate(_ name: String, _ a: ActionExpr, _ expected: Int) throws {
    let s: [String: TLAValue] = ["x": .int(0), "y": .int(0)]
    let r = try ActionEnumerator.enumerate(a, from: s, varNames: ["x", "y"])
    #expect(r.count == expected, "\(name): expected \(expected), got \(r.count)")
  }
}

// MARK: - ModelChecker: spec pattern matrix

@Suite(.serialized) struct ModelCheckerMatrix {
  @Test("parameterized actions retain ordered Cartesian invocation labels")
  func parameterizedActionsRetainOrderedCartesianInvocationLabels() throws {
    let floor = Var<Int>("floor")
    let person = Var<Int>("person")
    let elevator = Var<Int>("elevator")
    let direction = Var<Int>("direction")
    let spec = TLASpec("Boarding") {
      Variable(floor, 0)
      Action(
        "board",
        parameters: [
          ActionParameter("person", values: [1, 2]),
          ActionParameter("elevator", values: [10, 20]),
          ActionParameter("direction", values: [100, 200])
        ]
      ) {
        floor.becomes(person + elevator + direction)
      }
    }

    #expect(spec.actions[0].bindings.map(\.name) == ["person", "elevator", "direction"])
    let graph = try ModelChecker(spec: spec).exploreGraph()
    let labels = graph.transitions[.init(0)]!.map(\.label)
    let expectedArguments: [[TLAValue]] = [
      [.int(1), .int(10), .int(100)], [.int(1), .int(10), .int(200)],
      [.int(1), .int(20), .int(100)], [.int(1), .int(20), .int(200)],
      [.int(2), .int(10), .int(100)], [.int(2), .int(10), .int(200)],
      [.int(2), .int(20), .int(100)], [.int(2), .int(20), .int(200)]
    ]
    #expect(labels.map(\.arguments) == expectedArguments)
    #expect(spec.tlaModule.contains("board__0_0_0 == board(1, 10, 100)"))
    #expect(spec.tlaModule.contains("board__1_1_1 == board(2, 20, 200)"))
    #expect(
      spec.swiftSource.contains(
        "parameters: [ActionParameter(\"person\", values: [1, 2]), "
          + "ActionParameter(\"elevator\", values: [10, 20]), "
          + "ActionParameter(\"direction\", values: [100, 200])]"
      ))

    let runtime = SpecRuntime(spec: spec)
    let initial = try #require(runtime.initialStates().first)
    let next = try runtime.apply(
      .init(name: "board", arguments: [.int(2), .int(20), .int(200)]), to: initial)
    #expect(next["floor"] == .int(222))
    #expect(throws: SpecRuntime.RuntimeError.self) {
      try runtime.apply(
        .init(name: "board", arguments: [.int(3), .int(20), .int(200)]), to: initial)
    }
    #expect(initial["floor"] == .int(0))
  }

  @Test func parameterizedActionExpandsFiniteDomainAndLabelsTransitions() throws {
    let floor = Var<Int>("floor")
    let id = Var<Int>("id")
    let spec = TLASpec("TwoCars") {
      Variable(floor, 0)
      Action("moveElevator", parameters: [ActionParameter("id", values: [1, 2])]) {
        floor.becomes(id)
      }
    }

    #expect(spec.actions[0].bindings.map(\.name) == ["id"])
    #expect(spec.actions[0].bindings[0].values == [.int(1), .int(2)])
    let graph = try ModelChecker(spec: spec).exploreGraph()
    let labels = graph.transitions[.init(0)]!.map(\.label)
    #expect(
      Set(labels) == [
        .init(.init(name: "moveElevator", arguments: [.int(1)])),
        .init(.init(name: "moveElevator", arguments: [.int(2)]))
      ])
    #expect(
      Set(graph.transitions[.init(0)]!.map(\.action)) == ["moveElevator(1)", "moveElevator(2)"])
    #expect(spec.tlaModule.contains("moveElevator(id) =="))
    #expect(spec.tlaModule.contains("moveElevator__0 == moveElevator(1)"))
  }

  @Test("parameterized invocations retain every label when they discover one successor")
  func parameterizedInvocationsRetainLabelsForSharedNewSuccessor() throws {
    let floor = Var<Int>("floor")
    let spec = TLASpec("SharedSuccessor") {
      Variable(floor, 0)
      Action("openDoor", parameters: [ActionParameter("trigger", values: [0, 1])]) {
        floor.becomes(1)
      }
    }

    let graph = try ModelChecker(spec: spec).exploreGraph()
    let transitions = try #require(graph.transitions[.init(0)])

    #expect(transitions.map(\.action) == ["openDoor(0)", "openDoor(1)"])
    #expect(transitions.map(\.target) == [.init(1), .init(1)])
  }

  @Test func explorationResultMatchesExistingCheckerViews() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("ExplorationSnapshot") {
      Variable(from: x.name, StateExpr.set([1, 2]))
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let checker = ModelChecker(spec: spec, maxStates: 100)

    let exploration = try checker.explore()
    let graph = try checker.exploreGraph()
    let result = try checker.check()

    #expect(exploration.initialStateIDs.map(\.id) == [0, 1])
    #expect(exploration.initialStateIDs.allSatisfy { exploration.graph.states[$0] != nil })
    #expect(exploration.graph.states == graph.states)
    #expect(
      exploration.graph.transitions.mapValues { $0.map { "\($0.action):\($0.target.id)" } }
        == graph.transitions.mapValues { $0.map { "\($0.action):\($0.target.id)" } }
    )
    #expect(exploration.result.description == result.description)
    #expect(exploration.isComplete)

    let incomplete = try ModelChecker(spec: spec, maxStates: 1).explore()
    #expect(!incomplete.isComplete)
  }

  @Test func singleVarLinear() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
    #expect(graph.states.count == 4)
  }

  @Test func singleVarCyclic() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("toggle") { x.becomes((x + 1) % 2) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test func invariantHolds() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("nonNeg") { x >= 0 }
    }
    if case .ok(let count) = try ModelChecker(spec: spec, maxStates: 100).check() {
      #expect(count == 6)
    } else {
      #expect(Bool(false))
    }
  }

  @Test func invariantViolated() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1) }
      Invariant("lt3") { x < 3 }
    }
    if case .invariantViolated(let name, _, _) = try ModelChecker(spec: spec, maxStates: 100)
      .check() {
      #expect(name == "lt3")
    } else {
      #expect(Bool(false))
    }
  }

  @Test func invariantDiagnosticRetainsProjectedStateAndCounterexampleTrace() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("DiagnosticCounter") {
      Variable(x, 0)
      Action("increment") { x.becomes(x + 1).when(x < 1) }
      Invariant("mustStayZero") { x == 0 }
    }

    let result = try ModelChecker(spec: spec, maxStates: 10).check()
    let diagnostic = try #require(result.diagnostic)
    let xToken = try #require(TLAStateProjection.Token(validating: "x"))

    #expect(diagnostic.kind == .invariantViolated)
    #expect(diagnostic.subject == "mustStayZero")
    #expect(diagnostic.expected == "the invariant to evaluate to true")
    #expect(diagnostic.actual == "false")
    #expect(diagnostic.stateCommitted == false)
    #expect(diagnostic.state?.projection?.value(for: xToken) == .int(1))
    #expect(diagnostic.trace.map(\.action) == ["init", "increment"])
    #expect(diagnostic.nextSafeAction.contains("final trace transition"))
  }

  @Test func maxStatesBound() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 3).exploreGraph()
    // Processes 3 states, discovers 4 (successors of last processed also stored)
    #expect(graph.states.count >= 3 && graph.states.count <= 4)
  }

  @Test func deadlockNotDetectedWhenFlagFalse() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("once") { x.becomes(1).when(x == 0) }
    }
    if case .ok(let c) = try ModelChecker(spec: spec, maxStates: 100).check() {
      #expect(c == 2)
    } else {
      #expect(Bool(false))
    }
  }

  @Test func twoVarBranching() throws {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    let spec = TLASpec("Test") {
      Variable(a, 0)
      Variable(b, 0)
      Action("incA") { a.becomes(a + 1).when(a < 2) }
      Action("incB") { b.becomes(b + 1).when(b < 2) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
    #expect(graph.states.count == 9)
  }

  @Test func expressionBackedNondeterministicInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("LazyInit") {
      Variable(from: x.name, StateExpr.set([1, 2, 3]))
      Invariant("TypeOK") { x >= 1 && x <= 3 }
    }

    let states = computeInitialStates(spec)
    #expect(Set(states.compactMap { $0["x"] }) == Set([.int(1), .int(2), .int(3)]))
    #expect(try ModelChecker(spec: spec).exploreGraph().states.count == 3)
    #expect(spec.tlaModule.contains("Init == x \\in {1, 2, 3}"))
  }

  @Test func dieHard16() throws {
    let big = Var<Int>("big")
    let small = Var<Int>("small")
    let spec = TLASpec("DieHard") {
      Variable(big, 0)
      Variable(small, 0)
      Action("FB") { big.becomes(5) }
      Action("FS") { small.becomes(3) }
      Action("EB") { big.becomes(0) }
      Action("ES") { small.becomes(0) }
      Action("S2B") {
        (big + small <= 5) && big.becomes(big + small) && small.becomes(0)
          || (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
      }
      Action("B2S") {
        (big + small <= 3) && small.becomes(big + small) && big.becomes(0)
          || (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
      }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
    #expect(graph.states.count == 16)
  }
}
