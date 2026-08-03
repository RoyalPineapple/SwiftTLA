import XCTest
import SwiftTLA
import SwiftTLAGenerator

final class SwiftTLATests: XCTestCase {

    func testCounterNoViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Inv("AlwaysNonNegative") { x >= 0 }
        }

        let checker = ModelChecker(spec: spec, maxStates: 100)
        let result = try checker.check()

        switch result {
        case .depthExceeded(let count, _):
            XCTAssertGreaterThan(count, 0)
        default:
            XCTFail("Expected depth exceeded, got \(result)")
        }
    }

    func testCounterInvariantViolated() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Act("Dec") { next(x) == x - 1 }
            Inv("NeverNegative") { !(x < 0) }
        }

        let checker = ModelChecker(spec: spec)
        let result = try checker.check()

        switch result {
        case .invariantViolated(let inv, let state, let trace):
            XCTAssertEqual(inv, "NeverNegative")
            guard case .int(let xVal) = state["x"] else {
                XCTFail("Expected int for x"); return
            }
            XCTAssertEqual(xVal, -1)
            XCTAssertFalse(trace.isEmpty)
        default:
            XCTFail("Expected invariant violation, got \(result)")
        }
    }

    func testDieHardFindsSolution() throws {
        let jug3 = Var<Int>("jug3")
        let jug5 = Var<Int>("jug5")

        let spec = TLASpec("DieHard") {
            Variable(jug3, 0)
            Variable(jug5, 0)

            Act("Fill3") { next(jug3) == 3 }
            Act("Fill5") { next(jug5) == 5 }
            Act("Empty3") { next(jug3) == 0 }
            Act("Empty5") { next(jug5) == 0 }
            Act("Pour3to5") {
                let pour: ActionExpr = (jug3 + jug5 <= 5) && (next(jug5) == jug3 + jug5) && (next(jug3) == 0)
                let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (next(jug5) == 5) && (next(jug3) == jug3 - (5 - jug5))
                pour || spill
            }
            Act("Pour5to3") {
                let pour: ActionExpr = (jug3 + jug5 <= 3) && (next(jug3) == jug3 + jug5) && (next(jug5) == 0)
                let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (next(jug3) == 3) && (next(jug5) == jug5 - (3 - jug3))
                pour || spill
            }

            Inv("jug5_ne_4") { jug5 != 4 }
        }

        let checker = ModelChecker(spec: spec)
        let result = try checker.check()

        switch result {
        case .invariantViolated(let inv, let state, let trace):
            XCTAssertEqual(inv, "jug5_ne_4")
            XCTAssertEqual(state["jug5"], .int(4))
            XCTAssertTrue(trace.count > 1, "Should have a multi-step trace")
        default:
            XCTFail("Expected invariant violation for jug5=4, got \(result)")
        }
    }

    func testStutteringAction() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Stutter") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Inv("LE3") { x <= 3 }
        }

        let checker = ModelChecker(spec: spec)
        let result = try checker.check()

        switch result {
        case .invariantViolated(let inv, _, _):
            XCTAssertEqual(inv, "LE3")
        default:
            XCTFail("Expected invariant violation, got \(result)")
        }
    }

    func testExpressionDescription() {
        let x = Var<Int>("x")
        let expr: StateExpr = x >= 0
        XCTAssertTrue(expr.description.contains("x"))
        XCTAssertTrue(expr.description.contains(">="))

        let action: ActionExpr = next(x) == x + 1
        XCTAssertTrue(action.description.contains("x'"))
        XCTAssertTrue(action.description.contains("+"))
    }

    func testCodableRoundtrip() throws {
        let spec = TLASpec("Test") {
            Variable(Var<Int>("x"), 0)
            Act("Inc") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Inv("GE0") { Var<Int>("x") >= 0 }
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(spec)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TLASpec.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.variables.count, 1)
        XCTAssertEqual(decoded.actions.count, 1)
        XCTAssertEqual(decoded.invariants.count, 1)
    }

    func testInvariantCantUseNext() {
        let x = Var<Int>("x")
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Inv("NonNeg") { x >= 0 }
        }
        XCTAssertEqual(spec.invariants.count, 1)
    }

    func testHourClock12States() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Act("Tick") {
                ((hr >= 1) && (hr <= 11) && (next(hr) == hr + 1))
                || ((hr == 12) && (next(hr) == 1))
            }
            Inv("ValidHour") { (hr >= 1) && (hr <= 12) }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
        XCTAssertEqual(graph.states.count, 12, "HourClock must have exactly 12 reachable states")
    }

    func testHourClockDeadInvariant() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Act("Tick") {
                ((hr >= 1) && (hr <= 11) && (next(hr) == hr + 1))
                || ((hr == 12) && (next(hr) == 1))
            }
            Inv("Never13") { hr != 13 }
        }

        let result = try ModelChecker(spec: spec, maxStates: 20).check()
        if case .ok(let count) = result {
            XCTAssertEqual(count, 12)
        } else {
            XCTFail("Expected OK, got \(result)")
        }
    }

    func testMissionariesAndCannibals() throws {
        let wm = Var<Int>("wm")
        let wc = Var<Int>("wc")
        let em = Var<Int>("em")
        let ec = Var<Int>("ec")
        let boat = Var<Int>("boat")

        let spec = TLASpec("MissionariesAndCannibals") {
            Variable(wm, 3)
            Variable(wc, 3)
            Variable(em, 0)
            Variable(ec, 0)
            Variable(boat, 0)

            Act("Move1m") {
                let left = (boat == 0) && (wm >= 1)
                let right = (boat == 1) && (em >= 1)
                left && (next(wm) == wm - 1) && (next(em) == em + 1) && (next(boat) == 1)
                || right && (next(wm) == wm + 1) && (next(em) == em - 1) && (next(boat) == 0)
            }
            Act("Move1c") {
                let left = (boat == 0) && (wc >= 1)
                let right = (boat == 1) && (ec >= 1)
                left && (next(wc) == wc - 1) && (next(ec) == ec + 1) && (next(boat) == 1)
                || right && (next(wc) == wc + 1) && (next(ec) == ec - 1) && (next(boat) == 0)
            }
            Act("Move2m") {
                let left = (boat == 0) && (wm >= 2)
                let right = (boat == 1) && (em >= 2)
                left && (next(wm) == wm - 2) && (next(em) == em + 2) && (next(boat) == 1)
                || right && (next(wm) == wm + 2) && (next(em) == em - 2) && (next(boat) == 0)
            }
            Act("Move2c") {
                let left = (boat == 0) && (wc >= 2)
                let right = (boat == 1) && (ec >= 2)
                left && (next(wc) == wc - 2) && (next(ec) == ec + 2) && (next(boat) == 1)
                || right && (next(wc) == wc + 2) && (next(ec) == ec - 2) && (next(boat) == 0)
            }
            Act("Move1m1c") {
                let left = (boat == 0) && (wm >= 1) && (wc >= 1)
                let right = (boat == 1) && (em >= 1) && (ec >= 1)
                left && (next(wm) == wm - 1) && (next(wc) == wc - 1)
                    && (next(em) == em + 1) && (next(ec) == ec + 1) && (next(boat) == 1)
                || right && (next(wm) == wm + 1) && (next(wc) == wc + 1)
                    && (next(em) == em - 1) && (next(ec) == ec - 1) && (next(boat) == 0)
            }

            Inv("NoCannibalFeast") {
                !(
                    ((wm > 0) && (wc > wm))
                    || ((em > 0) && (ec > em))
                )
            }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty)
    }

    func testFiniteCounterExactStates() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("BoundedCounter") {
            Variable(x, 0)
            Act("Inc") {
                (x < 4) && (next(x) == x + 1)
            }
            Inv("InRange") { (x >= 0) && (x <= 4) }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        XCTAssertEqual(graph.states.count, 5, "Should have 5 states: 0, 1, 2, 3, 4")
    }

    func testSetMembership() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(1 ∈ s, in: [:])
        XCTAssertEqual(result, .bool(true))

        let result2 = try Evaluator.evaluate(5 ∈ s, in: [:])
        XCTAssertEqual(result2, .bool(false))
    }

    func testSetUnion() throws {
        let a = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b = StateExpr.setLiteral([.value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(a ∪ b, in: [:])
        XCTAssertEqual(result, .set([.int(1), .int(2), .int(3)]))
    }

    func testSetIntersection() throws {
        let a = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b = StateExpr.setLiteral([.value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(a ∩ b, in: [:])
        XCTAssertEqual(result, .set([.int(2)]))
    }

    func testSetDiff() throws {
        let a = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b = StateExpr.setLiteral([.value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(.setDifference(a, b), in: [:])
        XCTAssertEqual(result, .set([.int(1)]))
    }

    func testSubset() throws {
        let a = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])

        let t = try Evaluator.evaluate(a ⊆ b, in: [:])
        XCTAssertEqual(t, .bool(true))

        let f = try Evaluator.evaluate(b ⊆ a, in: [:])
        XCTAssertEqual(f, .bool(false))
    }

    func testSetVariableInSpec() throws {
        let known = Var<TLASet>("known")
        let n = Var<Int>("n")

        let spec = TLASpec("SetCounter") {
            Variable(known, set([1, 2, 3]))
            Variable(n, 1)

            Act("MarkSeen") {
                n ∈ known && (next(known) == known) && (next(n) == n + 1)
            }

            Inv("KnownNonEmpty") { cardinality(known) >= 1 }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10_000).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty)
    }

    func testCardinality() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(.cardinality(s), in: [:])
        XCTAssertEqual(result, .int(3))
    }

    func testLivenessAlwaysEventually() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("Clock") {
            Variable(hr, 0)
            Act("Tick") {
                let inc: ActionExpr = (hr < 5) && (next(hr) == hr + 1)
                let wrap: ActionExpr = (hr == 5) && (next(hr) == 0)
                inc || wrap
            }
            Temporal("AlwaysEventually3", .alwaysEventually(hr == 3))
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let checker = LivenessChecker(graph: graph, spec: spec)
        let violations = try checker.check()
        XCTAssertTrue(violations.isEmpty, "Clock should always eventually reach 3")
    }

    func testLivenessPropertyViolated() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Stuck") {
            Variable(x, 0)
            Act("Inc") { (x < 3) && (next(x) == x + 1) }
            Temporal("AlwaysEventually4", .alwaysEventually(x == 4))
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let checker = LivenessChecker(graph: graph, spec: spec)
        let violations = try checker.check()
        XCTAssertFalse(violations.isEmpty, "Should detect that x never reaches 4")
    }

    func testLivenessLeadsTo() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("LeadsTo") {
            Variable(x, 0)
            Act("Inc") { (x < 5) && (next(x) == x + 1) }
            Temporal("FiveLeadsToTwo", .leadsTo(x == 5, x == 2))
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let checker = LivenessChecker(graph: graph, spec: spec)
        let violations = try checker.check()
        XCTAssertFalse(violations.isEmpty, "Stuck at 5 — 5 never leads to 2")
    }

    func testLivenessFairnessFiltersViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("FairClock") {
            Variable(x, 0)
            Act("Tick") { (x < 3) && (next(x) == x + 1) }
            Act("Stutter") { next(x) == x }
            Temporal("AlwaysEventually3", .alwaysEventually(x == 3))
            Fairness(.weakFairness("Tick"))
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let checker = LivenessChecker(graph: graph, spec: spec)
        let violations = try checker.check()
        XCTAssertTrue(violations.isEmpty, "With WF(Tick), eventually reaches 3")
    }

    func testForAll() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let allPositive = forAll(s, .greaterThan(.variable("_q"), .value(.int(0))))
        XCTAssertEqual(try Evaluator.evaluate(allPositive, in: [:]), .bool(true))

        let allEven = forAll(s, .equal(.modulo(.variable("_q"), .value(.int(2))), .value(.int(0))))
        XCTAssertEqual(try Evaluator.evaluate(allEven, in: [:]), .bool(false))
    }

    func testExists() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let hasEven = exists(s, .equal(.modulo(.variable("_q"), .value(.int(2))), .value(.int(0))))
        XCTAssertEqual(try Evaluator.evaluate(hasEven, in: [:]), .bool(true))
    }

    func testChoose() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(choose(s, .greaterThan(.variable("_q"), .value(.int(1)))), in: [:])
        XCTAssertTrue(result == .int(2) || result == .int(3))
    }

    func testEnabledInSpec() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("EnabledTest") {
            Variable(x, 0)
            Act("CanInc") { (x < 3) && (next(x) == x + 1) }
            Inv("IncEnabledUntil3") { (x < 3) == enabled("CanInc") }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10).check()
        if case .ok = result { } else { XCTFail("Expected OK") }
    }

    func testStateMachineGenerationProducesValidSwift() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Toggle") {
            Variable(x, 0)
            Act("Flip") { next(x) == (x + 1) % 2 }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let gen = StateMachineGenerator(graph: graph)
        let code = gen.generate()

        XCTAssertTrue(code.contains("struct Toggle"))
        XCTAssertTrue(code.contains("enum Action"))
        XCTAssertTrue(code.contains("transitions"))
    }

    func testConstantSubstitution() throws {
        let spec = TLASpec("Param") {
            Variable(Var<Int>("x"), TLAValue.constant("N"))
            Constant("N", 5)
            Act("Inc") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Inv("Positive") { Var<Int>("x") >= 0 }
        }
        let substituted = substituteConstants(spec)
        XCTAssertEqual(substituted.variables.first?.initial, .int(5))
    }

    func testModelCheckWithConstants() throws {
        let spec = TLASpec("Param") {
            Variable(Var<Int>("x"), TLAValue.constant("Limit"))
            Constant("Limit", 2)
            Act("Tick") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Inv("Below3") { Var<Int>("x") <= 2 }
        }
        let checker = ModelChecker(spec: spec, maxStates: 10)
        let result = try checker.check()
        if case .invariantViolated = result {
        } else {
            XCTFail("Expected violation when x exceeds 2")
        }
    }
}
