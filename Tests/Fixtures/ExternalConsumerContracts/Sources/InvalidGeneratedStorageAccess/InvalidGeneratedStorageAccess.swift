import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedStorageAccess {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("GeneratedStorageAccess") {
      Algorithm("GeneratedStorageAccess", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          When(value < 1)
          Assign(value, to: value + 1)
        }
      })
    }
  }
}

let generatedMachine = try GeneratedStorageAccess.makeMachine()
_ = generatedMachine._storage

func inspect(_ actor: GeneratedStorageAccess.Actor) async {
  _ = await actor.machine
}
