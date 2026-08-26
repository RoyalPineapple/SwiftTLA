import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

private func compiledSuccessors(
  _ body: ActionExpr,
  from values: [(String, TLAValue)],
  variables: [String]
) throws -> [TLAStateProjection] {
  let spec = TLASpec(
    name: "ActionFixture",
    variables: variables.map { NamedVar(name: $0, initial: .int(0)) },
    actions: [NamedAction(name: "step", body: body)],
    invariants: []
  )
  let compilation = try spec.compile()
  let state = try CompiledState(
    projection: projection(values),
    compilation: compilation
  )
  let action = try #require(compilation.semantics.actions.first)
  return try CompiledRuntime(compilation: compilation)
    .successors(for: action.id, from: state)
    .map { try $0.state.projection(using: compilation.layout) }
}

private func compiledInitialProjections(_ spec: TLASpec) throws -> [TLAStateProjection] {
  let compilation = try spec.compile()
  return try CompiledRuntime(compilation: compilation).initialStates()
    .map { try $0.projection(using: compilation.layout) }
}

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
    "Compiled action variants",
    arguments: [
      ("simpleAssign", 1),
      ("guardTrue", 1),
      ("guardFalse", 0),
      ("orBranches", 2),
      ("twoVars", 1)
    ] as [(String, Int)])
  func actionMatrix(_ variant: String, _ expected: Int) throws {
    let s: [(String, TLAValue)] = [("x", .int(0)), ("y", .int(0))]
    let action: ActionExpr
    switch variant {
    case "simpleAssign": action = .assign(.named("x"), .value(.int(42)))
    case "guardTrue":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(0)))), .assign(.named("x"), .value(.int(1))))
    case "guardFalse":
      action = .and(.guard_(.equal(.variable("x"), .value(.int(1)))), .assign(.named("x"), .value(.int(2))))
    case "orBranches": action = .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2))))
    case "twoVars": action = .and(.assign(.named("x"), .value(.int(1))), .assign(.named("y"), .value(.int(2))))
    default: action = .assign(.named("x"), .value(.int(0)))
    }
    let r = try compiledSuccessors(action, from: s, variables: ["x", "y"])
    #expect(r.count == expected)
  }

  @Test("Compiled action execution accepts wide lowered simultaneous updates")
  func wideAssignmentsPreserveOneCommitment() throws {
    // This is deliberately large enough to exercise a lowered atomic block,
    // while keeping the recursive value-type teardown itself bounded.
    let depth = 256
    let assignment = ActionExpr.assign(.named("x"), .value(.int(1)))
    let action = (0..<depth).reduce(assignment) { partial, _ in
      .and(partial, assignment)
    }

    let successors = try compiledSuccessors(
      action,
      from: [("x", .int(0))],
      variables: ["x"]
    )
    let x = try #require(TLAStateProjection.Token(validating: "x"))
    #expect(successors.count == 1)
    #expect(successors.first?.value(for: x) == .int(1))
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
  let s0: [(String, TLAValue)] = [("x", .int(0))]
  let s2: [(String, TLAValue)] = [("a", .int(0)), ("b", .int(0))]

  @Test func simpleAssign() throws {
    let r = try compiledSuccessors(.assign(.named("x"), .value(.int(42))), from: s0, variables: ["x"])
    let assigned = try value("x", in: try #require(r.first))
    #expect(r.count == 1)
    #expect(assigned == .int(42))
  }

  @Test func unchanged() throws {
    let r = try compiledSuccessors(.unchanged(.named("x")), from: s0, variables: ["x"])
    let unchanged = try value("x", in: try #require(r.first))
    #expect(r.count == 1)
    #expect(unchanged == .int(0))
  }

  @Test func guardTrue() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))), .assign(.named("x"), .value(.int(1))))
    let r = try compiledSuccessors(a, from: s0, variables: ["x"])
    #expect(r.count == 1)
  }

  @Test func guardFalse() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(1)))), .assign(.named("x"), .value(.int(2))))
    let r = try compiledSuccessors(a, from: s0, variables: ["x"])
    #expect(r.isEmpty)
  }

  @Test func twoVars() throws {
    let a: ActionExpr = .and(.assign(.named("a"), .value(.int(1))), .assign(.named("b"), .value(.int(2))))
    let r = try compiledSuccessors(a, from: s2, variables: ["a", "b"])
    let successor = try #require(r.first)
    let aValue = try value("a", in: successor)
    let bValue = try value("b", in: successor)
    #expect(r.count == 1)
    #expect(aValue == .int(1))
    #expect(bValue == .int(2))
  }

  @Test func orBranches() throws {
    let a: ActionExpr = .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2))))
    let r = try compiledSuccessors(a, from: s0, variables: ["x"])
    #expect(r.count == 2)
  }

  @Test func nestedOr() throws {
    let a: ActionExpr = .or(
      .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2)))),
      .assign(.named("x"), .value(.int(3))))
    let r = try compiledSuccessors(a, from: s0, variables: ["x"])
    #expect(r.count == 3)
  }

  @Test func existentialRetainsItsSurroundingGuard() throws {
    let action: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))),
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign(.named("x"), .variable("candidate"))
      )
    )

    let blocked = try compiledSuccessors(action, from: [("x", .int(1))], variables: ["x"])
    #expect(blocked.isEmpty)

    let advanced = try compiledSuccessors(action, from: s0, variables: ["x"])
    #expect(try advanced.map { try value("x", in: $0) } == [.int(1)])
  }

  @Test func equivalentAssignmentsAroundAnExistentialAgree() throws {
    let action: ActionExpr = .and(
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign(.named("x"), .variable("candidate"))
      ),
      .assign(.named("x"), .value(.int(1)))
    )

    let successors = try compiledSuccessors(action, from: s0, variables: ["x"])
    #expect(try successors.map { try value("x", in: $0) } == [.int(1)])
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
      StateExpr.record(["k": .int(1)]), .recordAccess(StateExpr.record(["k": .int(1)]), "k"),
      .domain(StateExpr.record(["k": .int(1)])),
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
    let v = try compiledValue(e, values: [("x", .int(5))])
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
    let state: [(String, TLAValue)] = [("f", v), ("k", .int(1))]
    let result = try compiledValue(StateExpr.functionApply(.variable("f"), .variable("k")), values: state)
    #expect(result == .string("one"))
  }
}

// MARK: - ActionExpr: every case

@Suite(.serialized) struct ActionExprCompleteTests {
  @Test(
    "Every ActionExpr case enumerates correctly",
    arguments: [
      ("assign", ActionExpr.assign(.named("x"), .int(1)), 1),
      ("unchanged", ActionExpr.unchanged(.named("x")), 1),
      ("simpleAnd", ActionExpr.and(.assign(.named("x"), .int(1)), .assign(.named("y"), .int(2))), 1),
      ("or", ActionExpr.or(.assign(.named("x"), .int(1)), .assign(.named("x"), .int(2))), 2),
      (
        "guarded", ActionExpr.and(.guard_(.equal(.variable("x"), .int(0))), .assign(.named("x"), .int(1))),
        1
      )
    ] as [(String, ActionExpr, Int)])
  func enumerate(_ name: String, _ a: ActionExpr, _ expected: Int) throws {
    let s: [(String, TLAValue)] = [("x", .int(0)), ("y", .int(0))]
    let r = try compiledSuccessors(a, from: s, variables: ["x", "y"])
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
    let labels = try #require(graph.transitions[.init(0)]).map(\.label)
    let expectedArguments: [[TLAValue]] = [
      [.int(1), .int(10), .int(100)], [.int(1), .int(10), .int(200)],
      [.int(1), .int(20), .int(100)], [.int(1), .int(20), .int(200)],
      [.int(2), .int(10), .int(100)], [.int(2), .int(10), .int(200)],
      [.int(2), .int(20), .int(100)], [.int(2), .int(20), .int(200)]
    ]
    #expect(labels.map(\.arguments) == expectedArguments)
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("board__0_0_0 == board(1, 10, 100)"))
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("board__1_1_1 == board(2, 20, 200)"))

    let compilation = try spec.compile()
    let action = try #require(compilation.layout.actionID(named: "board"))
    let runtime = CompiledRuntime(compilation: compilation)
    let initial = try #require(try runtime.initialStates().first)
    let successors = try runtime.successors(for: action, from: initial)
    let next = try #require(successors.first { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) }
        == [.int(2), .int(20), .int(200)]
    })
    let floorID = try #require(compilation.layout.variableID(named: "floor"))
    #expect(try next.state.value(for: floorID).rendered(using: compilation.layout) == .int(222))
    #expect(try successors.contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) }
        == [.int(3), .int(20), .int(200)]
    } == false)
    #expect(try initial.value(for: floorID).rendered(using: compilation.layout) == .int(0))
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
    let transitions = try #require(graph.transitions[.init(0)])
    let labels = transitions.map(\.label)
    #expect(
      Set(labels) == [
        .init(.init(name: "moveElevator", arguments: [.int(1)])),
        .init(.init(name: "moveElevator", arguments: [.int(2)]))
      ])
    #expect(
      Set(transitions.map(\.action)) == ["moveElevator(1)", "moveElevator(2)"])
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("moveElevator(id) =="))
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("moveElevator__0 == moveElevator(1)"))
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

    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
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
    let checker = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))

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

    let incomplete = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1)).explore()
    #expect(!incomplete.isComplete)
  }

  @Test func singleVarLinear() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph.states.count == 4)
  }

  @Test func singleVarCyclic() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("toggle") { x.becomes((x + 1) % 2) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test func invariantHolds() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("nonNeg") { x >= 0 }
    }
    if case .ok(let count) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check() {
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
    if case .invariantViolated(let name, _, _) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
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

    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).check()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 3)).exploreGraph()
    // Processes 3 states, discovers 4 (successors of last processed also stored)
    #expect(graph.states.count >= 3 && graph.states.count <= 4)
  }

  @Test func deadlockNotDetectedWhenFlagFalse() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("once") { x.becomes(1).when(x == 0) }
    }
    if case .ok(let c) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check() {
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph.states.count == 9)
  }

  @Test func expressionBackedNondeterministicInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("LazyInit") {
      Variable(from: x.name, StateExpr.set([1, 2, 3]))
      Invariant("TypeOK") { x >= 1 && x <= 3 }
    }

    let compilation = try spec.compile()
    let variable = try #require(compilation.layout.variableID(named: "x"))
    let initialValues = try CompiledRuntime(compilation: compilation).initialStates().map {
      try $0.value(for: variable).rendered(using: compilation.layout)
    }
    let expectedValues: Set<TLAValue> = [.int(1), .int(2), .int(3)]
    #expect(Set(initialValues) == expectedValues)
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph().states.count == 3)
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("Init == x \\in {1, 2, 3}"))
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph.states.count == 16)
  }
}

// MARK: - Phase 1-7: bound variables, functions, sequences, EXCEPT, CONSTANTS
@Suite(.serialized) struct BoundVariableTests { @Test("Function literal with bound variable evaluates correctly")
  func functionLiteralWithBoundVar() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2, 3])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 2).raw)
    let result = try compiledValue(fun)
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
    let result = try compiledValue(apply)
    #expect(result == .int(20))
  }

  @Test("Function EXCEPT updates a key")
  func functionExcept() throws {
    let p = Var<Int>("p")
    let domain = StateExpr.set([1, 2])
    let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
    let updated = StateExpr.except(fun, .value(.int(1)), .value(.int(99)))
    let result = try compiledValue(updated)
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
    let result = try compiledValue(expr)
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
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)
    ).explore()
    let resultToken = try #require(TLAStateProjection.Token(validating: "result"))
    let results = Set(exploration.graph.states.values.compactMap { $0.value(for: resultToken) })
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
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)
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
    if case .ok(let count) = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).check() {
      #expect(count > 0)
    } else {
      #expect(Bool(false))
    }
  }

  @Test("SpecParser parses choose(variable, from:) call")
  func specParserChooseCall() throws {
    let source = "choose(picked, from: q)"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
    let result = SpecParser.decodeActionExpr(expr)
    #expect(result == ActionExpr.chooseAction(.named("picked"), .variable("q")))
  }

  @Test("SpecParser parses singleton()")
  func specParserSingleton() throws {
    let source = "StateExpr.singleton(x)"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
    let result = SpecParser.decodeStateExpr(expr)
    #expect(result == StateExpr.setLiteral([.variable("x")]))
  }

  @Test("SpecParser parses functionLiteral(p, in: domain, body)")
  func specParserFunctionLiteral() throws {
    let source = "StateExpr.functionLiteral(StateExpr.set([1]), (2 + 3))"
    let statement = try #require(Parser.parse(source: source).statements.first)
    let expr = try #require(statement.item.as(ExprSyntax.self))
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
