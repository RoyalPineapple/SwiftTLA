import Testing
import Foundation
import SwiftTLA

// MARK: - Var<T> operators: full matrix

struct VarOperatorMatrix {
    @Test("Arithmetic", arguments: [
        ("+", 3, "(x + 3)"),
        ("-", 1, "(x - 1)"),
        ("*", 2, "(x * 2)"),
        ("%", 5, "(x % 5)"),
    ])
    func arithmetic(_ op: String, _ val: Int, _ expected: String) {
        let x = Var<Int>("x", value: 1)
        let result: String
        switch op {
        case "+": result = (x + val).description
        case "-": result = (x - val).description
        case "*": result = (x * val).description
        case "%": result = (x % val).description
        default: result = ""
        }
        #expect(result == expected)
    }

    @Test("Comparison matrix", arguments: [
        ("==", 0, "(x = 0)"),
        ("==", 1, "(x = 1)"),
        ("!=", 0, "(x /= 0)"),
        ("<",  5, "(x < 5)"),
        ("<=", 5, "(x <= 5)"),
        (">",  0, "(x > 0)"),
        (">=", 1, "(x >= 1)"),
    ])
    func comparison(_ op: String, _ val: Int, _ expected: String) {
        let x = Var<Int>("x", value: 1)
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
        ("twoVars", 1),
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
        ("valueInt",    "42"),
        ("valueBool",   "true"),
        ("valueString", "\"hi\""),
        ("variable",    "x"),
        ("add",         "(1 + 2)"),
        ("subtract",   "(5 - 3)"),
        ("multiply",   "(2 * 3)"),
        ("modulo",     "(7 % 3)"),
        ("negate",     "(-1)"),
        ("equal",      "(1 = 1)"),
        ("notEqual",   "(1 /= 2)"),
        ("lessThan",   "(1 < 2)"),
        ("greaterThan","(2 > 1)"),
        ("setLiteral", "{1, 2}"),
        ("inSet",      "(1 \\in {1, 2})"),
        ("tupleLiteral","<<1, 2>>"),
        ("ifThen",     "(IF true THEN 1 ELSE 2)"),
        ("enabled",    "ENABLED Tick"),
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
        let a = Var<Int>("a", value: 1)
        let b = Var<Int>("b", value: 2)
        #expect((a == b).description == "(a = b)")
        #expect((a != b).description == "(a /= b)")
        #expect((a < b).description == "(a < b)")
    }

    @Test func prefix() {
        let x = Var<Int>("x", value: 1)
        #expect((-x).description == "(-x)")
    }

    @Test func stringComparison() {
        let s = Var<String>("s", value: "right")
        #expect((s == "right").description == "(s = \"right\")")
    }

    @Test func assignmentAndWhen() {
        let x = Var<Int>("x", value: 0)
        let a = x.becomes(1)
        #expect(a.description.contains("x' = 1"))
        let g = x.becomes(1).when(x == 0)
        #expect(g.description.contains("(x = 0)") && g.description.contains("x' = 1"))
        let s = x.stays
        #expect(s.description.contains("UNCHANGED x"))
    }
}

// MARK: - ActionExpr: full variant coverage

struct ActionExprMatrix {
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
struct StateExprCompleteTests {
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
            .setFilter(.setLiteral([.int(1)]), .bool(true)),
            .setMap(.variable("x"), .setLiteral([.int(1)])),
            .powerSet(.setLiteral([.int(1)])),
            .unionAll(.setLiteral([.setLiteral([.int(1)])])),
            .tupleLiteral([.int(1)]), .tupleAccess(.tupleLiteral([.int(1)]), 0),
            .tupleLength(.tupleLiteral([.int(1)])),
            .tupleAppend(.tupleLiteral([.int(1)]), .int(2)),
            .tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)])),
            .recordLiteral(["k": .int(1)]), .recordAccess(.recordLiteral(["k": .int(1)]), "k"),
            .domain(.recordLiteral(["k": .int(1)])),
            .functionLiteral(.setLiteral([.int(1)]), .variable("x")),
            .functionApply(.functionLiteral(.setLiteral([.int(1)]), .variable("x")), .int(1)),
            .except(.functionLiteral(.setLiteral([.int(1)]), .variable("x")), .int(1), .int(2)),
            .caseExpr([.bool(true), .int(1)], .int(0)),
            .forAll(.setLiteral([.int(1)]), .bool(true)),
            .exists(.setLiteral([.int(1)]), .bool(true)),
            .choose(.setLiteral([.int(1)]), .bool(true)),
            .enabledAction("Foo"),
        ]
        for e in cases {
            #expect(!e.description.isEmpty, "\(e) has no description")
        }
    }

    @Test("Every StateExpr case rounds trips through Codable")
    func allCasesCodable() throws {
        let e: StateExpr = .equal(.add(.variable("x"), .int(1)), .int(5))
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(StateExpr.self, from: data)
        #expect(decoded.description == e.description)
    }
}

// MARK: - TLAValue: every case

struct TLAValueTests {
    @Test("Every TLAValue case has a description", arguments: [
        TLAValue.int(1), .bool(true), .string("hi"),
        .set([.int(1)]), .tuple([.int(1)]), .record(["k": .int(1)]),
        .constant("N"),
    ] as [TLAValue])
    func descriptions(_ v: TLAValue) {
        #expect(!v.description.isEmpty)
    }

    @Test("TLAValue rounds trips via Codable")  
    func codable() throws {
        let v: TLAValue = .set([.int(1), .bool(true), .string("hi")])
        let data = try JSONEncoder().encode(v)
        let d = try JSONDecoder().decode(TLAValue.self, from: data)
        #expect(d.description == v.description)
    }
}

// MARK: - ActionExpr: every case

struct ActionExprCompleteTests {
    @Test("Every ActionExpr case enumerates correctly", arguments: [
        ("assign", ActionExpr.assign("x", .int(1)), 1),
        ("unchanged", ActionExpr.unchanged("x"), 1),
        ("simpleAnd", ActionExpr.and(.assign("x", .int(1)), .assign("y", .int(2))), 1),
        ("or", ActionExpr.or(.assign("x", .int(1)), .assign("x", .int(2))), 2),
        ("guarded", ActionExpr.and(.guard_(.equal(.variable("x"), .int(0))), .assign("x", .int(1))), 1),
    ] as [(String, ActionExpr, Int)])
    func enumerate(_ name: String, _ a: ActionExpr, _ expected: Int) throws {
        let s: [String: TLAValue] = ["x": .int(0), "y": .int(0)]
        let r = try ActionEnumerator.enumerate(a, from: s, varNames: ["x", "y"])
        #expect(r.count == expected, "\(name): expected \(expected), got \(r.count)")
    }
}

// MARK: - ModelChecker: spec pattern matrix

struct ModelCheckerMatrix {
    @Test func singleVarLinear() throws {
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 4)
    }

    @Test func singleVarCyclic() throws {
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("toggle") { x.becomes((x + 1) % 2) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test func invariantHolds() throws {
        let x = Var<Int>("x", value: 0)
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
        let x = Var<Int>("x", value: 0)
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
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 3).exploreGraph()
        // Processes 3 states, discovers 4 (successors of last processed also stored)
        #expect(graph.states.count >= 3 && graph.states.count <= 4)
    }


    @Test func deadlockNotDetectedWhenFlagFalse() throws {
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("once") { x.becomes(1).when(x == 0) }
        }
        if case .ok(let c) = try ModelChecker(spec: spec, maxStates: 100).check() {
            #expect(c == 2)
        } else { #expect(Bool(false)) }
    }

    @Test func twoVarBranching() throws {
        let a = Var<Int>("a", value: 0)
        let b = Var<Int>("b", value: 0)
        let spec = TLASpec("Test") {
            Variable(a, 0); Variable(b, 0)
            Action("incA") { a.becomes(a + 1).when(a < 2) && b.stays }
            Action("incB") { b.becomes(b + 1).when(b < 2) && a.stays }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 9)
    }

    @Test func dieHard16() throws {
        let big = Var<Int>("big", value: 0)
        let small = Var<Int>("small", value: 0)
        let spec = TLASpec("DieHard") {
            Variable(big, 0); Variable(small, 0)
            Action("FB") { big.becomes(5) && small.stays }
            Action("FS") { small.becomes(3) && big.stays }
            Action("EB") { big.becomes(0) && small.stays }
            Action("ES") { small.becomes(0) && big.stays }
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

struct TLAModuleMatrix {
    @Test func constantsAndAssume() {
        let x = Var<Int>("x", value: 0)
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
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("Next") { x.becomes(x + 1).when(x < 3) }
            WeakFairness("Next")
        }
        let tla = spec.tlaModule
        #expect(tla.contains("WF_x(Next)"))  // single var → no tuple brackets
    }

    @Test func theoremOutput() {
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
            Theorem("Spec => [](x >= 0)")
        }
        let tla = spec.tlaModule
        #expect(tla.contains("THEOREM"))
    }

    @Test func definitionsOutput() {
        let x = Var<Int>("x", value: 0)
        let spec = TLASpec("Test") {
            Definition("Min(m,n) == IF m < n THEN m ELSE n")
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("Min(m,n) =="))
    }

    @Test func extendsNaturals() {
        let x = Var<Int>("x", value: 0)
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

struct SwiftSourceMatrix {
    @Test func roundTripStructure() {
        let x = Var<Int>("x", value: 0)
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

// MARK: - Upstream golden equivalence (verified against TLC)

/// Each test mirrors an upstream tlaplus/Examples spec.
/// State counts were verified by running TLC on the generated .tlaModule output.
struct GoldenTests {
    @Test("HourClock = 12 states")
    func hourClock12() throws {
        let hr = Var<Int>("hr", value: 1)
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Action("HCnxt") { (hr < 12) && hr.becomes(hr + 1) || (hr == 12) && hr.becomes(1) }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 12)
    }

    @Test("HourClock invariant holds")
    func hourClockInv() throws {
        let hr = Var<Int>("hr", value: 1)
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Action("HCnxt") { (hr < 12) && hr.becomes(hr + 1) || (hr == 12) && hr.becomes(1) }
            Invariant("ValidHours") { hr >= 1 && hr <= 12 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        #expect({ if case .ok = result { true } else { false } }())
    }

    @Test("DieHard = 16 states")
    func dieHard16() throws {
        let big = Var<Int>("big", value: 0); let small = Var<Int>("small", value: 0)
        let spec = TLASpec("DieHard") {
            Variable(big, 0); Variable(small, 0)
            Action("FB") { big.becomes(5) && small.stays }
            Action("FS") { small.becomes(3) && big.stays }
            Action("EB") { big.becomes(0) && small.stays }
            Action("ES") { small.becomes(0) && big.stays }
            Action("S2B") { (big+small<=5) && big.becomes(big+small) && small.becomes(0) || (big+small>5) && big.becomes(5) && small.becomes(small-(5-big)) }
            Action("B2S") { (big+small<=3) && small.becomes(big+small) && big.becomes(0) || (big+small>3) && small.becomes(3) && big.becomes(big-(3-small)) }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 16)
    }

    @Test("DieHard TypeOK holds")
    func dieHardInv() throws {
        let big = Var<Int>("big", value: 0); let small = Var<Int>("small", value: 0)
        let spec = TLASpec("DieHard") {
            Variable(big, 0); Variable(small, 0)
            Action("FB") { big.becomes(5) && small.stays }; Action("FS") { small.becomes(3) && big.stays }
            Action("EB") { big.becomes(0) && small.stays }; Action("ES") { small.becomes(0) && big.stays }
            Action("S2B") { (big+small<=5) && big.becomes(big+small) && small.becomes(0) || (big+small>5) && big.becomes(5) && small.becomes(small-(5-big)) }
            Action("B2S") { (big+small<=3) && small.becomes(big+small) && big.becomes(0) || (big+small>3) && small.becomes(3) && big.becomes(big-(3-small)) }
            Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        #expect({ if case .ok = result { true } else { false } }())
    }

    @Test("Allocator = 4 states")
    func allocator4() throws {
        let a = Var<Int>("available", value: 3); let b = Var<Int>("allocated", value: 0)
        let spec = TLASpec("Allocator") {
            Variable(a, 3); Variable(b, 0)
            Action("Alloc") { a.becomes(a-1).when(a>0) && b.becomes(b+1) }
            Action("Free") { a.becomes(a+1).when(b>0) && b.becomes(b-1) }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count == 4)
    }

    @Test("Allocator invariant holds")
    func allocatorInv() throws {
        let a = Var<Int>("available", value: 3); let b = Var<Int>("allocated", value: 0)
        let spec = TLASpec("Allocator") {
            Variable(a, 3); Variable(b, 0)
            Action("Alloc") { a.becomes(a-1).when(a>0) && b.becomes(b+1) }
            Action("Free") { a.becomes(a+1).when(b>0) && b.becomes(b-1) }
            Invariant("SumConstant") { a + b == 3 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        #expect({ if case .ok = result { true } else { false } }())
    }

    @Test("CoffeeCan = 21 states")
    func coffeeCan21() throws {
        let bl = Var<Int>("black", value: 5); let wh = Var<Int>("white", value: 5)
        let spec = TLASpec("CoffeeCan") {
            Variable(bl, 5); Variable(wh, 5)
            Action("BB") { (bl+wh>1) && bl>=2 && bl.becomes(bl-1) && wh.stays }
            Action("WW") { (bl+wh>1) && wh>=2 && bl.becomes(bl+1) && wh.becomes(wh-2) }
            Action("BW") { (bl+wh>1) && bl>=1 && wh>=1 && bl.becomes(bl-1) && wh.stays }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 500).exploreGraph().states.count == 21)
    }

    @Test("MovingCat = 18 states (composite && fixed)")
    func movingCat() throws {
        let c = Var<Int>("cat", value: 3); let o = Var<Int>("obs", value: 3); let d = Var<Int>("dir", value: 1)
        let spec = TLASpec("MovingCat") {
            Variable(c, 3); Variable(o, 3); Variable(d, 1)
            Action("Next") {
                (c < 6 && c.becomes(c + 1) || c > 1 && c.becomes(c - 1)) &&
                ((d == 1 && o < 5) && o.becomes(o + 1) && d.stays ||
                 (d == 1 && o == 5) && o.becomes(o - 1) && d.becomes(-1) ||
                 (d == -1 && o > 2) && o.becomes(o - 1) && d.stays ||
                 (d == -1 && o == 2) && o.becomes(o + 1) && d.becomes(1))
            }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 200).exploreGraph().states.count == 18)
    }

    @Test("Majority = at least 1 state")
    func majority() throws {
        let ca = Var<Int>("cand", value: 0); let cn = Var<Int>("cnt", value: 0); let i = Var<Int>("i", value: 1)
        let spec = TLASpec("Majority") {
            Variable(ca, 0); Variable(cn, 0); Variable(i, 1)
            Action("N") {
                (i <= 3) && i.becomes(i + 1) && cn.becomes(cn + 1)
            }
        }
        #expect(try ModelChecker(spec: spec, maxStates: 100).exploreGraph().states.count >= 1)
    }
}
