import XCTest
import SwiftTLA

final class ExpressionTests: XCTestCase {
    func testSetMembership() throws {
        let s = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        XCTAssertEqual(try Evaluator.evaluate(1 ∈ s, in: [:]), .bool(true))
        XCTAssertEqual(try Evaluator.evaluate(5 ∈ s, in: [:]), .bool(false))
    }

    func testSetUnionIntersectionDifference() throws {
        let a: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b: StateExpr = StateExpr.setLiteral([.value(.int(2)), .value(.int(3))])
        XCTAssertEqual(try Evaluator.evaluate(a ∪ b, in: [:]), .set([.int(1), .int(2), .int(3)]))
        XCTAssertEqual(try Evaluator.evaluate(a ∩ b, in: [:]), .set([.int(2)]))
        XCTAssertEqual(try Evaluator.evaluate(setDifference(a, b), in: [:]), .set([.int(1)]))
    }

    func testSubsetAndCardinality() throws {
        let a: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2))])
        let b: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        XCTAssertEqual(try Evaluator.evaluate(a ⊆ b, in: [:]), .bool(true))
        XCTAssertEqual(try Evaluator.evaluate(b ⊆ a, in: [:]), .bool(false))
        XCTAssertEqual(try Evaluator.evaluate(.cardinality(b), in: [:]), .int(3))
    }

    func testForAll() throws {
        let s: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let allPositive = forAll(s, .greaterThan(.variable("_q"), .value(.int(0))))
        XCTAssertEqual(try Evaluator.evaluate(allPositive, in: [:]), .bool(true))
    }

    func testExists() throws {
        let s: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let hasEven = exists(s, .equal(.modulo(.variable("_q"), .value(.int(2))), .value(.int(0))))
        XCTAssertEqual(try Evaluator.evaluate(hasEven, in: [:]), .bool(true))
    }

    func testChoose() throws {
        let s: StateExpr = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        let result = try Evaluator.evaluate(choose(s, .greaterThan(.variable("_q"), .value(.int(1)))), in: [:])
        XCTAssertTrue(result == .int(2) || result == .int(3))
    }

    func testExpressionDescriptionProducesTLA() {
        let x = Var<Int>("x")
        let expr: StateExpr = x >= 0
        XCTAssertTrue(expr.description.contains("x"))
        XCTAssertTrue(expr.description.contains(">="))
        let action: ActionExpr = next(x) == x + 1
        XCTAssertTrue(action.description.contains("x'"))
    }

    func testConstantSubstitution() throws {
        let spec = TLASpec("Test") {
            Variable(Var<Int>("x"), .constant("N"))
            Constant("N", 5)
            Act("Inc") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
        }
        let substituted = substituteConstants(spec)
        XCTAssertEqual(substituted.variables.first?.initial, .int(5))
    }
}
