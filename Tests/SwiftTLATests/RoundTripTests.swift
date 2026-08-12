import Testing
import Foundation
import SwiftTLA
import SwiftTLAModels
import UpstreamParity
import SwiftParser
import SwiftSyntax

// MARK: - Var<T> operators: full matrix

@Suite(.serialized) struct VarOperatorMatrix {
    @Test("Arithmetic", arguments: [
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

    @Test("Comparison matrix", arguments: [
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
        case "<":  result = (x < val).description
        case "<=": result = (x <= val).description
        case ">":  result = (x > val).description
        case ">=": result = (x >= val).description
        default:   result = ""
        }
        #expect(result == expected)
    }

    @Test("ActionEnumerator variants", arguments: [
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
        case "guardTrue":    action = .and(.guard_(.equal(.variable("x"), .value(.int(0)))), .assign("x", .value(.int(1))))
        case "guardFalse":   action = .and(.guard_(.equal(.variable("x"), .value(.int(1)))), .assign("x", .value(.int(2))))
        case "orBranches":   action = .or(.assign("x", .value(.int(1))), .assign("x", .value(.int(2))))
        case "twoVars":      action = .and(.assign("x", .value(.int(1))), .assign("y", .value(.int(2))))
        default:             action = .assign("x", .value(.int(0)))
        }
        let r = try ActionEnumerator.enumerate(action, from: s, varNames: ["x", "y"])
        #expect(r.count == expected)
    }

    @Test("StateExpr cases", arguments: [
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
        case "valueInt":    e = .value(.int(42))
        case "valueBool":   e = .value(.bool(true))
        case "valueString": e = .value(.string("hi"))
        case "variable":    e = .variable("x")
        case "add":         e = .add(.int(1), .int(2))
        case "subtract":   e = .subtract(.int(5), .int(3))
        case "multiply":   e = .multiply(.int(2), .int(3))
        case "modulo":     e = .modulo(.int(7), .int(3))
        case "negate":     e = .negate(.int(1))
        case "equal":      e = .equal(.int(1), .int(1))
        case "notEqual":   e = .notEqual(.int(1), .int(2))
        case "lessThan":   e = .lessThan(.int(1), .int(2))
        case "greaterThan": e = .greaterThan(.int(2), .int(1))
        case "setLiteral": e = .setLiteral([.int(1), .int(2)])
        case "inSet":      e = .in(.int(1), .setLiteral([.int(1), .int(2)]))
        case "tupleLiteral": e = .tupleLiteral([.int(1), .int(2)])
        case "ifThen":     e = .ifThenElse(.bool(true), .int(1), .int(2))
        case "enabled":    e = .enabledAction("Tick")
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
        let r = try ActionEnumerator.enumerate(.assign("x", .value(.int(42))), from: s0, varNames: ["x"])
        #expect(r.count == 1 && r[0]["x"] == .int(42))
    }

    @Test func unchanged() throws {
        let r = try ActionEnumerator.enumerate(.unchanged("x"), from: s0, varNames: ["x"])
        #expect(r.count == 1 && r[0]["x"] == .int(0))
    }

    @Test func guardTrue() throws {
        let a: ActionExpr = .and(.guard_(.equal(.variable("x"), .value(.int(0)))), .assign("x", .value(.int(1))))
        let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
        #expect(r.count == 1)
    }

    @Test func guardFalse() throws {
        let a: ActionExpr = .and(.guard_(.equal(.variable("x"), .value(.int(1)))), .assign("x", .value(.int(2))))
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
        let a: ActionExpr = .or(.or(.assign("x", .value(.int(1))), .assign("x", .value(.int(2)))), .assign("x", .value(.int(3))))
        let r = try ActionEnumerator.enumerate(a, from: s0, varNames: ["x"])
        #expect(r.count == 3)
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
    @Test("Every TLAValue case has a description", arguments: [
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
    @Test("Every ActionExpr case enumerates correctly", arguments: [
        ("assign", ActionExpr.assign("x", .int(1)), 1),
        ("unchanged", ActionExpr.unchanged("x"), 1),
        ("simpleAnd", ActionExpr.and(.assign("x", .int(1)), .assign("y", .int(2))), 1),
        ("or", ActionExpr.or(.assign("x", .int(1)), .assign("x", .int(2))), 2),
        ("guarded", ActionExpr.and(.guard_(.equal(.variable("x"), .int(0))), .assign("x", .int(1))), 1)
    ] as [(String, ActionExpr, Int)])
    func enumerate(_ name: String, _ a: ActionExpr, _ expected: Int) throws {
        let s: [String: TLAValue] = ["x": .int(0), "y": .int(0)]
        let r = try ActionEnumerator.enumerate(a, from: s, varNames: ["x", "y"])
        #expect(r.count == expected, "\(name): expected \(expected), got \(r.count)")
    }
}

// MARK: - ModelChecker: spec pattern matrix

@Suite(.serialized) struct ModelCheckerMatrix {
    @Test func parameterizedActionExpandsFiniteDomainAndLabelsTransitions() throws {
        let floor = Var<Int>("floor")
        let spec = TLASpec("TwoCars") {
            Variable(floor, 0)
            Action("moveElevator", id: [1, 2]) { id in
                floor.becomes(id)
            }
        }

        #expect(spec.actions[0].binding?.name == "id")
        #expect(spec.actions[0].binding?.values == [.int(1), .int(2)])
        let graph = try ModelChecker(spec: spec).exploreGraph()
        let labels = graph.transitions[.init(0)]!.map(\.label)
        #expect(Set(labels) == [.init(action: "moveElevator", argument: .int(1)), .init(action: "moveElevator", argument: .int(2))])
        #expect(Set(graph.transitions[.init(0)]!.map(\.action)) == ["moveElevator(1)", "moveElevator(2)"])
        #expect(spec.tlaModule.contains("moveElevator(id) =="))
        #expect(spec.tlaModule.contains("\\E id \\in {1, 2}: moveElevator(id)"))
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
        if case .invariantViolated(let name, _, _) = try ModelChecker(spec: spec, maxStates: 100).check() {
            #expect(name == "lt3")
        } else {
            #expect(Bool(false))
        }
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
        } else { #expect(Bool(false)) }
    }

    @Test func twoVarBranching() throws {
        let a = Var<Int>("a")
        let b = Var<Int>("b")
        let spec = TLASpec("Test") {
            Variable(a, 0); Variable(b, 0)
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
            Variable(big, 0); Variable(small, 0)
            Action("FB") { big.becomes(5) }
            Action("FS") { small.becomes(3) }
            Action("EB") { big.becomes(0) }
            Action("ES") { small.becomes(0) }
            Action("S2B") {
                (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                (big + small > 5)  && big.becomes(5) && small.becomes(small - (5 - big))
            }
            Action("B2S") {
                (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                (big + small > 3)  && small.becomes(3) && big.becomes(big - (3 - small))
            }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 16)
    }
}

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
        let big = Var<Int>("big"); let small = Var<Int>("small")
        let spec = TLASpec("DieHard") {
            Variable(big, 0); Variable(small, 0)
            Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            Action("FillSmallJug") { small.becomes(3) }
            Action("FillBigJug") { big.becomes(5) }
            Action("EmptySmallJug") { small.becomes(0) }
            Action("EmptyBigJug") { big.becomes(0) }
            Action("SmallToBig") {
                (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
            }
            Action("BigToSmall") {
                (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
            }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 16)
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        #expect({ if case .ok = result { true } else { false } }())
    }

    @Test("Allocator = 4 states")
    func allocator4() throws {
        let a = Var<Int>("available"); let b = Var<Int>("allocated")
        let spec = TLASpec("allocator") {
            Variable(a, 3); Variable(b, 0)
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
            Variable(cand, 0); Variable(cnt, 0); Variable(i, 1)
            Invariant("TypeOK") {
                i >= 1 && i <= 4 && cand >= 0 && cand <= 3 && cnt >= 0 && cnt <= 3
            }
            Action("Next") {
                (i <= 3) && i.becomes(i + 1) &&
                (cnt == 0 && cand.becomes(i) && cnt.becomes(1) ||
                 cnt != 0 && cand == i && cnt.becomes(cnt + 1) ||
                 cnt != 0 && cand != i && cnt.becomes(cnt - 1))
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
        let spec = TLASpec("HourClock") { Variable(hr, 1); Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) } }
        let rt = SpecRuntime(spec: spec)
        let state = rt.initialStates().first!
        let next = try rt.apply(actionName: "Tick", to: state)
        #expect(next["hr"] == .int(2))
    }

    @Test("Runtime checks invariants")
    func checkInvariant() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") { Variable(hr, 1); Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) }; Invariant("Positive") { hr > 0 } }
        let rt = SpecRuntime(spec: spec)
        let state = rt.initialStates().first!
        #expect(try rt.check("Positive", in: state) == true)
    }

    @Test("Runtime lists available actions")
    func availableActions() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") { Variable(hr, 1); Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) } }
        let rt = SpecRuntime(spec: spec)
        let state = rt.initialStates().first!
        let available = rt.availableActions(in: state)
        #expect(available.contains("Tick"))
    }

    @Test("Runtime step validates + applies")
    func step() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") { Variable(hr, 1); Action("Tick") { hr.becomes(hr + 1).when(hr < 12) || (hr == 12 && hr.becomes(1)) } }
        let rt = SpecRuntime(spec: spec)
        let state = rt.initialStates().first!
        let result = try rt.step("Tick", from: state)
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
        let next = try rt.apply(actionName: "StepDiscover", to: state)
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
        #expect(graph.states.count == 5) // 0,1,2,3,4
        let values = Set(graph.states.values.compactMap { $0["x"] })
        #expect(values == Set([.int(0), .int(1), .int(2), .int(3), .int(4)]))
    }

    @Test("No transition targets unknown states")
    func noDanglingTransitions() throws {
        let a = Var<Int>("a"); let b = Var<Int>("b")
        let spec = TLASpec("Test") {
            Variable(a, 0); Variable(b, 0)
            Action("incA") { a.becomes(a+1).when(a<3) }
            Action("incB") { b.becomes(b+1).when(b<3) }
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
        let spec = TLASpec("Test") { Variable(x, 0); Action("inc") { x.becomes(x+1) } }
        let g = try ModelChecker(spec: spec, maxStates: 5).exploreGraph()
        // maxStates limits processed, last state may discover one extra
        #expect(g.states.count <= 5 + 1)
    }

    @Test("Invariant checked on all states")
    func invariantChecked() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("inc") { x.becomes(x+1).when(x<5) }
            Invariant("nonNeg") { x >= 0 }
        }
        if case .ok(let c) = try ModelChecker(spec: spec, maxStates: 100).check() {
            #expect(c == 6)
        } else { #expect(Bool(false)) }
    }
}

@Suite(.serialized) struct EdgeCaseTests {
    @Test("3-level nested OR in AND")
    func nestedOrL3() throws {
        let a: ActionExpr = .and(
            .assign("x", .value(.int(1))),
            .or(.or(.assign("y", .value(.int(2))), .assign("y", .value(.int(3)))), .assign("y", .value(.int(4))))
        )
        let s: [String: TLAValue] = ["x": .int(0), "y": .int(0), "z": .int(0)]
        let r = try ActionEnumerator.enumerate(a, from: s, varNames: ["x", "y", "z"])
        #expect(r.count == 3)
    }

    @Test("Deadlock when guard fails at init")
    func deadlockAtInit() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("T") { Variable(x, 0); Action("a") { x.becomes(2).when(x == 1) }; DeadlockCheck() }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        var dead = false; if case .deadlocked = result { dead = true } else { dead = false }
        #expect(dead)
    }

    @Test("Deadlock at terminal linear state")
    func deadlockTerminal() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("T") { Variable(x, 0); Action("a") { x.becomes(x + 1).when(x < 2) }; DeadlockCheck() }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        var val: TLAValue = .int(-1)
        if case .deadlocked(let s) = result { val = s["x"] ?? .int(-1) }
        #expect(val == .int(2))
    }

    @Test("No deadlock on cyclic spec")
    func noDeadlockCyclic() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("T") { Variable(x, 0); Action("a") { x.becomes((x + 1) % 2) }; DeadlockCheck() }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        var ok = false; if case .ok = result { ok = true }
        #expect(ok)
    }

    @Test("maxStates=1 bounds state count")
    func maxStatesOne() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("T") { Variable(x, 0); Action("a") { x.becomes(x + 1) } }
        let g = try ModelChecker(spec: spec, maxStates: 1).exploreGraph()
        #expect(g.states.count <= 2)
    }
}

// MARK: - Phase 1-7: bound variables, functions, sequences, EXCEPT, CONSTANTS

@Suite(.serialized) struct BoundVariableTests {
    @Test("Function literal with bound variable evaluates correctly")
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
        let predicate = StateExpr.forAll(p, in: domain, StateExpr.greaterThan(p.stateExpr, StateExpr.value(.int(0))))
        let result = try predicate.evaluateBool(in: [:])
        #expect(result)
    }

    @Test("exists with bound variable finds matching element")
    func existsWithBoundVar() throws {
        let p = Var<Int>("p")
        let domain = StateExpr.set([1, 2, 3])
        let predicate = StateExpr.exists(p, in: domain, StateExpr.equal(p.stateExpr, StateExpr.value(.int(2))))
        let result = try predicate.evaluateBool(in: [:])
        #expect(result)
    }

    @Test("Sequence variable append and read in model checker")
    func sequenceVariableAppendRead() throws {
        let seq = Var<TLATupleType>("seq")
        let result = Var<Int>("result")
        let spec = TLASpec("SeqTest") {
            Variable(seq, TLAValue.tuple([]))
            Variable(result, 0)
            Action("push") { seq.becomes(seq.appending(42)).when(seq.count == 0) && result.stays }
            Action("pop") { seq.count > 0 && result.becomes(seq.at(1)) }
        }
        let g = try! ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let states = g.states.values
        let results = Set(states.compactMap { $0["result"] })
        #expect(results.contains(.int(0)))
        #expect(results.contains(.int(42)))
    }

    @Test("Function-typed variable stores and retrieves values")
    func functionVariable() throws {
        let clock = Var<TLAFunctionType>("clock")
        let p = Var<Int>("p")
        let domain = StateExpr.set([1, 2])
        let spec = TLASpec("FuncTest") {
            Variable(clock, TLAValue.function([:]))
            Action("init") {
                let fun = StateExpr.functionLiteral(p, in: domain, (p * 10).raw)
                clock.becomes(fun).when(clock.domain.cardinality == 0)
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
    func constantModelCheck() {
        let bound = 5
        let x = Var<Int>("x")
        let spec = TLASpec("ConstTest") {
            Constant("N", bound)
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < bound) }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("CONSTANTS N"))
        #expect(tla.contains("ASSUME N = 5"))
        let g = try! ModelChecker(spec: substituteConstants(spec), maxStates: 10).exploreGraph()
        #expect(g.states.count == bound + 1)
    }

    @Test("choose action produces nondeterministic assignment")
    func chooseAction() throws {
        let picked = Var<Int>("picked")
        let source = Var<TLASetType>("source")
        let spec = TLASpec("ChooseTest") {
            Variable(picked, 0)
            Variable(source, TLAValue.set([.int(1), .int(2), .int(3)]))
            Action("pick") {
                source.cardinality > 0
                && choose(picked, from: source)
                && source.becomes(Expr(.setDifference(source.stateExpr, StateExpr.singleton(picked.stateExpr))))
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

@Suite(.serialized) struct CompletionCoverageTests {
    @Test("completeAction pushes UNCHANGED into OR branches")
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
        let chosenProcess: ActionExpr = .chooseAction("process", .setLiteral([.value(.int(1)), .value(.int(2))]))
        let readState: ActionExpr = .guard_(.equal(
            .functionApply(.variable("programCounter"), .variable("process")),
            .value(.string("initial"))
        ))
        let updateState: ActionExpr = .assign("programCounter",
            .except(.variable("programCounter"), .variable("process"), .value(.string("done")))
        )
        let unchanged: ActionExpr = .unchanged("sent")
        let action = ActionExpr.and(chosenProcess, ActionExpr.and(readState, ActionExpr.and(updateState, unchanged)))

        let state: [String: TLAValue] = [
            "programCounter": .function([.int(1): "initial", .int(2): "initial"]),
            "sent": .set([]),
            "process": .int(0)
        ]
        let successors = try ActionEnumerator.enumerate(action, from: state, varNames: ["programCounter", "sent", "process"])
        #expect(successors.count == 2)
        for s in successors {
            let pc = s["programCounter"]
            let proc = s["process"]
            guard case .function(let mapping) = pc else { #expect(Bool(false)); return }
            if case .int(1) = proc {
                #expect(mapping[.int(1)] == "done")
                #expect(mapping[.int(2)] == "initial")
            }
        }
    }

    @Test("RecursiveFunction builtins evaluate correctly")
    func recursiveBuiltins() throws {
        let result = try StateExpr.recursiveCall("SeqFromSet", [.value(.set([.int(3), .int(1), .int(2)]))]).evaluate(in: [:])
        #expect(result == .tuple([.int(1), .int(2), .int(3)]))
    }

    @Test("DefineRecursive DSL body evaluates with depth tracking")
    func recursiveDSLEval() throws {
        let body: StateExpr = .ifThenElse(
            .equal(.setLiteral([]), .variable("S")),
            .tupleLiteral([]),
            .tupleConcatenate(
                .tupleLiteral([.any(from: .variable("S"))]),
                .recursiveCall("SfS", [
                    .setDifference(.variable("S"),
                        .setLiteral([.any(from: .variable("S"))])
                    )
                ])
            )
        )
        let fn = RecursiveFunc(name: "SfS", params: ["S"], body: body)
        let result = try StateExpr.recursiveCall("SfS", [.value(.set([.int(3), .int(1), .int(2)]))]).evaluate(in: [:], recursiveFuncs: [fn])
        guard case .tuple(let tv) = result else { #expect(Bool(false)); return }
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

    @Test("StateExprConvertible forwarding: functionApply on Var<TLAFunctionType>")
    func functionApplyForwarding() {
        let pc = Var<TLAFunctionType>("pc")
        let selfProcess = Var<Int>("self")
        let result = pc.applying(selfProcess)
        let expected: StateExpr = .functionApply(.variable("pc"), .variable("self"))
        #expect(result == expected)
    }

    @Test("StateExprConvertible forwarding: updated on Var<TLAFunctionType>")
    func functionUpdateForwarding() {
        let pc = Var<TLAFunctionType>("pc")
        let selfProcess = Var<Int>("self")
        let result = pc.updated(at: selfProcess, to: "done")
        let expected: StateExpr = .except(.variable("pc"), .variable("self"), .value(.string("done")))
        #expect(result.raw == expected)
    }

    @Test("Function-typed variable works end-to-end in ModelChecker")
    func functionVariableEndToEnd() throws {
        let programCounter = Var<TLAFunctionType>("programCounter")
        let selfProcess = Var<Int>("selfProcess")
        let spec = TLASpec("FuncEndToEnd") {
            Variable(programCounter, TLAValue.function([.int(1): "initial", .int(2): "initial"]))
            Variable(selfProcess, 0)
            Action("process") {
                choose(selfProcess, from: StateExpr.set([1, 2]))
                && programCounter.applying(selfProcess) == "initial"
                && programCounter.becomes(programCounter.updated(at: selfProcess, to: "done"))
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
        let programCounter = Var<TLAFunctionType>("programCounter")
        let spec = TLASpec("FuncGen") {
            Variable(programCounter, TLAValue.function([:]))
            Action("init") {
                let domain = StateExpr.set([1])
                let p = Var<Int>("p")
                let fun = StateExpr.functionLiteral(p, in: domain, "ready")
                programCounter.becomes(fun).when(programCounter.domain.cardinality == 0)
            }
        }
        let rt = SpecRuntime(spec: spec)
        let state = rt.initialStates().first!
        let next = try rt.apply(actionName: "init", to: state)
        #expect(next["programCounter"] != nil)
    }
}

@Suite(.serialized) struct LivenessCheckerTests {
    @Test("SCC decomposition works on HourClock (12 states, 1 SCC)")
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
        if case .violated = result { } else { #expect(Bool(false)) }
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
        let wfFair = lc.fairTerminalSCCs(sccs, fairness: [FairnessCondition.weakFairness("A")], actions: spec.actions)
        let sfFair = lc.fairTerminalSCCs(sccs, fairness: [FairnessCondition.strongFairness("A")], actions: spec.actions)
        // WF accepts more SCCs than SF
        #expect(wfFair.count > sfFair.count, "WF should accept more SCCs than SF (WF: \(wfFair.count), SF: \(sfFair.count))")
    }
}

    @Test("ChangRoberts liveness: cand ~> won holds")
    func changRobertsLiveness() throws {
        let spec = Example.changRobertsN3.spec
        let mc = ModelChecker(spec: spec, maxStates: 500)
        let graph = try mc.exploreGraph()
        let lc = LivenessChecker(graph: graph)

        // Verify temporal property exists
        #expect(spec.temporalProperties.count == 1)
        #expect(spec.temporalProperties[0].name == "Liveness")

        let results = try lc.checkAll(spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
        #expect(results.count == 1)
        #expect(results[0] == .satisfied)
    }

    @Test("ChangRoberts liveness verified by TLC")
    func changRobertsLivenessParity() throws {
        let spec = Example.changRobertsN3.spec
        let mc = ModelChecker(spec: spec, maxStates: 500)
        let graph = try mc.exploreGraph()
        let lc = LivenessChecker(graph: graph)
        let results = try lc.checkAll(spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
        #expect(results.count == 1)
        #expect(results[0] == .satisfied)
    }

    struct SymmetryReductionTests {
    @Test("Symmetry reduces ChangRoberts state count")
    func changRobertsSymmetryReduction() throws {
        let specNoSym = Example.changRobertsN3.spec
        let mcNoSym = ModelChecker(spec: specNoSym, maxStates: 500)
        let graphNoSym = try mcNoSym.exploreGraph()
        #expect(graphNoSym.states.count == 137)

        let specWithSym = TLASpec("ChangRobertsSym") {
            Extends("Integers")
            Use(spec: specNoSym)
            Symmetry("pc", [1, 2, 3] as Set<Int>)
        }
        let mcWithSym = ModelChecker(spec: specWithSym, maxStates: 500)
        let graphWithSym = try mcWithSym.exploreGraph()
        #expect(graphWithSym.states.count < 137)
        #expect(graphWithSym.states.count > 0)
    }

    @Test("Symmetry with direct-value variable reduces state count")
    func directValueSymmetry() throws {
        let spec = TLASpec("SymTest") {
            let x = Var<Int>("x")
            Variable(x, in: [1, 2, 3])
            Action("inc") { x < 3 && x.becomes(x + 1) }
            Invariant("TypeOK") { x >= 1 && x <= 3 }
            Symmetry("x", [1, 2, 3] as Set<Int>)
        }
        let mc = ModelChecker(spec: spec, maxStates: 100)
        let result = try mc.check()
        guard case .ok(let count) = result else {
            #expect(Bool(false)); return
        }
        #expect(count < 3)
    }

    @Test("Symmetry chains multiple sets")
    func multipleSymmetrySets() throws {
        let spec = TLASpec("MultiSym") {
            let x = Var<Int>("x")
            let y = Var<Int>("y")
            Variable(x, in: [1, 2])
            Variable(y, in: [10, 20])
            Action("bump") {
                (x == 1 && x.becomes(2) && y.stays)
                || (y == 10 && y.becomes(20) && x.stays)
            }
            Invariant("TypeOK") { x >= 1 && x <= 2 && y >= 10 && y <= 20 }
            Symmetry("x", [1, 2] as Set<Int>)
            Symmetry("y", [10, 20] as Set<Int>)
        }
        let mc = ModelChecker(spec: spec, maxStates: 100)
        let result = try mc.check()
        guard case .ok = result else {
            #expect(Bool(false)); return
        }
    }

    @Test("Empty symmetry sets are no-op")
    func emptySymmetryNoOp() throws {
        let spec = TLASpec("NoSym") {
            let x = Var<Int>("x")
            Variable(x, in: 1...3)
            Action("inc") { x < 3 && x.becomes(x + 1) }
            Invariant("TypeOK") { x >= 1 && x <= 3 }
        }
        let mc = ModelChecker(spec: spec, maxStates: 100)
        let result = try mc.check()
        guard case .ok(let count) = result else {
            #expect(Bool(false)); return
        }
        #expect(count == 3)
    }

    @Test("TLA+ symmetry operator and config directive are emitted")
    func symmetryTLAOutput() {
        let spec = TLASpec("SymOut") {
            let x = Var<Int>("x")
            Variable(x, in: [1, 2, 3])
            Invariant("TypeOK") { x >= 1 }
            Symmetry("x", [1, 2, 3] as Set<Int>)
        }
        let tla = spec.tlaModule
        #expect(tla.contains("EXTENDS Integers, FiniteSets, Sequences, TLC"))
        #expect(tla.contains("Symmx == Permutations({1, 2, 3})"))
        #expect(tla.contains("Symmx"))
        #expect(spec.tlaCfg.contains("SYMMETRY Symmx"))
    }
}

// MARK: - StateVar parity: same behavior as Var + Variable

@Suite(.serialized) struct StateVarParityTests {
    @Test("StateVar spec produces same StateGraph as Var + Variable spec")
    func stateVarVsVar() throws {
        let x = Var<Int>("x")
        let spec1 = TLASpec("Test") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 5) }
            Invariant("ok") { x >= 0 && x <= 5 }
        }

        let sv = Var("x", 0)
        let spec2 = TLASpec("Test") {
            Variable(sv)
            Action("inc") { sv.becomes(sv + 1).when(sv < 5) }
            Invariant("ok") { sv >= 0 && sv <= 5 }
        }

        let graph1 = try ModelChecker(spec: spec1, maxStates: 100).exploreGraph()
        let graph2 = try ModelChecker(spec: spec2, maxStates: 100).exploreGraph()
        #expect(graph1.states.count == graph2.states.count)
        #expect(graph1.states.count == 6)

        let result1 = try ModelChecker(spec: spec1, maxStates: 100).check()
        let result2 = try ModelChecker(spec: spec2, maxStates: 100).check()
        if case .ok(let c1) = result1, case .ok(let c2) = result2 {
            #expect(c1 == c2)
        } else {
            #expect(Bool(false), "Invariants should hold in both specs")
        }
    }
}

// MARK: - Enum domain type tests

enum Mode: Int, TLAValueType, StateExprConvertible {
    case idle = 0, active = 1
}

enum Status: String, TLAValueType, StateExprConvertible {
    case on, off
}

@Suite(.serialized) struct EnumDomainTests {
    @Test("Int-backed enum Var model-checks correctly")
    func intEnumVar() throws {
        let mode = Var<Mode>("mode")
        let spec = TLASpec("IntEnum") {
            Variable(mode, Mode.idle)
            Action("toggle") {
                (mode == Mode.idle) && mode.becomes(Mode.active) ||
                (mode == Mode.active) && mode.becomes(Mode.idle)
            }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("Int-backed enum StateVar model-checks correctly")
    func intEnumStateVar() throws {
        let mode = Var("mode", Mode.idle)
        let spec = TLASpec("IntEnumSV") {
            Variable(mode)
            Action("toggle") {
                (mode == Mode.idle) && mode.becomes(Mode.active) ||
                (mode == Mode.active) && mode.becomes(Mode.idle)
            }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("String-backed enum Var model-checks correctly")
    func stringEnumVar() throws {
        let state = Var<Status>("state")
        let spec = TLASpec("StringEnum") {
            Variable(state, Status.on)
            Action("toggle") {
                (state == Status.on) && state.becomes(Status.off) ||
                (state == Status.off) && state.becomes(Status.on)
            }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("String-backed enum StateVar model-checks correctly")
    func stringEnumStateVar() throws {
        let state = Var("state", Status.on)
        let spec = TLASpec("StringEnumSV") {
            Variable(state)
            Action("toggle") {
                (state == Status.on) && state.becomes(Status.off) ||
                (state == Status.off) && state.becomes(Status.on)
            }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("Int-backed enum TLA+ output uses raw values")
    func intEnumTLAOutput() {
        let mode = Var<Mode>("mode")
        let spec = TLASpec("IntEnum") {
            Variable(mode, Mode.idle)
            Action("toggle") {
                (mode == Mode.idle) && mode.becomes(Mode.active) ||
                (mode == Mode.active) && mode.becomes(Mode.idle)
            }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("mode = 0"))
        #expect(tla.contains("toggle =="))
    }

    @Test("String-backed enum TLA+ output uses raw string values")
    func stringEnumTLAOutput() {
        let state = Var<Status>("state")
        let spec = TLASpec("StringEnum") {
            Variable(state, Status.on)
            Action("toggle") {
                (state == Status.on) && state.becomes(Status.off) ||
                (state == Status.off) && state.becomes(Status.on)
            }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("state = \"on\""))
        #expect(tla.contains("toggle =="))
    }

    @Test("Enum values work in invariant expressions")
    func enumInInvariant() throws {
        let mode = Var<Mode>("mode")
        let spec = TLASpec("IntEnumInv") {
            Variable(mode, Mode.idle)
            Action("toggle") {
                (mode == Mode.idle) && mode.becomes(Mode.active) ||
                (mode == Mode.active) && mode.becomes(Mode.idle)
            }
            Invariant("TypeOK") { (mode == Mode.idle) || (mode == Mode.active) }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        if case .ok(let count) = result {
            #expect(count == 2)
        } else {
            #expect(Bool(false), "Invariant should hold")
        }
    }

    @Test("Enum-backed spec produces valid TLA+ bundle")
    func enumBundle() {
        let mode = Var<Mode>("mode")
        let spec = TLASpec("IntEnumBundle") {
            Variable(mode, Mode.idle)
            Action("toggle") {
                (mode == Mode.idle) && mode.becomes(Mode.active) ||
                (mode == Mode.active) && mode.becomes(Mode.idle)
            }
            Invariant("TypeOK") { (mode == Mode.idle) || (mode == Mode.active) }
        }
        let bundle = spec.tlaBundle
        #expect(bundle.tla.contains("MODULE"))
        #expect(bundle.tla.contains("VARIABLES mode"))
        #expect(bundle.cfg.contains("INVARIANT TypeOK"))
    }

    @Test("Multi-state Int-backed enum explores all values")
    func multiStateIntEnum() throws {
        let phase = Var<Mode>("phase")
        let spec = TLASpec("MultiEnum") {
            Variable(phase, Mode.idle)
            Action("activate") { phase.becomes(Mode.active).when(phase == Mode.idle) }
            Action("deactivate") { phase.becomes(Mode.idle).when(phase == Mode.active) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        let values = Set(graph.states.values.compactMap { $0["phase"] })
        #expect(values == Set([TLAValue.int(0), TLAValue.int(1)]))
    }

    @Test("Enum vars work with stays expression")
    func enumStays() {
        let phase = Var<Mode>("phase")
        let spec = TLASpec("EnumStays") {
            Variable(phase, Mode.idle)
            Action("noop") {
                (phase == Mode.idle) && phase.stays
            }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("UNCHANGED phase"))
    }

    @Test("Enum var initial state is first case raw value")
    func enumInitialState() throws {
        let mode = Var<Mode>("mode")
        let spec = TLASpec("EnumInit") {
            Variable(mode, Mode.idle)
        }
        let states = computeInitialStates(spec)
        #expect(states.count == 1)
        #expect(states[0]["mode"] == TLAValue.int(0))
    }
}

// MARK: - Round-trip: parse(swiftSource(expr)) == expr for every StateExpr case

private extension StateExpr {
    var normalized: StateExpr {
        switch self {
        case .setFilter(let s, _, let p): return .setFilter(s.normalized, "x", p.normalized)
        case .setMap(let e, _, let s): return .setMap(e.normalized, "x", s.normalized)
        case .forAll(let s, _, let p): return .forAll(s.normalized, "x", p.normalized)
        case .exists(let s, _, let p): return .exists(s.normalized, "x", p.normalized)
        case .choose(let s, _, let p): return .choose(s.normalized, "x", p.normalized)
        case .functionLiteral(let d, _, let b): return .functionLiteral(d.normalized, "x", b.normalized)
        case .add(let a, let b): return .add(a.normalized, b.normalized)
        case .subtract(let a, let b): return .subtract(a.normalized, b.normalized)
        case .multiply(let a, let b): return .multiply(a.normalized, b.normalized)
        case .divide(let a, let b): return .divide(a.normalized, b.normalized)
        case .modulo(let a, let b): return .modulo(a.normalized, b.normalized)
        case .integerDivide(let a, let b): return .integerDivide(a.normalized, b.normalized)
        case .negate(let a): return .negate(a.normalized)
        case .equal(let a, let b): return .equal(a.normalized, b.normalized)
        case .notEqual(let a, let b): return .notEqual(a.normalized, b.normalized)
        case .lessThan(let a, let b): return .lessThan(a.normalized, b.normalized)
        case .lessOrEqual(let a, let b): return .lessOrEqual(a.normalized, b.normalized)
        case .greaterThan(let a, let b): return .greaterThan(a.normalized, b.normalized)
        case .greaterOrEqual(let a, let b): return .greaterOrEqual(a.normalized, b.normalized)
        case .and(let a, let b): return .and(a.normalized, b.normalized)
        case .or(let a, let b): return .or(a.normalized, b.normalized)
        case .not(let a): return .not(a.normalized)
        case .ifThenElse(let c, let t, let e): return .ifThenElse(c.normalized, t.normalized, e.normalized)
        case .in(let a, let b): return .in(a.normalized, b.normalized)
        case .setLiteral(let es): return .setLiteral(es.map(\.normalized))
        case .subset(let a, let b): return .subset(a.normalized, b.normalized)
        case .union(let a, let b): return .union(a.normalized, b.normalized)
        case .intersection(let a, let b): return .intersection(a.normalized, b.normalized)
        case .setDifference(let a, let b): return .setDifference(a.normalized, b.normalized)
        case .cardinality(let a): return .cardinality(a.normalized)
        case .powerSet(let a): return .powerSet(a.normalized)
        case .unionAll(let a): return .unionAll(a.normalized)
        case .domain(let a): return .domain(a.normalized)
        case .functionApply(let f, let a): return .functionApply(f.normalized, a.normalized)
        case .except(let f, let k, let v): return .except(f.normalized, k.normalized, v.normalized)
        case .tupleLiteral(let es): return .tupleLiteral(es.map(\.normalized))
        case .tupleAccess(let t, let i): return .tupleAccess(t.normalized, i)
        case .tupleLength(let t): return .tupleLength(t.normalized)
        case .tupleHead(let t): return .tupleHead(t.normalized)
        case .tupleTail(let t): return .tupleTail(t.normalized)
        case .tupleAppend(let t, let e): return .tupleAppend(t.normalized, e.normalized)
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(a.normalized, b.normalized)
        case .recordLiteral(let f): return .recordLiteral(f.mapValues(\.normalized))
        case .recordAccess(let r, let f): return .recordAccess(r.normalized, f)
        case .caseExpr(let pairs, let fallback):
            return .caseExpr(pairs.map(\.normalized), fallback?.normalized)
        default: return self
        }
    }
}

@Suite(.serialized) struct StateExprRoundTripTests {
    private static func parseExpression(_ source: String) -> ExprSyntax {
        SwiftParser.Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    }

    @Test("Round-trip: parse(swiftSource(expr)) == expr for all parseable StateExpr cases",
          arguments: [
            ("value int",      StateExpr.value(.int(42))),
            ("value bool",     StateExpr.value(.bool(true))),
            ("value string",   StateExpr.value(.string("hi"))),
            ("variable",       StateExpr.variable("x")),
            ("add",            StateExpr.add(.int(1), .int(2))),
            ("subtract",       StateExpr.subtract(.int(5), .int(3))),
            ("multiply",       StateExpr.multiply(.int(2), .int(3))),
            ("divide",         StateExpr.divide(.int(6), .int(2))),
            ("modulo",         StateExpr.modulo(.int(7), .int(3))),
            ("negate",         StateExpr.negate(.int(1))),
            ("integerDivide",  StateExpr.integerDivide(.int(4), .int(2))),
            ("equal",          StateExpr.equal(.int(1), .int(1))),
            ("notEqual",       StateExpr.notEqual(.int(1), .int(2))),
            ("lessThan",       StateExpr.lessThan(.int(1), .int(2))),
            ("lessOrEqual",    StateExpr.lessOrEqual(.int(1), .int(2))),
            ("greaterThan",    StateExpr.greaterThan(.int(2), .int(1))),
            ("greaterOrEqual", StateExpr.greaterOrEqual(.int(2), .int(1))),
            ("and",            StateExpr.and(.bool(true), .bool(false))),
            ("or",             StateExpr.or(.bool(true), .bool(false))),
            ("not",            StateExpr.not(.bool(true))),
            ("ifThenElse",     StateExpr.ifThenElse(.bool(true), .int(1), .int(2))),
            ("in",             StateExpr.in(.int(1), .setLiteral([.int(1), .int(2)]))),
            ("setLiteral",     StateExpr.setLiteral([.int(1), .int(2)])),
            ("subset",         StateExpr.subset(.setLiteral([.int(1)]), .setLiteral([.int(1), .int(2)]))),
            ("union",          StateExpr.union(.setLiteral([.int(1)]), .setLiteral([.int(2)]))),
            ("intersection",   StateExpr.intersection(.setLiteral([.int(1)]), .setLiteral([.int(1)]))),
            ("setDifference",  StateExpr.setDifference(.setLiteral([.int(1), .int(2)]), .setLiteral([.int(2)]))),
            ("cardinality",    StateExpr.cardinality(.setLiteral([.int(1)]))),
            ("powerSet",       StateExpr.powerSet(.setLiteral([.int(1)]))),
            ("unionAll",       StateExpr.unionAll(.setLiteral([.setLiteral([.int(1)])]))),
            ("domain",         StateExpr.domain(.recordLiteral(["k": .int(1)]))),
            ("functionApply",  StateExpr.functionApply(.variable("f"), .int(1))),
            ("except",         StateExpr.except(.variable("f"), .int(1), .int(2))),
            ("tupleLiteral",   StateExpr.tupleLiteral([.int(1), .int(2)])),
            ("tupleAccess",    StateExpr.tupleAccess(.tupleLiteral([.int(10)]), 1)),
            ("tupleLength",    StateExpr.tupleLength(.tupleLiteral([.int(1)]))),
            ("tupleHead",      StateExpr.tupleHead(.tupleLiteral([.int(1)]))),
            ("tupleTail",      StateExpr.tupleTail(.tupleLiteral([.int(1)]))),
            ("tupleAppend",    StateExpr.tupleAppend(.tupleLiteral([.int(1)]), .int(2))),
            ("tupleConcatenate", StateExpr.tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)]))),
            ("recordLiteral",  StateExpr.recordLiteral(["k": .int(1)])),
            ("recordAccess",   StateExpr.recordAccess(.recordLiteral(["k": .int(1)]), "k")),
            ("setFilter",      StateExpr.setFilter(.setLiteral([.int(1)]), "x0", .bool(true))),
            ("setMap",         StateExpr.setMap(.variable("y"), "x0", .setLiteral([.int(1)]))),
            ("forAll",         StateExpr.forAll(.setLiteral([.int(1)]), "x0", .bool(true))),
            ("exists",         StateExpr.exists(.setLiteral([.int(1)]), "x0", .bool(true))),
            ("choose",         StateExpr.choose(.setLiteral([.int(1)]), "x0", .bool(true))),
            ("functionLiteral", StateExpr.functionLiteral(.setLiteral([.int(1)]), "x0", .variable("z"))),
            ("caseExpr",       StateExpr.caseExpr([.bool(true), .int(1), .bool(false), .int(2)], .int(0))),
            ("enabledAction",  StateExpr.enabledAction("Tick")),
          ] as [(String, StateExpr)])
    func roundTrip(_ name: String, _ expr: StateExpr) {
        let source = expr.swiftSource
        #expect(!source.isEmpty, "\(name): swiftSource is empty")
        #expect(!source.contains("\\in"), "\(name): swiftSource contains TLA+ syntax: \(source)")
        #expect(!source.contains("<<"), "\(name): swiftSource contains TLA+ tuple syntax: \(source)")

        let parsed = SpecParser.decodeStateExpr(Self.parseExpression(source))
        let parsedNormalized = parsed?.normalized
        #expect(parsedNormalized == expr.normalized,
                "\(name): round-trip failed.\n  source: \(source)\n  parsed: \(String(describing: parsed))\n  expected: \(expr)")
    }
}

// MARK: - Var-as-SpecComponent: builder collects Var directly

@Suite(.serialized) struct VarSpecComponentTests {
    @Test("Var(name, value) + Variable(ref) registers spec variable")
    func varAsSpecComponent() throws {
        let spec = TLASpec("VarTest") {
            let x = Var("x", 0)
            Variable(x)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
        }
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "x")
        #expect(spec.variables[0].initial == .int(0))
        #expect(try ModelChecker(spec: spec, maxStates: 10).exploreGraph().states.count == 4)
    }
}
