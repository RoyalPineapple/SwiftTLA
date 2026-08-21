import SwiftTLA
import SwiftTLAMacros

/// Paxos consensus - Lamport's classic spec, small model: 1 acceptor, 1 value, 2 ballots.
/// Upstream: specifications/Paxos/Paxos.tla

extension Example {
    public static let paxosSmall = Entry(
        id: "Paxos/Small",
        upstreamSpec: "Paxos",
        upstreamModule: "specifications/Paxos/Paxos.tla",
        upstreamCfg: "specifications/Paxos/MCPaxos.cfg",
        expectedDistinct: 81,
        spec: paxosSpec(),
        notes: "1 acceptor, 1 value, 2 ballots. Phase1a/b + Phase2a/b.",
    )
}

private func paxosSpec() -> TLASpec {
    let none = TLAValue.string("None")
    let sentinel = TLAValue.int(-1)

    let maxBal = Var<TLAValue>("maxBal")
    let maxVBal = Var<TLAValue>("maxVBal")
    let maxVal = Var<TLAValue>("maxVal")
    let msgs = Var<TLAValue>("msgs")

    let initFunc: TLAValue = .function(["a1": sentinel])
    let initValFunc: TLAValue = .function(["a1": none])

    func rec(_ fields: [String: StateExpr]) -> StateExpr { StateExpr.record(fields) }
    func sv(_ str: String) -> StateExpr { .value(.string(str)) }

    func msg1a(_ b: Int) -> StateExpr { rec(["type": sv("1a"), "bal": .value(.int(b))]) }
    func msg1b(_ b: Int, _ mb: StateExpr, _ mv: StateExpr) -> StateExpr {
        rec(["type": sv("1b"), "acc": sv("a1"), "bal": .value(.int(b)), "mbal": mb, "mval": mv])
    }
    func msg2a(_ b: Int, _ v: String) -> StateExpr {
        rec(["type": sv("2a"), "bal": .value(.int(b)), "val": sv(v)])
    }
    func msg2b(_ b: Int, _ v: String) -> StateExpr {
        rec(["type": sv("2b"), "acc": sv("a1"), "bal": .value(.int(b)), "val": sv(v)])
    }

    func addMsg(_ m: StateExpr) -> ActionExpr {
        .assign(msgs.name, .union(msgs.stateExpr, StateExpr.singleton(m)))
    }

    return #spec("Paxos") {
        Extends(.integers)

        Variable(maxBal, initFunc)
        Variable(maxVBal, initFunc)
        Variable(maxVal, initValFunc)
        Variable(msgs, TLAValue.set([]))

        Invariant("TypeOK") {
            let ballotSet = StateExpr.setLiteral([.int(0), .int(1), .value(sentinel)])
            let valSet = StateExpr.setLiteral([sv("v1"), .value(none)])
            StateExpr.in(maxBal.stateExpr.applying("a1"), ballotSet)
                && StateExpr.in(maxVBal.stateExpr.applying("a1"), ballotSet)
                && StateExpr.in(maxVal.stateExpr.applying("a1"), valSet)
        }

        Invariant("Inv") {
            StateExpr.ifThenElse(
                maxVBal.stateExpr.applying("a1") == -1,
                maxVal.stateExpr.applying("a1") == "None",
                .value(.bool(true))
            )
        }

        // Phase 1a: leader sends ballot
        Action("Phase1a_0") { addMsg(msg1a(0)) && maxBal.stays && maxVBal.stays && maxVal.stays }
        Action("Phase1a_1") { addMsg(msg1a(1)) && maxBal.stays && maxVBal.stays && maxVal.stays }

        // Phase 1b: acceptor responds
        Action("Phase1b_a1_0") {
            StateExpr.in(msg1a(0), msgs.stateExpr) && 0 > maxBal.stateExpr.applying("a1")
                && .assign(maxBal.name, maxBal.stateExpr.updated(at: "a1", to: 0))
                && addMsg(msg1b(0, maxVBal.stateExpr.applying("a1"), maxVal.stateExpr.applying("a1")))
                && maxVBal.stays && maxVal.stays
        }
        Action("Phase1b_a1_1") {
            StateExpr.in(msg1a(1), msgs.stateExpr) && 1 > maxBal.stateExpr.applying("a1")
                && .assign(maxBal.name, maxBal.stateExpr.updated(at: "a1", to: 1))
                && addMsg(msg1b(1, maxVBal.stateExpr.applying("a1"), maxVal.stateExpr.applying("a1")))
                && maxVBal.stays && maxVal.stays
        }

        // Phase 2a: leader proposes (3 actions: b0_v1, b1_v1)
        Action("Phase2a_0_v1") {
            !StateExpr.in(msg2a(0, "v1"), msgs.stateExpr)
                && addMsg(msg2a(0, "v1"))
                && maxBal.stays && maxVBal.stays && maxVal.stays
        }
        Action("Phase2a_1_v1") {
            !StateExpr.in(msg2a(1, "v1"), msgs.stateExpr)
                && addMsg(msg2a(1, "v1"))
                && maxBal.stays && maxVBal.stays && maxVal.stays
        }

        // Phase 2b: acceptor votes (2 actions: ballot 0 + ballot 1)
        Action("Phase2b_a1_0") {
            StateExpr.in(msg2a(0, "v1"), msgs.stateExpr) && 0 >= maxBal.stateExpr.applying("a1")
                && .assign(maxBal.name, maxBal.stateExpr.updated(at: "a1", to: 0))
                && .assign(maxVBal.name, maxVBal.stateExpr.updated(at: "a1", to: 0))
                && .assign(maxVal.name, maxVal.stateExpr.updated(at: "a1", to: sv("v1")))
                && addMsg(msg2b(0, "v1"))
        }
        Action("Phase2b_a1_1") {
            StateExpr.in(msg2a(1, "v1"), msgs.stateExpr) && 1 >= maxBal.stateExpr.applying("a1")
                && .assign(maxBal.name, maxBal.stateExpr.updated(at: "a1", to: 1))
                && .assign(maxVBal.name, maxVBal.stateExpr.updated(at: "a1", to: 1))
                && .assign(maxVal.name, maxVal.stateExpr.updated(at: "a1", to: sv("v1")))
                && addMsg(msg2b(1, "v1"))
        }
    }
}
