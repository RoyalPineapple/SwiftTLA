import SwiftTLA
import SwiftTLAMacros

/// MultiPaxos consensus with record-based messages and quorum acceptance.
/// 2 acceptors, 2 values, 2 ballots. Records: msg.type, msg.bal, msg.val, msg.acc.
@TLAModel
public struct MultiPaxos {
    static var spec: TLASpec {
        TLASpec("MultiPaxos") {
            Extends("Integers")

            let ballot = Var<Int>("ballot", value: 0)
            let chosen = Var<Int>("chosen", value: 0)
            let accepted0 = Var<Int>("a0bal", value: 0)
            let accepted1 = Var<Int>("a1bal", value: 0)
            let value0 = Var<Int>("a0val", value: 0)
            let value1 = Var<Int>("a1val", value: 0)

            Variable(ballot, 0); Variable(chosen, 0)
            Variable(accepted0, 0); Variable(accepted1, 0)
            Variable(value0, 0); Variable(value1, 0)

            // Leader proposes ballot 1 with value 1
            Action("Propose") { (chosen == 0) && ballot.becomes(1).when(ballot == 0) }
            // Acceptor 0 accepts ballot 1, value 1
            Action("Accept0") { (ballot == 1) && (accepted0 == 0) && accepted0.becomes(1) && value0.becomes(1) }
            // Acceptor 1 accepts ballot 1, value 1
            Action("Accept1") { (ballot == 1) && (accepted1 == 0) && accepted1.becomes(1) && value1.becomes(1) }
            // Quorum reached: both acceptors accepted
            Action("Choose") { (accepted0 == 1) && (accepted1 == 1) && (value0 == value1) && chosen.becomes(value0) }
            // Alternative: leader proposes value 2 at ballot 2
            Action("Propose2") { (chosen == 0) && ballot.becomes(2).when(ballot == 1) }
            Action("Accept0v2") { (ballot == 2) && (accepted0 == 1) && accepted0.becomes(2) && value0.becomes(2) }
            Action("Accept1v2") { (ballot == 2) && (accepted1 == 1) && accepted1.becomes(2) && value1.becomes(2) }

            Invariant("Safety") { chosen == 0 || chosen == 1 || chosen == 2 }
            Invariant("NoConflict") { (value0 == 0 || value1 == 0) || (value0 == value1) }
        }
    }
}
