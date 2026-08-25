import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidGeneratedRawSurface {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("InvalidGeneratedRawSurface") {
      Algorithm("InvalidGeneratedRawSurface", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          When(value < 1)
          Assign(value, to: value + 1)
        }
      })
    }
  }
}

let machine = try InvalidGeneratedRawSurface.makeMachine()
let rawState = machine.tlaSnapshot()
let transitionEvidence = InvalidGeneratedRawSurface.TransitionEvidence.self
_ = (rawState, transitionEvidence)
