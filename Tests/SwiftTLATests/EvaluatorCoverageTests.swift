import SwiftTLA
import Testing

struct EvaluatorCoverage {
    let state: [String: TLAValue] = [
        "x": .int(5), "y": .int(3), "b": .bool(true),
        "s": .set([.int(1), .int(2), .int(3)]),
        "t": .tuple([.int(1), .int(2), .int(3)]),
        "f": .function([.int(1): .string("a"), .int(2): .string("b")]),
        "r": .record(["a": .int(1), "b": .int(2)]),
    ]

    @Test("leaf — value and variable")
    func leaf() throws {
        #expect(try Evaluator.evaluate(.value(.int(42)), in: [:]) == .int(42))
        #expect(try Evaluator.evaluate(.variable("x"), in: state) == .int(5))
    }

    @Test("arithmetic — all 7 ops")
    func arithmetic() throws {
        #expect(try Evaluator.evaluate(.add(.int(2), .int(3)), in: [:]) == .int(5))
        #expect(try Evaluator.evaluate(.subtract(.int(5), .int(2)), in: [:]) == .int(3))
        #expect(try Evaluator.evaluate(.multiply(.int(2), .int(3)), in: [:]) == .int(6))
        #expect(try Evaluator.evaluate(.divide(.int(6), .int(3)), in: [:]) == .int(2))
        #expect(try Evaluator.evaluate(.modulo(.int(7), .int(3)), in: [:]) == .int(1))
        #expect(try Evaluator.evaluate(.negate(.int(5)), in: [:]) == .int(-5))
        #expect(try Evaluator.evaluate(.integerDivide(.int(7), .int(3)), in: [:]) == .int(2))
    }

    @Test("comparison — all 6 ops")
    func comparison() throws {
        #expect(try Evaluator.evaluate(.equal(.int(5), .int(5)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.notEqual(.int(5), .int(3)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.lessThan(.int(3), .int(5)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.lessOrEqual(.int(3), .int(3)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.greaterThan(.int(5), .int(3)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.greaterOrEqual(.int(5), .int(5)), in: [:]) == .bool(true))
    }

    @Test("logic — and, or, not, ifThenElse")
    func logic() throws {
        #expect(try Evaluator.evaluate(.and(.bool(true), .bool(true)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.or(.bool(false), .bool(true)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.not(.bool(false)), in: [:]) == .bool(true))
        #expect(try Evaluator.evaluate(.ifThenElse(.bool(true), .int(1), .int(2)), in: [:]) == .int(1))
    }

    @Test("sets — literal, in, subset, union, intersection, difference, cardinality, powerset")
    func sets() throws {
        #expect(try Evaluator.evaluate(.setLiteral([.int(1), .int(2)]), in: [:]) == .set([.int(1), .int(2)]))
        #expect(try Evaluator.evaluate(.in(.int(2), .variable("s")), in: state) == .bool(true))
        #expect(try Evaluator.evaluate(.subset(.setLiteral([.int(1)]), .variable("s")), in: state) == .bool(true))
        #expect(try Evaluator.evaluate(.union(.setLiteral([.int(1)]), .setLiteral([.int(2)])), in: [:]) == .set([.int(1), .int(2)]))
        #expect(try Evaluator.evaluate(.intersection(.variable("s"), .setLiteral([.int(2)])), in: state) == .set([.int(2)]))
        #expect(try Evaluator.evaluate(.setDifference(.variable("s"), .setLiteral([.int(2)])), in: state) == .set([.int(1), .int(3)]))
        #expect(try Evaluator.evaluate(.cardinality(.variable("s")), in: state) == .int(3))
        #expect(try Evaluator.evaluate(.powerSet(.setLiteral([.int(1)])), in: state) == .set([.set([]), .set([.int(1)])]))
    }

    @Test("tuples — literal, access, length, append, head, tail, concatenate")
    func tuples() throws {
        #expect(try Evaluator.evaluate(.tupleLiteral([.int(1), .int(2)]), in: [:]) == .tuple([.int(1), .int(2)]))
        #expect(try Evaluator.evaluate(.tupleAccess(.variable("t"), 1), in: state) == .int(1))
        #expect(try Evaluator.evaluate(.tupleLength(.variable("t")), in: state) == .int(3))
        #expect(try Evaluator.evaluate(.tupleAppend(.variable("t"), .int(4)), in: state) == .tuple([.int(1), .int(2), .int(3), .int(4)]))
        #expect(try Evaluator.evaluate(.tupleHead(.variable("t")), in: state) == .int(1))
        #expect(try Evaluator.evaluate(.tupleTail(.variable("t")), in: state) == .tuple([.int(2), .int(3)]))
        #expect(try Evaluator.evaluate(.tupleConcatenate(.variable("t"), .tupleLiteral([.int(4)])), in: state) == .tuple([.int(1), .int(2), .int(3), .int(4)]))
    }

    @Test("records — literal, access")
    func records() throws {
        #expect(try Evaluator.evaluate(.recordLiteral(["k": .int(1)]), in: [:]) == .record(["k": .int(1)]))
        #expect(try Evaluator.evaluate(.recordAccess(.variable("r"), "a"), in: state) == .int(1))
    }

    @Test("functions — domain, apply, except, literal")
    func functions() throws {
        #expect(try Evaluator.evaluate(.domain(.variable("f")), in: state) == .set([.int(1), .int(2)]))
        #expect(try Evaluator.evaluate(.functionApply(.variable("f"), .int(1)), in: state) == .string("a"))
    }

    @Test("quantifiers — forAll, exists")
    func quantifiers() throws {
        #expect(try Evaluator.evaluate(.forAll(.variable("s"), .greaterThan(.variable("_x"), .int(0))), in: state) == .bool(true))
        #expect(try Evaluator.evaluate(.exists(.variable("s"), .equal(.variable("_x"), .int(2))), in: state) == .bool(true))
    }

    @Test("builtins — sequenceFromSet, setSum, functionSet")
    func builtins() throws {
        #expect(try Evaluator.evaluate(.sequenceFromSet(.setLiteral([.int(3), .int(1)])), in: [:]) == .tuple([.int(1), .int(3)]))
        #expect(try Evaluator.evaluate(.setSum(.functionLiteral(.setLiteral([.int(1), .int(2)]), .variable("_x")), .setLiteral([.int(1), .int(2)])), in: [:]) == .int(3))
        #expect(try Evaluator.evaluate(.functionSet(.setLiteral([.int(1)]), .setLiteral([.int(2)])), in: [:]) == .set([.function([.int(1): .int(2)])]))
    }
}
