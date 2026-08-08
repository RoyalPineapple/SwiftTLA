import SwiftTLA
import Testing

@Suite(.serialized) struct EvaluatorCoverage {
    let state: [String: TLAValue] = [
        "x": .int(5), "y": .int(3), "b": .bool(true),
        "s": .set([.int(1), .int(2), .int(3)]),
        "t": .tuple([.int(1), .int(2), .int(3)]),
        "f": .function([.int(1): .string("a"), .int(2): .string("b")]),
        "r": .record(["a": .int(1), "b": .int(2)])
    ]

    @Test("leaf — value and variable")
    func leaf() throws {
        #expect(try StateExpr.value(.int(42)).evaluate(in: [:]) == .int(42))
        #expect(try StateExpr.variable("x").evaluate(in: state) == .int(5))
    }

    @Test("arithmetic — all 7 ops")
    func arithmetic() throws {
        #expect(try StateExpr.add(.int(2), .int(3)).evaluate(in: [:]) == .int(5))
        #expect(try StateExpr.subtract(.int(5), .int(2)).evaluate(in: [:]) == .int(3))
        #expect(try StateExpr.multiply(.int(2), .int(3)).evaluate(in: [:]) == .int(6))
        #expect(try StateExpr.divide(.int(6), .int(3)).evaluate(in: [:]) == .int(2))
        #expect(try StateExpr.modulo(.int(7), .int(3)).evaluate(in: [:]) == .int(1))
        #expect(try StateExpr.negate(.int(5)).evaluate(in: [:]) == .int(-5))
        #expect(try StateExpr.integerDivide(.int(7), .int(3)).evaluate(in: [:]) == .int(2))
    }

    @Test("comparison — all 6 ops")
    func comparison() throws {
        #expect(try StateExpr.equal(.int(5), .int(5)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.notEqual(.int(5), .int(3)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.lessThan(.int(3), .int(5)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.lessOrEqual(.int(3), .int(3)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.greaterThan(.int(5), .int(3)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.greaterOrEqual(.int(5), .int(5)).evaluate(in: [:]) == .bool(true))
    }

    @Test("logic — and, or, not, ifThenElse")
    func logic() throws {
        #expect(try StateExpr.and(.bool(true), .bool(true)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.or(.bool(false), .bool(true)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.not(.bool(false)).evaluate(in: [:]) == .bool(true))
        #expect(try StateExpr.ifThenElse(.bool(true), .int(1), .int(2)).evaluate(in: [:]) == .int(1))
    }

    @Test("sets — literal, in, subset, union, intersection, difference, cardinality, powerset")
    func sets() throws {
        #expect(try StateExpr.setLiteral([.int(1), .int(2)]).evaluate(in: [:]) == .set([.int(1), .int(2)]))
        #expect(try StateExpr.in(.int(2), .variable("s")).evaluate(in: state) == .bool(true))
        #expect(try StateExpr.subset(.setLiteral([.int(1)]), .variable("s")).evaluate(in: state) == .bool(true))
        #expect(try StateExpr.union(.setLiteral([.int(1)]), .setLiteral([.int(2)])).evaluate(in: [:]) == .set([.int(1), .int(2)]))
        #expect(try StateExpr.intersection(.variable("s"), .setLiteral([.int(2)])).evaluate(in: state) == .set([.int(2)]))
        #expect(try StateExpr.setDifference(.variable("s"), .setLiteral([.int(2)])).evaluate(in: state) == .set([.int(1), .int(3)]))
        #expect(try StateExpr.cardinality(.variable("s")).evaluate(in: state) == .int(3))
        #expect(try StateExpr.powerSet(.setLiteral([.int(1)])).evaluate(in: state) == .set([.set([]), .set([.int(1)])]))
    }

    @Test("tuples — literal, access, length, append, head, tail, concatenate")
    func tuples() throws {
        #expect(try StateExpr.tupleLiteral([.int(1), .int(2)]).evaluate(in: [:]) == .tuple([.int(1), .int(2)]))
        #expect(try StateExpr.tupleAccess(.variable("t"), 1).evaluate(in: state) == .int(1))
        #expect(try StateExpr.tupleLength(.variable("t")).evaluate(in: state) == .int(3))
        #expect(try StateExpr.tupleAppend(.variable("t"), .int(4)).evaluate(in: state) == .tuple([.int(1), .int(2), .int(3), .int(4)]))
        #expect(try StateExpr.tupleHead(.variable("t")).evaluate(in: state) == .int(1))
        #expect(try StateExpr.tupleTail(.variable("t")).evaluate(in: state) == .tuple([.int(2), .int(3)]))
        let tc = try StateExpr.tupleConcatenate(.variable("t"), .tupleLiteral([.int(4)])).evaluate(in: state)
        #expect(tc == .tuple([.int(1), .int(2), .int(3), .int(4)]))
    }

    @Test("records — literal, access")
    func records() throws {
        #expect(try StateExpr.recordLiteral(["k": .int(1)]).evaluate(in: [:]) == .record(["k": .int(1)]))
        #expect(try StateExpr.recordAccess(.variable("r"), "a").evaluate(in: state) == .int(1))
    }

    @Test("functions — domain, apply, except, literal")
    func functions() throws {
        #expect(try StateExpr.domain(.variable("f")).evaluate(in: state) == .set([.int(1), .int(2)]))
        #expect(try StateExpr.functionApply(.variable("f"), .int(1)).evaluate(in: state) == .string("a"))
    }

    @Test("quantifiers — forAll, exists")
    func quantifiers() throws {
        #expect(try StateExpr.forAll(.variable("s"), QuantVar(name: "x"), .greaterThan(.variable("x"), .int(0))).evaluate(in: state) == .bool(true))
        #expect(try StateExpr.exists(.variable("s"), QuantVar(name: "x"), .equal(.variable("x"), .int(2))).evaluate(in: state) == .bool(true))
    }

    @Test("builtins — sequenceFromSet, setSum, functionSet")
    func builtins() throws {
        #expect(try StateExpr.sequenceFromSet(.setLiteral([.int(3), .int(1)])).evaluate(in: [:]) == .tuple([.int(1), .int(3)]))
        let sum = try StateExpr.setSum(
            .functionLiteral(.setLiteral([.int(1), .int(2)]), QuantVar(name: "x"), .variable("x")),
            .setLiteral([.int(1), .int(2)])
        ).evaluate(in: [:])
        #expect(sum == .int(3))
        let fset = try StateExpr.functionSet(.setLiteral([.int(1)]), .setLiteral([.int(2)])).evaluate(in: [:])
        #expect(fset == .set([.function([.int(1): .int(2)])]))
    }
}
