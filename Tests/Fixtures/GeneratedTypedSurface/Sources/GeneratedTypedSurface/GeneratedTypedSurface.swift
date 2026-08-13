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
requireSendable(GeneratedTypedSurface.Variables.self)
requireSendable(GeneratedTypedSurface.ActionLabel.self)
requireSendable(GeneratedTypedSurface.TransitionResult.self)

var machine = GeneratedTypedSurface()
let variable: GeneratedTypedSurface.Variables = .value
let action: GeneratedTypedSurface.ActionLabel = .advance
let result = try machine.apply(action)

precondition(variable.rawValue == "value")
precondition(result.action == action)
precondition(result.before.value == 0)
precondition(result.after.value == 1)
