import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedTypedSurface {
  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("GeneratedTypedSurface") {
      Algorithm("GeneratedTypedSurface", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.advance) {
          When(value < 1)
          Assign(value, to: value + 1)
        }
      })
    }
  }
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}

requireSendable(GeneratedTypedSurface.State.self)
requireSendable(GeneratedTypedSurface.Action.self)
requireSendable(GeneratedTypedSurface.Transition.self)

var machine = try GeneratedTypedSurface.makeMachine()
let action: GeneratedTypedSurface.Action = .advance
let transition = try machine.send(action)

guard transition.action == action,
      transition.before.value == 0,
      transition.after.value == 1 else {
  throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
  case invalidTransition
}
