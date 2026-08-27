import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedActorSurface {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("GeneratedActorSurface") {
      Algorithm("GeneratedActorSurface", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          When(value < 1)
          Assign(value, to: value + 1)
        }
      })
    }
  }
}

func rejectRawState(_ machine: GeneratedActorSurface.Actor) async {
  _ = await machine.tlaSnapshot()
  _ = GeneratedActorSurface.Actor.TransitionEvidence.self
}
