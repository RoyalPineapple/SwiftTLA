import XCTest
import SwiftTLA

private extension StateExpr {
    static func int(_ v: Int) -> StateExpr { .value(.int(v)) }
    static func bool(_ v: Bool) -> StateExpr { .value(.bool(v)) }
    static func set(_ v: [Int]) -> StateExpr { .setLiteral(v.map { .int($0) }) }
}

private typealias TestCase = (name: String, expr: StateExpr, expected: TLAValue, state: [String: TLAValue])

final class ArithmeticTests: XCTestCase {
    func testAll() throws {
        let cases: [TestCase] = [
            ("add",        .add(.int(2), .int(3)), .int(5), [:]),
            ("subtract",   .subtract(.int(5), .int(3)), .int(2), [:]),
            ("multiply",   .multiply(.int(4), .int(3)), .int(12), [:]),
            ("divide",     .divide(.int(10), .int(2)), .int(5), [:]),
            ("modulo",     .modulo(.int(10), .int(3)), .int(1), [:]),
            ("intDivide",  .integerDivide(.int(10), .int(3)), .int(3), [:]),
            ("negate",     .negate(.int(5)), .int(-5), [:]),
            ("variable",   .variable("x"), .int(42), ["x": .int(42)]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }
}

final class ComparisonTests: XCTestCase {
    func testAll() throws {
        let cases: [TestCase] = [
            ("equal-true",    .equal(.int(1), .int(1)), .bool(true), [:]),
            ("equal-false",   .equal(.int(1), .int(2)), .bool(false), [:]),
            ("notEqual",      .notEqual(.int(1), .int(2)), .bool(true), [:]),
            ("lessThan",      .lessThan(.int(1), .int(2)), .bool(true), [:]),
            ("lessOrEqual",   .lessOrEqual(.int(2), .int(2)), .bool(true), [:]),
            ("greaterThan",   .greaterThan(.int(2), .int(1)), .bool(true), [:]),
            ("greaterOrEqual",.greaterOrEqual(.int(2), .int(2)), .bool(true), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }
}

final class LogicTests: XCTestCase {
    func testAll() throws {
        let cases: [TestCase] = [
            ("and-true",        .and(.bool(true), .bool(true)), .bool(true), [:]),
            ("and-false",       .and(.bool(true), .bool(false)), .bool(false), [:]),
            ("or-true",         .or(.bool(false), .bool(true)), .bool(true), [:]),
            ("or-false",        .or(.bool(false), .bool(false)), .bool(false), [:]),
            ("not",             .not(.bool(false)), .bool(true), [:]),
            ("ifThenElse-true", .ifThenElse(.bool(true), .int(1), .int(2)), .int(1), [:]),
            ("ifThenElse-false",.ifThenElse(.bool(false), .int(1), .int(2)), .int(2), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }

    func testAndShortCircuits() {
        // Division by zero in RHS should not matter if LHS is false
        XCTAssertNoThrow(try Evaluator.evaluate(.and(.bool(false), .divide(.int(1), .int(0))), in: [:]))
    }

    func testOrShortCircuits() {
        XCTAssertNoThrow(try Evaluator.evaluate(.or(.bool(true), .divide(.int(1), .int(0))), in: [:]))
    }
}

final class SetTests: XCTestCase {
    func testAll() throws {
        let s12: StateExpr = .set([1,2])
        let s13: StateExpr = .set([1,3])
        let s23: StateExpr = .set([2,3])
        let s123: StateExpr = .set([1,2,3])

        let cases: [TestCase] = [
            ("member-true",   .in(.int(2), s12), .bool(true), [:]),
            ("member-false",  .in(.int(3), s12), .bool(false), [:]),
            ("subset-true",   .subset(s12, s123), .bool(true), [:]),
            ("subset-false",  .subset(s123, s12), .bool(false), [:]),
            ("union",         .union(s12, s23), .set([.int(1), .int(2), .int(3)]), [:]),
            ("intersection",  .intersection(s12, s23), .set([.int(2)]), [:]),
            ("difference",    .setDifference(s12, s23), .set([.int(1)]), [:]),
            ("cardinality",   .cardinality(s123), .int(3), [:]),
            ("empty",         .cardinality(.setLiteral([])), .int(0), [:]),
            ("powerSet",      .cardinality(.powerSet(s12)), .int(4), [:]),
            ("filter",        .cardinality(.setFilter(s123, .greaterThan(.variable("_q"), .int(1)))), .int(2), [:]),
            ("map",           .cardinality(.setMap(.add(.variable("_q"), .int(10)), s12)), .int(2), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }

    func testUnionAll() throws {
        let s: StateExpr = .setLiteral([.set([1]), .set([2])])
        let result = try Evaluator.evaluate(.unionAll(s), in: [:])
        XCTAssertEqual(result, .set([.int(1), .int(2)]))
    }
}

final class TupleTests: XCTestCase {
    func testAll() throws {
        let t12: StateExpr = .tupleLiteral([.int(1), .int(2)])
        let cases: [TestCase] = [
            ("literal",     t12, .tuple([.int(1), .int(2)]), [:]),
            ("access-1",    .tupleAccess(t12, 1), .int(1), [:]),
            ("access-2",    .tupleAccess(t12, 2), .int(2), [:]),
            ("length",      .tupleLength(t12), .int(2), [:]),
            ("append",      .tupleAppend(.tupleLiteral([.int(1)]), .int(2)), .tuple([.int(1), .int(2)]), [:]),
            ("concatenate", .tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)])), .tuple([.int(1), .int(2)]), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }
}

final class RecordTests: XCTestCase {
    func testAll() throws {
        let rec: StateExpr = .recordLiteral(["a": .int(1), "b": .int(2)])
        let cases: [TestCase] = [
            ("literal",  rec, .record(["a": .int(1), "b": .int(2)]), [:]),
            ("access",   .recordAccess(rec, "a"), .int(1), [:]),
            ("domain",   .domain(rec), .set([.string("a"), .string("b")]), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }
}

final class FunctionTests: XCTestCase {
    func testLiteralAndApply() throws {
        let domain: StateExpr = .set([1])
        let body: StateExpr = .add(.variable("_q"), .int(10))
        let f = try Evaluator.evaluate(.functionLiteral(domain, body), in: [:])
        guard case .set(let s) = f else { return XCTFail() }
        let result = try Evaluator.evaluate(.functionApply(.value(.set(s)), .int(1)), in: [:])
        XCTAssertEqual(result, .int(11))
    }

    func testExceptUpdatesEntry() throws {
        let domain: StateExpr = .set([1])
        let f = try Evaluator.evaluate(.functionLiteral(domain, .add(.variable("_q"), .int(10))), in: [:])
        guard case .set(let s) = f else { return XCTFail() }
        let result = try Evaluator.evaluate(.except(.value(.set(s)), .int(1), .int(99)), in: [:])
        XCTAssertEqual(result, .set([.record(["1": .int(99)])]))
    }
}

final class QuantifierTests: XCTestCase {
    func testAll() throws {
        let s: StateExpr = .set([1,2,3])
        let cases: [TestCase] = [
            ("forAll-true",  .forAll(s, .greaterThan(.variable("_q"), .int(0))), .bool(true), [:]),
            ("forAll-false", .forAll(s, .lessThan(.variable("_q"), .int(2))), .bool(false), [:]),
            ("exists-true",  .exists(s, .equal(.variable("_q"), .int(2))), .bool(true), [:]),
            ("exists-false", .exists(s, .equal(.variable("_q"), .int(99))), .bool(false), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }
}

final class CaseExprTests: XCTestCase {
    func testAll() throws {
        let cases: [TestCase] = [
            ("first",    .caseExpr([.bool(true), .int(1), .bool(false), .int(2)], nil), .int(1), [:]),
            ("second",   .caseExpr([.bool(false), .int(1), .bool(true), .int(2)], nil), .int(2), [:]),
            ("other",    .caseExpr([.bool(false), .int(1)], .int(99)), .int(99), [:]),
        ]
        for (name, expr, expected, state) in cases {
            XCTAssertEqual(try Evaluator.evaluate(expr, in: state), expected, name)
        }
    }

    func testCaseNoMatchThrows() {
        XCTAssertThrowsError(try Evaluator.evaluate(.caseExpr([.bool(false), .int(1)], nil), in: [:]))
    }
}

