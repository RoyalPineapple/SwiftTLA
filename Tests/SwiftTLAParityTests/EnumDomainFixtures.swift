@testable import SwiftTLA

enum Mode: Int, TLAValueType, StateExprConvertible {
  case idle = 0
  case active = 1

  static var defaultValue: Self { .idle }
}

enum Status: String, TLAValueType, StateExprConvertible {
  case on, off

  static var defaultValue: Self { .on }
}
