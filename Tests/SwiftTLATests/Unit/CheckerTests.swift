import XCTest
@_spi(Internal) import SwiftTLA

final class CheckerTests: XCTestCase {
    func testCounterInvariantViolated() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Action("Inc") { x.next == x + 1 }
            Action("Dec") { x.next == x - 1 }
            Invariant("NeverNegative") { !(x < 0) }
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
            Action("Inc") { x.next == x + 1 }
            Invariant("NonNeg") { x >= 0 }
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
            Action("Inc") { x.next == x + 1 }
            Invariant("NonNeg") { x >= 0 }
        }
        XCTAssertEqual(spec.invariants.count, 1)
    }

    func testEnabledAction() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("EnabledTest") {
            Variable(x, 0)
            Action("CanInc") { (x < 3) && (x.next == x + 1) }
            Invariant("IncUntil3") { (x < 3) == enabled("CanInc") }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10).check()
        if case .invariantViolated = result { XCTFail("ENABLED check should pass") }
    }

    func testModelCheckWithConstants() throws {
        let spec = TLASpec("Param") {
            Variable(Var<Int>("x"), TLAValue.constant("Limit"))
            Constant("Limit", 2)
            Action("Tick") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Invariant("Below3") { Var<Int>("x") <= 2 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10).check()
        if case .invariantViolated = result { } else { XCTFail("Expected violation") }
    }
}
