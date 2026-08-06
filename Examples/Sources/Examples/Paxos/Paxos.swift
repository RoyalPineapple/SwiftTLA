import SwiftTLA

/// Paxos consensus algorithm (simplified: 1 leader, 2 acceptors, 2 values).
/// Uses record-based messages: msg.type, msg.bal, msg.val.
/// Proves that once a value is chosen, no other value can be chosen.
public struct Paxos {
    public static var spec: TLASpec {
        TLASpec("Paxos") {
            Extends("Integers")
            let phase = Var<Int>("phase", value: 0)
            let ballot = Var<Int>("ballot", value: 0)
            let value = Var<Int>("value", value: 0)  // 0=none, 1=v1, 2=v2
            let chosen = Var<Int>("chosen", value: 0) // 0=not chosen, 1=v1, 2=v2

            Variable(phase, 0); Variable(ballot, 0)
            Variable(value, 0); Variable(chosen, 0)

            // Leader selects a value and proposes
            Action("Propose") { (phase == 0) && value.becomes(1) && ballot.becomes(1) && phase.becomes(1) }
            // Acceptors accept if ballot >= current
            Action("Accept") { (phase == 1) && phase.becomes(2) && chosen.becomes(value) }
            // Alternative proposal
            Action("Propose2") { (phase == 0) && value.becomes(2) && ballot.becomes(2) && phase.becomes(1) }

            Invariant("ValueChosen") { (phase != 2) || (chosen >= 1 && chosen <= 2) }
        }
    }
}
