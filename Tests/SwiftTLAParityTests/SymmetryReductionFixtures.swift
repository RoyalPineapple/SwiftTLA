import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

enum LeftNode: String, CaseIterable, FiniteTLAValueDomain {
  case first = "LeftFirst"
  case second = "LeftSecond"

  static var defaultValue: Self { .first }
  static let finiteValues = allCases
  var tlaValue: TLAValue { .constant(rawValue) }

  init?(formalValue: TLAValue) {
    guard case .constant(let value) = formalValue else { return nil }
    self.init(rawValue: value)
  }
}

enum RightNode: String, CaseIterable, FiniteTLAValueDomain {
  case first = "RightFirst"
  case second = "RightSecond"

  static var defaultValue: Self { .first }
  static let finiteValues = allCases
  var tlaValue: TLAValue { .constant(rawValue) }

  init?(formalValue: TLAValue) {
    guard case .constant(let value) = formalValue else { return nil }
    self.init(rawValue: value)
  }
}

enum Mode: Int, TLAValueType, StateExprConvertible {
  case idle = 0
  case active = 1

  static var defaultValue: Self { .idle }
}
enum Status: String, TLAValueType, StateExprConvertible {
  case on, off

  static var defaultValue: Self { .on }
}
