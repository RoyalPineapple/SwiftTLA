@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ActionExprCompleteTests {
  @Test(
    "Every ActionExpr case enumerates correctly",
    arguments: [
      ("assign", ActionExpr.assign(.named("x"), .int(1)), 1),
      ("unchanged", ActionExpr.unchanged(.named("x")), 1),
      ("simpleAnd", ActionExpr.and(.assign(.named("x"), .int(1)), .assign(.named("y"), .int(2))), 1),
      ("or", ActionExpr.or(.assign(.named("x"), .int(1)), .assign(.named("x"), .int(2))), 2),
      (
        "guarded", ActionExpr.and(.guard_(.equal(.variable("x"), .int(0))), .assign(.named("x"), .int(1))),
        1
      )
    ] as [(String, ActionExpr, Int)])
  func enumerate(_ name: String, _ a: ActionExpr, _ expected: Int) throws {
    let s: [(String, TLAValue)] = [("x", .int(0)), ("y", .int(0))]
    let r = try compiledActionProjections(a, from: s, variables: ["x", "y"])
    #expect(r.count == expected, "\(name): expected \(expected), got \(r.count)")
  }
}
