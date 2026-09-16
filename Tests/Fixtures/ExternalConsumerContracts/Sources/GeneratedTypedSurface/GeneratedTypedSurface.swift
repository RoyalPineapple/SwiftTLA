import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct GeneratedTypedSurface {
  public struct Packet: Hashable, Sendable {
    let count: Int
    let ready: Bool
  }

  enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("GeneratedTypedSurface") { scope in
      let value = scope.sharedVar(_name: "value", initial: 0)
      let packet = scope.sharedVar(_name: "packet", initial: Packet(count: 0, ready: false))
      Algorithm("GeneratedTypedSurface") {
        Do(Step.advance, when: value < 1) {
          Assign(value, to: packet.count + 1)
          Assign(packet.count, to: packet.count + 1)
          Assign(packet.ready, to: true)
        }
      }
      Invariant("ConsistentCount") { packet.count == value }
    }
  }
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}

requireSendable(GeneratedTypedSurface.self)
requireSendable(GeneratedTypedSurface.State.self)
requireSendable(GeneratedTypedSurface.Action.self)
requireSendable(GeneratedTypedSurface.Transition.self)
requireSendable(GeneratedTypedSurface.Packet.self)

var machine = try GeneratedTypedSurface.makeMachine()
let action: GeneratedTypedSurface.Action = .advance
let transition = try machine.send(action)

guard transition.action == action,
      transition.before.value == 0,
      transition.after.value == 1,
      transition.before.packet == .init(count: 0, ready: false),
      transition.after.packet == .init(count: 1, ready: true),
      GeneratedTypedSurface.Packet(formalValue: transition.after.packet.tlaValue) == transition.after.packet else {
  throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
  case invalidTransition
}
