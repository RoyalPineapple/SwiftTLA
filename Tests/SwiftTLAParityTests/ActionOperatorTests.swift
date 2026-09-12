@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ActionOperatorTests {
  let s0: [(String, TLAValue)] = [("x", .int(0))]
  let s2: [(String, TLAValue)] = [("a", .int(0)), ("b", .int(0))]

  @Test func simpleAssign() throws {
    let r = try compiledActionProjections(.assign(.named("x"), .value(.int(42))), from: s0, variables: ["x"])
    let assigned = try value("x", in: try #require(r.first))
    #expect(r.count == 1)
    #expect(assigned == .int(42))
  }

  @Test func unchanged() throws {
    let r = try compiledActionProjections(.unchanged(.named("x")), from: s0, variables: ["x"])
    let unchanged = try value("x", in: try #require(r.first))
    #expect(r.count == 1)
    #expect(unchanged == .int(0))
  }

  @Test func guardTrue() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))), .assign(.named("x"), .value(.int(1))))
    let r = try compiledActionProjections(a, from: s0, variables: ["x"])
    #expect(r.count == 1)
  }

  @Test func guardFalse() throws {
    let a: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(1)))), .assign(.named("x"), .value(.int(2))))
    let r = try compiledActionProjections(a, from: s0, variables: ["x"])
    #expect(r.isEmpty)
  }

  @Test func twoVars() throws {
    let a: ActionExpr = .and(.assign(.named("a"), .value(.int(1))), .assign(.named("b"), .value(.int(2))))
    let r = try compiledActionProjections(a, from: s2, variables: ["a", "b"])
    let successor = try #require(r.first)
    let aValue = try value("a", in: successor)
    let bValue = try value("b", in: successor)
    #expect(r.count == 1)
    #expect(aValue == .int(1))
    #expect(bValue == .int(2))
  }

  @Test func orBranches() throws {
    let a: ActionExpr = .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2))))
    let r = try compiledActionProjections(a, from: s0, variables: ["x"])
    #expect(r.count == 2)
  }

  @Test func nestedOr() throws {
    let a: ActionExpr = .or(
      .or(.assign(.named("x"), .value(.int(1))), .assign(.named("x"), .value(.int(2)))),
      .assign(.named("x"), .value(.int(3))))
    let r = try compiledActionProjections(a, from: s0, variables: ["x"])
    #expect(r.count == 3)
  }

  @Test func existentialRetainsItsSurroundingGuard() throws {
    let action: ActionExpr = .and(
      .guard_(.equal(.variable("x"), .value(.int(0)))),
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign(.named("x"), .variable("candidate"))
      )
    )

    let blocked = try compiledActionProjections(action, from: [("x", .int(1))], variables: ["x"])
    #expect(blocked.isEmpty)

    let advanced = try compiledActionProjections(action, from: s0, variables: ["x"])
    #expect(try advanced.map { try value("x", in: $0) } == [.int(1)])
  }

  @Test func equivalentAssignmentsAroundAnExistentialAgree() throws {
    let action: ActionExpr = .and(
      .existsAction(
        "candidate",
        .setLiteral([.value(.int(1))]),
        .assign(.named("x"), .variable("candidate"))
      ),
      .assign(.named("x"), .value(.int(1)))
    )

    let successors = try compiledActionProjections(action, from: s0, variables: ["x"])
    #expect(try successors.map { try value("x", in: $0) } == [.int(1)])
  }

}
