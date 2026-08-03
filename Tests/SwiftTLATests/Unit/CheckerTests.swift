import XCTest
import SwiftTLA

final class CheckerTests: XCTestCase {
    func testCounterInvariantViolated() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Act("Dec") { next(x) == x - 1 }
            Inv("NeverNegative") { !(x < 0) }
        }
        let result = try ModelChecker(spec: spec).check()
        if case .invariantViolated(let inv, let state, _) = result {
            XCTAssertEqual(inv, "NeverNegative")
            XCTAssertEqual(state["x"], .int(-1))
        } else { XCTFail("Expected violation") }
    }

    func testCounterNoViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Act("Inc") { next(x) == x + 1 }
            Inv("NonNeg") { x >= 0 }
        }
        let checker = ModelChecker(spec: spec, maxStates: 100)
        let result = try checker.check()
        if case .depthExceeded(let count, _) = result {
            XCTAssertGreaterThan(count, 0)
        } else { XCTFail("Expected depth exceeded") }
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

    func testEnabledAction() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("EnabledTest") {
            Variable(x, 0)
            Act("CanInc") { (x < 3) && (next(x) == x + 1) }
            Inv("IncUntil3") { (x < 3) == enabled("CanInc") }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10).check()
        if case .invariantViolated = result { XCTFail("ENABLED check should pass") }
    }

    func testModelCheckWithConstants() throws {
        let spec = TLASpec("Param") {
            Variable(Var<Int>("x"), TLAValue.constant("Limit"))
            Constant("Limit", 2)
            Act("Tick") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Inv("Below3") { Var<Int>("x") <= 2 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10).check()
        if case .invariantViolated = result { } else { XCTFail("Expected violation") }
    }
}
