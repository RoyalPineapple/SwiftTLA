import SwiftTLA
import SwiftTLAMacros

@TLAObservable
final class StandaloneObservableSendable {
  static var spec: TLASpec {
    TLASpec("StandaloneObservableSendable") {
      let count = Var<Int>("count")
      Variable(count, 0)
      Action("advance") { count.becomes(count + 1).when(count < 1) }
    }
  }
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}

requireSendable(StandaloneObservableSendable.self)
requireSendable(StandaloneObservableSendable.State.self)
requireSendable(StandaloneObservableSendable.Variables.self)
requireSendable(StandaloneObservableSendable.ActionLabel.self)
requireSendable(StandaloneObservableSendable.TransitionResult.self)

let observable = StandaloneObservableSendable()
let result = try observable._advance()

precondition(result.action == .advance)
precondition(result.before.count == 0)
precondition(result.after.count == 1)
precondition(observable.state.count == 1)

let beforeRejectedAction = observable.tlaSnapshot()
do {
  _ = try observable._advance()
  fatalError("Expected disabled action")
} catch {
  precondition(observable.tlaSnapshot() == beforeRejectedAction)
}
