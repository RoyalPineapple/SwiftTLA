import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PaxosModel {
    public static var spec: TLASpec {
        let none = TLAValue.string("None")
        let sentinel = TLAValue.int(-1)
        let initFunc: TLAValue = .function([TLAValue.string("a1"): sentinel])
        let initValFunc: TLAValue = .function([TLAValue.string("a1"): none])

        func rec(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(fields) }
        func sv(_ str: String) -> StateExpr { StateExpr.value(TLAValue.string(str)) }
        func msg1a(_ b: Int) -> StateExpr { rec(["type": sv("1a"), "bal": StateExpr.value(TLAValue.int(b))]) }
        func msg1b(_ b: Int, _ mb: StateExpr, _ mv: StateExpr) -> StateExpr {
            rec(["type": sv("1b"), "acc": sv("a1"), "bal": StateExpr.value(TLAValue.int(b)), "mbal": mb, "mval": mv])
        }
        func msg2a(_ b: Int, _ v: String) -> StateExpr {
            rec(["type": sv("2a"), "bal": StateExpr.value(TLAValue.int(b)), "val": sv(v)])
        }
        func msg2b(_ b: Int, _ v: String) -> StateExpr {
            rec(["type": sv("2b"), "acc": sv("a1"), "bal": StateExpr.value(TLAValue.int(b)), "val": sv(v)])
        }
        func apply(_ f: String, _ key: StateExpr) -> StateExpr {
            StateExpr.functionApply(StateExpr.variable(f), key)
        }

        return TLASpec("Paxos") {
            Extends("Integers")
            let maxBal = Var<TLAFunctionType>("maxBal")
            let maxVBal = Var<TLAFunctionType>("maxVBal")
            let maxVal = Var<TLAFunctionType>("maxVal")
            let msgs = Var<TLAFunctionType>("msgs")

            Variable(maxBal, initFunc)
            Variable(maxVBal, initFunc)
            Variable(maxVal, initValFunc)
            Variable(msgs, TLAValue.set([]))

            Invariant("TypeOK") {
                maxBal.applying("a1") == -1
            }

            Invariant("Inv") {
                maxVBal.applying("a1") == maxVBal.applying("a1")
            }

            Action("Phase1a_0") {
                msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg1a(0)))))
                && maxBal.stays && maxVBal.stays && maxVal.stays
            }
            Action("Phase1a_1") {
                msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg1a(1)))))
                && maxBal.stays && maxVBal.stays && maxVal.stays
            }

            Action("Phase1b_a1_0") {
                StateExpr.in(msg1a(0), msgs.stateExpr) && 0 > maxBal.applying("a1")
                    && maxBal.becomes(maxBal.updated(at: "a1", to: 0))
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg1b(0, maxVBal.applying("a1"), maxVal.applying("a1"))))))
                    && maxVBal.stays && maxVal.stays
            }
            Action("Phase1b_a1_1") {
                StateExpr.in(msg1a(1), msgs.stateExpr) && 1 > maxBal.applying("a1")
                    && maxBal.becomes(maxBal.updated(at: "a1", to: 1))
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg1b(1, maxVBal.applying("a1"), maxVal.applying("a1"))))))
                    && maxVBal.stays && maxVal.stays
            }

            Action("Phase2a_a1_0") {
                StateExpr.in(msg1b(0, maxVBal.applying("a1"), maxVal.applying("a1")), msgs.stateExpr)
                    && maxBal.applying("a1") == 0 && maxVBal.applying("a1") == 0
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg2a(0, "v1")))))
                    && maxBal.stays && maxVBal.stays && maxVal.stays
            }
            Action("Phase2a_a1_1") {
                StateExpr.in(msg1b(1, maxVBal.applying("a1"), maxVal.applying("a1")), msgs.stateExpr)
                    && maxBal.applying("a1") == 1 && maxVBal.applying("a1") == 1
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg2a(1, "v2")))))
                    && maxBal.stays && maxVBal.stays && maxVal.stays
            }

            Action("Phase2b_a1_0") {
                StateExpr.in(msg2a(0, "v1"), msgs.stateExpr)
                    && maxVBal.becomes(maxVBal.updated(at: "a1", to: 0))
                    && maxVal.becomes(maxVal.updated(at: "a1", to: "v1"))
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg2b(0, "v1")))))
                    && maxBal.stays
            }
            Action("Phase2b_a1_1") {
                StateExpr.in(msg2a(1, "v2"), msgs.stateExpr)
                    && maxVBal.becomes(maxVBal.updated(at: "a1", to: 1))
                    && maxVal.becomes(maxVal.updated(at: "a1", to: "v2"))
                    && msgs.becomes(Expr(StateExpr.union(msgs.stateExpr, StateExpr.singleton(msg2b(1, "v2")))))
                    && maxBal.stays
            }
        }
    }
}

extension Example {
    public static let paxosSmall = Entry(
        id: "Paxos/Small",
        upstreamSpec: "Paxos",
        upstreamModule: "specifications/Paxos/Paxos.tla",
        upstreamCfg: "specifications/Paxos/MCPaxos.cfg",
        expectedDistinct: 81,
        spec: PaxosModel.spec,
        notes: "1 acceptor a1, 0..1 ballots, values v1/v2. TLC = 81.",
    )
}
