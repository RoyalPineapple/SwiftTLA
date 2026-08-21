import SwiftTLA
import SwiftTLAMacros

@SwiftTLAMacros.TLAModel
struct ObservableHost {
  static var spec: TLASpec {
    TLASpec("StandaloneObservableSendable") {
      let count = Var<Int>("count")
      Variable(count, 0)
      Action("advance") { count.becomes(count + 1).when(count < 1) }
    }
  }

  @SwiftTLAMacros.TLAObservable
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

guard result.action == .advance,
      result.before.count == 0,
      result.after.count == 1 else {
  throw FixtureError.invalidTransition
}
let stateCount = observable.state.count
guard stateCount == 1 else {
  throw FixtureError.invalidState
}

let beforeRejectedAction = observable.state
let rejected: Bool
do {
  _ = try await observable.apply(.advance)
  rejected = false
} catch {
  rejected = true
}
guard rejected else {
  throw FixtureError.expectedDisabledAction
}
let stateAfterRejectedAction = observable.state
guard stateAfterRejectedAction == beforeRejectedAction else {
  throw FixtureError.invalidRejection
}

private enum FixtureError: Error {
  case invalidTransition
  case invalidState
  case expectedDisabledAction
  case invalidRejection
}
