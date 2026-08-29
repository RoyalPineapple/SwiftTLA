import SwiftTLA
import SwiftTLAMacros

@TLAModel
final class InvalidModelClassHost {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("InvalidModelClassHost") {
      Algorithm("InvalidModelClassHost", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          Assign(value, to: value + 1)
        }
      })
    }
  }
}
