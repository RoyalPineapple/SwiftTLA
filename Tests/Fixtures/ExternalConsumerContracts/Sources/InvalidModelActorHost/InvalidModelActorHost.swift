import SwiftTLA
import SwiftTLAMacros

@TLAModel
actor InvalidModelActorHost {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("InvalidModelActorHost") {
      Algorithm("InvalidModelActorHost", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          Assign(value, to: value + 1)
        }
      })
    }
  }
}
