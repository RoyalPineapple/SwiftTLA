import XCTest
import SwiftTLA

final class ArithmeticTests: XCTestCase {
    func testAdd()          { try assertEval(.add(.int(2), .int(3)), .int(5)) }
    func testSubtract()     { try assertEval(.subtract(.int(5), .int(3)), .int(2)) }
    func testMultiply()     { try assertEval(.multiply(.int(4), .int(3)), .int(12)) }
    func testDivide()       { try assertEval(.divide(.int(10), .int(2)), .int(5)) }
    func testModulo()       { try assertEval(.modulo(.int(10), .int(3)), .int(1)) }
    func testIntegerDivide(){ try assertEval(.integerDivide(.int(10), .int(3)), .int(3)) }
    func testNegate()       { try assertEval(.negate(.int(5)), .int(-5)) }

    func testDivideByZeroThrows() {
        XCTAssertThrowsError(try Evaluator.evaluate(.divide(.int(1), .int(0)), in: [:]))
    }

    func testEvaluatesVariable() {
        try assertEval(.variable("x"), .int(42), state: ["x": .int(42)])
    }
}

final class ComparisonTests: XCTestCase {
    func testEqualTrue()      { try assertEval(.equal(.int(1), .int(1)), .bool(true)) }
    func testEqualFalse()     { try assertEval(.equal(.int(1), .int(2)), .bool(false)) }
    func testNotEqual()       { try assertEval(.notEqual(.int(1), .int(2)), .bool(true)) }
    func testLessThan()       { try assertEval(.lessThan(.int(1), .int(2)), .bool(true)) }
    func testLessOrEqual()    { try assertEval(.lessOrEqual(.int(2), .int(2)), .bool(true)) }
    func testGreaterThan()    { try assertEval(.greaterThan(.int(2), .int(1)), .bool(true)) }
    func testGreaterOrEqual() { try assertEval(.greaterOrEqual(.int(2), .int(2)), .bool(true)) }
}

final class LogicTests: XCTestCase {
    func testAndTrue()  { try assertEval(.and(.bool(true), .bool(true)), .bool(true)) }
    func testAndFalse() { try assertEval(.and(.bool(true), .bool(false)), .bool(false)) }
    func testOrTrue()   { try assertEval(.or(.bool(false), .bool(true)), .bool(true)) }
    func testOrFalse()  { try assertEval(.or(.bool(false), .bool(false)), .bool(false)) }
    func testNot()      { try assertEval(.not(.bool(false)), .bool(true)) }
    func testAndShortCircuits() {
        try assertEval(.and(.bool(false), .divide(.int(1), .int(0))), .bool(false))
    }
    func testOrShortCircuits() {
        try assertEval(.or(.bool(true), .divide(.int(1), .int(0))), .bool(true))
    }
    func testIfThenElseTrue()  { try assertEval(.ifThenElse(.bool(true), .int(1), .int(2)), .int(1)) }
    func testIfThenElseFalse() { try assertEval(.ifThenElse(.bool(false), .int(1), .int(2)), .int(2)) }
}

final class SetTests: XCTestCase {
    func testMembership() {
        let s: StateExpr = .setLiteral([.int(1), .int(2)])
        try assertEval(.in(.int(2), s), .bool(true))
        try assertEval(.in(.int(3), s), .bool(false))
    }
    func testSubset() {
        let a: StateExpr = .setLiteral([.int(1)])
        let b: StateExpr = .setLiteral([.int(1), .int(2)])
        try assertEval(.subset(a, b), .bool(true))
        try assertEval(.subset(b, a), .bool(false))
    }
    func testUnion() {
        try assertEval(.union(.setLiteral([.int(1)]), .setLiteral([.int(2)])), .set([.int(1), .int(2)]))
    }
    func testIntersection() {
        try assertEval(.intersection(.setLiteral([.int(1), .int(2)]), .setLiteral([.int(2), .int(3)])), .set([.int(2)]))
    }
    func testDifference() {
        try assertEval(.setDifference(.setLiteral([.int(1), .int(2)]), .setLiteral([.int(2), .int(3)])), .set([.int(1)]))
    }
    func testCardinality() {
        try assertEval(.cardinality(.setLiteral([.int(1), .int(2), .int(3)])), .int(3))
    }
    func testEmptySet() {
        try assertEval(.cardinality(.setLiteral([])), .int(0))
    }
    func testPowerSet() {
        try assertEval(.cardinality(.powerSet(.setLiteral([.int(1), .int(2)]))), .int(4))
    }
    func testUnionAll() {
        let s: StateExpr = .setLiteral([.setLiteral([.int(1)]), .setLiteral([.int(2)])])
        try assertEval(.unionAll(s), .set([.int(1), .int(2)]))
    }
    func testSetFilter() {
        let s: StateExpr = .setLiteral([.int(1), .int(2), .int(3)])
        try assertEval(.cardinality(.setFilter(s, .greaterThan(.variable("_q"), .int(1)))), .int(2))
    }
    func testSetMap() {
        let s: StateExpr = .setLiteral([.int(1), .int(2)])
        try assertEval(.cardinality(.setMap(.add(.variable("_q"), .int(10)), s)), .int(2))
    }
}

final class TupleTests: XCTestCase {
    func testLiteral() {
        try assertEval(.tupleLiteral([.int(1), .int(2)]), .tuple([.int(1), .int(2)]))
    }
    func testAccess() {
        try assertEval(.tupleAccess(.tupleLiteral([.int(10), .int(20)]), 1), .int(10))
        try assertEval(.tupleAccess(.tupleLiteral([.int(10), .int(20)]), 2), .int(20))
    }
    func testLength() {
        try assertEval(.tupleLength(.tupleLiteral([.int(1), .int(2), .int(3)])), .int(3))
    }
    func testAppend() {
        try assertEval(.tupleAppend(.tupleLiteral([.int(1)]), .int(2)), .tuple([.int(1), .int(2)]))
    }
    func testConcatenate() {
        try assertEval(.tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)])), .tuple([.int(1), .int(2)]))
    }
}

final class RecordTests: XCTestCase {
    func testLiteral() {
        try assertEval(.recordLiteral(["a": .int(1)]), .record(["a": .int(1)]))
    }
    func testAccess() {
        try assertEval(.recordAccess(.recordLiteral(["a": .int(42)]), "a"), .int(42))
    }
    func testDomain() {
        try assertEval(.domain(.recordLiteral(["a": .int(1), "b": .int(2)])), .set([.string("a"), .string("b")]))
    }
}

final class FunctionTests: XCTestCase {
    func testLiteral() {
        let domain: StateExpr = .setLiteral([.int(1), .int(2)])
        let body: StateExpr = .add(.variable("_q"), .int(10))
        let f = try Evaluator.evaluate(.functionLiteral(domain, body), in: [:])
        if case .set(let s) = f {
            XCTAssertTrue(s.contains(.record(["1": .int(11)])))
            XCTAssertTrue(s.contains(.record(["2": .int(12)])))
        } else { XCTFail() }
    }
    func testApply() {
        let domain: StateExpr = .setLiteral([.int(1)])
        let body: StateExpr = .add(.variable("_q"), .int(10))
        let f: StateExpr = .functionLiteral(domain, body)
        let state = try Evaluator.evaluate(f, in: [:])
        if case .set(let s) = state {
            try assertEval(.functionApply(.value(.set(s)), .int(1)), .int(11), state: [:])
        }
    }
    func testExcept() {
        let domain: StateExpr = .setLiteral([.int(1)])
        let body: StateExpr = .add(.variable("_q"), .int(10))
        let f = try Evaluator.evaluate(.functionLiteral(domain, body), in: [:])
        if case .set(let s) = f {
            try assertEval(.except(.value(.set(s)), .int(1), .int(99)), .set([.record(["1": .int(99)])]), state: [:])
        }
    }
}

final class QuantifierTests: XCTestCase {
    func testForAll() {
        let s: StateExpr = .setLiteral([.int(1), .int(2), .int(3)])
        try assertEval(.forAll(s, .greaterThan(.variable("_q"), .int(0))), .bool(true))
        try assertEval(.forAll(s, .lessThan(.variable("_q"), .int(2))), .bool(false))
    }
    func testExists() {
        let s: StateExpr = .setLiteral([.int(1), .int(2), .int(3)])
        try assertEval(.exists(s, .equal(.variable("_q"), .int(2))), .bool(true))
        try assertEval(.exists(s, .equal(.variable("_q"), .int(99))), .bool(false))
    }
    func testChoose() {
        let s: StateExpr = .setLiteral([.int(1), .int(2), .int(3)])
        let result = try Evaluator.evaluate(.choose(s, .greaterThan(.variable("_q"), .int(1))), in: [:])
        XCTAssertTrue(result == .int(2) || result == .int(3))
    }
    func testChooseNoMatch() {
        let s: StateExpr = .setLiteral([.int(1)])
        XCTAssertThrowsError(try Evaluator.evaluate(.choose(s, .greaterThan(.variable("_q"), .int(99))), in: [:]))
    }
}

final class CaseExprTests: XCTestCase {
    func testFirstBranch() {
        try assertEval(.caseExpr([.bool(true), .int(1), .bool(false), .int(2)], nil), .int(1))
    }
    func testSecondBranch() {
        try assertEval(.caseExpr([.bool(false), .int(1), .bool(true), .int(2)], nil), .int(2))
    }
    func testOther() {
        try assertEval(.caseExpr([.bool(false), .int(1)], .int(99)), .int(99))
    }
    func testNoMatch() {
        XCTAssertThrowsError(try Evaluator.evaluate(.caseExpr([.bool(false), .int(1)], nil), in: [:]))
    }
}

private extension StateExpr {
    static func int(_ v: Int) -> StateExpr { .value(.int(v)) }
    static func bool(_ v: Bool) -> StateExpr { .value(.bool(v)) }
    static func string(_ v: String) -> StateExpr { .value(.string(v)) }
}

extension XCTestCase {
    func assertEval(_ expr: StateExpr, _ expected: TLAValue, state: [String: TLAValue] = [:], file: StaticString = #file, line: UInt = #line) throws {
        let result = try Evaluator.evaluate(expr, in: state)
        XCTAssertEqual(result, expected, file: file, line: line)
    }
}
