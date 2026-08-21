import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedTypedSurface {
  static var spec: TLASpec {
    TLASpec("GeneratedTypedSurface") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
    }
  }
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}

requireSendable(GeneratedTypedSurface.State.self)
requireSendable(GeneratedTypedSurface.ActionLabel.self)
requireSendable(GeneratedTypedSurface.TransitionResult.self)

var machine = GeneratedTypedSurface()
let action: GeneratedTypedSurface.ActionLabel = .advance
let result = try machine.apply(action)

guard result.action == action,
      result.before.value == 0,
      result.after.value == 1 else {
  throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
  case invalidTransition
}
