import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ObservableHost {
  static var spec: TLASpec {
    TLASpec("StandaloneObservableSendable") {
      let count = Var<Int>("count")
      Variable(count, 0)
      Action("advance") { count.becomes(count + 1).when(count < 1) }
    }
  }

  @TLAObservable
  final class Observable {}
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}

requireSendable(ObservableHost.Observable.self)
requireSendable(ObservableHost.Observable.State.self)
requireSendable(ObservableHost.Observable.ActionLabel.self)
requireSendable(ObservableHost.Observable.TransitionResult.self)

let live = try ObservableHost.makeLive()
let observable = try await ObservableHost.Observable(live: live)
let result = try await observable.apply(.advance)

precondition(result.action == .advance)
precondition(result.before.count == 0)
precondition(result.after.count == 1)
let stateCount = observable.state.count
precondition(stateCount == 1)

let beforeRejectedAction = observable.state
do {
  _ = try await observable.apply(.advance)
  fatalError("Expected disabled action")
} catch {
  let stateAfterRejectedAction = observable.state
  precondition(stateAfterRejectedAction == beforeRejectedAction)
}
