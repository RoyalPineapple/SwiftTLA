@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct TLAValueTests {
  @Test(
    "Every TLAValue case has a description",
    arguments: [
      TLAValue.int(1), .bool(true), .string("hi"),
      .set([.int(1)]), .tuple([.int(1)]), .record(["k": .int(1)]),
      .constant("N")
    ] as [TLAValue])
  func descriptions(_ v: TLAValue) {
    #expect(!v.description.isEmpty)
  }

  @Test("TLAValue function apply lookup")
  func functionApplyLookup() throws {
    let v: TLAValue = .function([.int(1): .string("one")])
    let state: [(String, TLAValue)] = [("f", v), ("k", .int(1))]
    let appliedValue = try compiledValue(StateExpr.functionApply(.variable("f"), .variable("k")), values: state)
    #expect(appliedValue == .string("one"))
  }
}
