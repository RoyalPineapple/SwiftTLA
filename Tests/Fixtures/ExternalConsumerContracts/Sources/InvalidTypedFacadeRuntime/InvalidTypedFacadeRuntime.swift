import SwiftTLA

enum OmittedID: String, FiniteTLAValueDomain {
  case included
  case omitted

  static var defaultValue: Self { .included }
  static let finiteValues = [OmittedID.included]
}

let values = Var<Function<OmittedID, Int>>("values")
_ = values[.omitted]
