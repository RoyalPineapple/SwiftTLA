import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct GeneratedTypedSurface {
  public struct Packet: Hashable, Sendable {
    let count: Int
    let ready: Bool
    let labels: Set<Step>
    let text: String
  }

  public enum Step: String, CaseIterable {
    case advance
  }

  static var spec: TLASpec {
    #spec("GeneratedTypedSurface") {
      let ConsistentCount = Invariant()
      let generatedTypedSurface = Algorithm(label: "GeneratedTypedSurface", scoped: { scope in
        let value = scope.sharedVar(initial: 0)
        let packet = scope.sharedVar(initial: Packet(count: 0, ready: false, labels: Set<Step>([Step.advance]), text: "e\u{301}"))
        let archive = scope.sharedVar(initial: SetExpr<Packet>.literal(
          Packet(count: 0, ready: false, labels: Set<Step>([Step.advance]), text: "e\u{301}"),
          Packet(count: 1, ready: false, labels: Set<Step>([Step.advance]), text: "e\u{301}")))
        Do(Step.advance, when: value < 1) {
          Assign(value, to: packet.count + 1)
          Assign(packet.count, to: packet.count + 1)
          Assign(packet.ready, to: true)
          Assign(archive, to: archive.union(SetExpr<Packet>.literal(
            Packet(count: 1, ready: false, labels: Set<Step>([Step.advance]), text: "e\u{301}"))))
        }
        ConsistentCount { packet.count == value && archive.cardinality == 2 }
      })
      generatedTypedSurface
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
let sourceText = "e\u{301}"
let requested = GeneratedTypedSurface.State(value: machine.state.value,
  packet: .init(count: machine.state.packet.count, ready: machine.state.packet.ready,
    labels: machine.state.packet.labels, text: "\(sourceText)"), archive: machine.state.archive)
guard try GeneratedTypedSurface.makeMachine(requested).snapshot == machine.snapshot else {
  throw FixtureError.invalidTransition
}
let action: GeneratedTypedSurface.Action = .advance
let transition = try machine.send(action)

guard transition.action == action,
      transition.before.value == 0,
      transition.after.value == 1,
      transition.before.packet.count == 0 && !transition.before.packet.ready,
      transition.after.packet.count == 1 && transition.after.packet.ready,
      transition.before.packet.labels == [.advance],
      transition.after.packet.labels == [.advance],
      transition.before.packet.text == "é",
      transition.after.packet.text == "é",
      transition.before.archive.map(\.count).sorted() == [0, 1],
      transition.after.archive.map(\.count).sorted() == [0, 1] else {
  throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
  case invalidTransition
}

guard let packetToken = TLAStateProjection.Token(validating: "packet") else {
  throw FixtureError.invalidTransition
}
let projection = try machine.formalProjection(of: machine.snapshot)
guard let formalPacket = projection.value(for: packetToken),
      GeneratedTypedSurface.Packet(formalValue: formalPacket) == .init(count: 1, ready: true, labels: [.advance], text: "é") else {
  throw FixtureError.invalidTransition
}
