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

let observable = await MainActor.run { ObservableHost.Observable() }
let result = try await observable._advance()

precondition(result.action == .advance)
precondition(result.before.count == 0)
precondition(result.after.count == 1)
let stateCount = observable.state.count
precondition(stateCount == 1)

let beforeRejectedAction = observable.tlaSnapshot()
do {
  _ = try await observable._advance()
  fatalError("Expected disabled action")
} catch {
  let stateAfterRejectedAction = observable.tlaSnapshot()
  precondition(stateAfterRejectedAction == beforeRejectedAction)
}
