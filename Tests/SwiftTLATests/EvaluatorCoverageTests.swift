@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct EvaluatorCoverage {
  let state: [(String, TLAValue)] = [
    ("x", .int(5)), ("y", .int(3)), ("b", .bool(true)),
    ("s", .set([.int(1), .int(2), .int(3)])),
    ("t", .tuple([.int(1), .int(2), .int(3)])),
    ("f", .function([.int(1): .string("a"), .int(2): .string("b")])),
    ("r", .record(["a": .int(1), "b": .int(2)]))
  ]

  private func evaluate(_ expression: StateExpr) throws -> TLAValue {
    try compiledValue(expression, values: state)
  }

  @Test("leaf values and variables")
  func leaf() throws {
    #expect(try evaluate(.value(.int(42))) == .int(42))
    #expect(try evaluate(.variable("x")) == .int(5))
  }

  @Test("arithmetic")
  func arithmetic() throws {
    #expect(try evaluate(.add(.int(2), .int(3))) == .int(5))
    #expect(try evaluate(.subtract(.int(5), .int(2))) == .int(3))
    #expect(try evaluate(.multiply(.int(2), .int(3))) == .int(6))
    #expect(try evaluate(.divide(.int(6), .int(3))) == .int(2))
    #expect(try evaluate(.modulo(.int(7), .int(3))) == .int(1))
    #expect(try evaluate(.negate(.int(5))) == .int(-5))
    #expect(try evaluate(.integerDivide(.int(7), .int(3))) == .int(2))
  }

  @Test("comparisons")
  func comparison() throws {
    #expect(try evaluate(.equal(.int(5), .int(5))) == .bool(true))
    #expect(try evaluate(.notEqual(.int(5), .int(3))) == .bool(true))
    #expect(try evaluate(.lessThan(.int(3), .int(5))) == .bool(true))
    #expect(try evaluate(.lessOrEqual(.int(3), .int(3))) == .bool(true))
    #expect(try evaluate(.greaterThan(.int(5), .int(3))) == .bool(true))
    #expect(try evaluate(.greaterOrEqual(.int(5), .int(5))) == .bool(true))
  }

  @Test("logical expressions")
  func logic() throws {
    #expect(try evaluate(.and(.bool(true), .bool(true))) == .bool(true))
    #expect(try evaluate(.or(.bool(false), .bool(true))) == .bool(true))
    #expect(try evaluate(.not(.bool(false))) == .bool(true))
    #expect(try evaluate(.ifThenElse(.bool(true), .int(1), .int(2))) == .int(1))
  }

  @Test("set expressions")
  func sets() throws {
    #expect(try evaluate(.setLiteral([.int(1), .int(2)])) == .set([.int(1), .int(2)]))
    #expect(try evaluate(.in(.int(2), .variable("s"))) == .bool(true))
    #expect(try evaluate(.subset(.setLiteral([.int(1)]), .variable("s"))) == .bool(true))
    #expect(try evaluate(.union(.setLiteral([.int(1)]), .setLiteral([.int(2)]))) == .set([.int(1), .int(2)]))
    #expect(try evaluate(.intersection(.variable("s"), .setLiteral([.int(2)]))) == .set([.int(2)]))
    #expect(try evaluate(.setDifference(.variable("s"), .setLiteral([.int(2)]))) == .set([.int(1), .int(3)]))
    #expect(try evaluate(.cardinality(.variable("s"))) == .int(3))
    #expect(try evaluate(.powerSet(.setLiteral([.int(1)]))) == .set([.set([]), .set([.int(1)])]))
    #expect(try evaluate(.integerRange(.int(2), .int(4))) == .set([.int(2), .int(3), .int(4)]))
  }

  @Test("tuple expressions")
  func tuples() throws {
    #expect(try evaluate(.tupleLiteral([.int(1), .int(2)])) == .tuple([.int(1), .int(2)]))
    #expect(try evaluate(.tupleAccess(.variable("t"), 1)) == .int(1))
    #expect(try evaluate(.tupleDynamicAccess(.variable("t"), .int(2))) == .int(2))
    #expect(try evaluate(.tupleLength(.variable("t"))) == .int(3))
    #expect(try evaluate(.tupleAppend(.variable("t"), .int(4))) == .tuple([.int(1), .int(2), .int(3), .int(4)]))
    #expect(try evaluate(.tupleHead(.variable("t"))) == .int(1))
    #expect(try evaluate(.tupleTail(.variable("t"))) == .tuple([.int(2), .int(3)]))
    #expect(try evaluate(.tupleConcatenate(.variable("t"), .tupleLiteral([.int(4)]))) == .tuple([.int(1), .int(2), .int(3), .int(4)]))
  }

  @Test("records and functions")
  func recordsAndFunctions() throws {
    #expect(try evaluate(.recordLiteral(["k": .int(1)])) == .record(["k": .int(1)]))
    #expect(try evaluate(.recordAccess(.variable("r"), "a")) == .int(1))
    #expect(try evaluate(.domain(.variable("f"))) == .set([.int(1), .int(2)]))
    #expect(try evaluate(.functionApply(.variable("f"), .int(1))) == .string("a"))
  }

  @Test("quantifiers")
  func quantifiers() throws {
    #expect(try evaluate(.forAll(.variable("s"), "x", .greaterThan(.variable("x"), .int(0)))) == .bool(true))
    #expect(try evaluate(.exists(.variable("s"), "x", .equal(.variable("x"), .int(2)))) == .bool(true))
  }

  @Test("built-in expressions")
  func builtins() throws {
    #expect(try evaluate(.sequenceFromSet(.setLiteral([.int(3), .int(1)]))) == .tuple([.int(1), .int(3)]))
    #expect(try evaluate(.setSum(
      .functionLiteral(.setLiteral([.int(1), .int(2)]), "x", .variable("x")),
      .setLiteral([.int(1), .int(2)])
    )) == .int(3))
    #expect(try evaluate(.functionSet(.setLiteral([.int(1)]), .setLiteral([.int(2)]))) == .set([.function([.int(1): .int(2)])]))
  }
}
