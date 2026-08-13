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
