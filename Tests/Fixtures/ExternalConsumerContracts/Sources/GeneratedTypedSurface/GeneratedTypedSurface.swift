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
let transitionBefore = machine.state
try machine.send(action)

guard transitionBefore.value == 0,
      machine.state.value == 1,
      transitionBefore.packet.count == 0 && !transitionBefore.packet.ready,
      machine.state.packet.count == 1 && machine.state.packet.ready,
      transitionBefore.packet.labels == [.advance],
      machine.state.packet.labels == [.advance],
      transitionBefore.packet.text == "é",
      machine.state.packet.text == "é",
      transitionBefore.archive.map(\.count).sorted() == [0, 1],
      machine.state.archive.map(\.count).sorted() == [0, 1] else {
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
